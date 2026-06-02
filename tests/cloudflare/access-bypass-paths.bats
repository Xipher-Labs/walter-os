#!/usr/bin/env bats
# tests/cloudflare/access-bypass-paths.bats
#
# Closes #170: external OAuth callbacks and webhooks need path-scoped
# Cloudflare Access bypass apps, while the rest of each service hostname
# stays behind the normal email-domain Access policy.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CF_SCRIPT="$REPO_ROOT/setup/walter-host/cloudflare/04-create-access.sh"
  CF_README="$REPO_ROOT/setup/walter-host/cloudflare/README.md"
  [[ -f "$CF_SCRIPT" && -f "$CF_README" ]] || skip "missing Cloudflare fixtures"
}

_install_fake_curl() {
  local bin_dir="$1"
  cat > "$bin_dir/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
payload=""
url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -d|--data|--data-raw|--data-binary)
      payload="$2"
      shift 2
      ;;
    -H)
      shift 2
      ;;
    -s|-S|-sS)
      shift
      ;;
    https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

jq -cn --arg method "$method" --arg url "$url" --arg payload "$payload" \
  '{method:$method,url:$url,payload:$payload}' >> "${CURL_LOG:?CURL_LOG required}"

case "$url" in
  *"/zones?name=example.test&account.id=account-id")
    printf '{"success":true,"result":[{"id":"zone-id"}]}\n'
    ;;
  *"/zones/zone-id")
    printf '{"success":true,"result":{"status":"active"}}\n'
    ;;
  *"/access/identity_providers")
    printf '{"success":true,"result":[{"id":"otp-id","type":"onetimepin"}]}\n'
    ;;
  *"/access/apps")
    if [[ "$method" == "GET" ]]; then
      cat <<'JSON'
{"success":true,"result":[
  {"id":"existing-postiz-bypass","domain":"postiz.example.test/integrations/social/*"},
  {"id":"existing-n8n-bypass","domain":"n8n.example.test/webhook/*"}
]}
JSON
    else
      printf '{"success":true,"result":{"id":"created-app"}}\n'
    fi
    ;;
  *"/access/apps/"*"/policies")
    if [[ "$method" == "GET" ]]; then
      app_id="${url%/policies}"
      app_id="${app_id##*/}"
      case "$app_id" in
        existing-postiz-bypass)
          printf '{"success":true,"result":[{"id":"policy-postiz","name":"Bypass /integrations/social/*","decision":"bypass"}]}\n'
          ;;
        existing-n8n-bypass)
          printf '{"success":true,"result":[{"id":"policy-n8n","name":"Bypass /webhook/*","decision":"bypass"}]}\n'
          ;;
        *)
          printf '{"success":true,"result":[{"id":"policy-%s","name":"Allow @example.test"}]}\n' "$app_id"
          ;;
      esac
    else
      printf '{"success":true,"result":{"id":"policy-created"}}\n'
    fi
    ;;
  *"/access/apps/"*)
    printf '{"success":true,"result":{"id":"updated-app"}}\n'
    ;;
  *)
    printf '{"success":false,"errors":[{"message":"unexpected URL"}]}\n'
    ;;
esac
FAKE_CURL
  chmod +x "$bin_dir/curl"
}

@test "#170: default bypass paths cover Postiz OAuth and n8n webhooks" {
  grep -qF '"postiz:/integrations/social/*"' "$CF_SCRIPT"
  grep -qF '"n8n:/webhook/*"' "$CF_SCRIPT"
}

@test "#170: operator can append custom bypass paths via env var" {
  grep -qF 'WALTER_CF_ACCESS_BYPASS_PATHS' "$CF_SCRIPT"
  grep -qF 'BYPASS_PATHS+=("$entry")' "$CF_SCRIPT"
  grep -qF "tr '[:space:]' '\\n'" "$CF_SCRIPT"
}

@test "#170: bypass apps are path-scoped and idempotent" {
  grep -qF 'bypass_domain="${hostname}${bypass_path}"' "$CF_SCRIPT"
  grep -qF 'access_app_payload "$bypass_name" "$bypass_domain" "false"' "$CF_SCRIPT"
  grep -qF 'access/apps/$bypass_app_id" -d "$bypass_app_payload"' "$CF_SCRIPT"
  grep -qF 'access/apps" -d "$bypass_app_payload"' "$CF_SCRIPT"
}

@test "#170: bypass policy allows everyone only on the path app" {
  grep -qF 'access_bypass_policy_payload()' "$CF_SCRIPT"
  grep -qF 'decision: "bypass"' "$CF_SCRIPT"
  grep -qF 'include: [{everyone: {}}]' "$CF_SCRIPT"
  grep -qF 'access_bypass_policy_payload "$bypass_policy_name"' "$CF_SCRIPT"
}

@test "#170: mocked CF API updates existing path apps and policies" {
  tmpdir="$(mktemp -d)"
  log_file="$tmpdir/curl.jsonl"
  export CURL_LOG="$log_file"
  _install_fake_curl "$tmpdir"

  run env \
    PATH="$tmpdir:$PATH" \
    CF_EMAIL="operator@example.test" \
    CF_KEY="global-api-key" \
    CF_ACCOUNT="account-id" \
    bash "$CF_SCRIPT" example.test example.test otp

  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]

  jq -er '
    select(.method == "PUT")
    | select(.url | endswith("/access/apps/existing-postiz-bypass"))
    | .payload
    | fromjson
    | select(.name == "Walter-VM postiz bypass (integrations-social-wildcard)")
    | select(.domain == "postiz.example.test/integrations/social/*")
    | select(.type == "self_hosted")
    | select(.allowed_idps == ["otp-id"])
    | select(.auto_redirect_to_identity == false)
  ' "$log_file" >/dev/null

  jq -er '
    select(.method == "PUT")
    | select(.url | endswith("/access/apps/existing-n8n-bypass"))
    | .payload
    | fromjson
    | select(.name == "Walter-VM n8n bypass (webhook-wildcard)")
    | select(.domain == "n8n.example.test/webhook/*")
    | select(.type == "self_hosted")
    | select(.allowed_idps == ["otp-id"])
    | select(.auto_redirect_to_identity == false)
  ' "$log_file" >/dev/null

  jq -er '
    select(.method == "PUT")
    | select(.url | endswith("/access/apps/existing-postiz-bypass/policies/policy-postiz"))
    | .payload
    | fromjson
    | select(.name == "Bypass /integrations/social/*")
    | select(.decision == "bypass")
    | select(.include == [{"everyone":{}}])
    | select(.precedence == 1)
  ' "$log_file" >/dev/null

  jq -er '
    select(.method == "PUT")
    | select(.url | endswith("/access/apps/existing-n8n-bypass/policies/policy-n8n"))
    | .payload
    | fromjson
    | select(.name == "Bypass /webhook/*")
    | select(.decision == "bypass")
    | select(.include == [{"everyone":{}}])
    | select(.precedence == 1)
  ' "$log_file" >/dev/null
}

@test "#170: duplicate operator bypass entries are emitted once" {
  tmpdir="$(mktemp -d)"
  log_file="$tmpdir/curl.jsonl"
  export CURL_LOG="$log_file"
  _install_fake_curl "$tmpdir"

  run env \
    PATH="$tmpdir:$PATH" \
    CF_EMAIL="operator@example.test" \
    CF_KEY="global-api-key" \
    CF_ACCOUNT="account-id" \
    WALTER_CF_ACCESS_BYPASS_PATHS="postiz:/integrations/social/* n8n:/webhook/*" \
    bash "$CF_SCRIPT" example.test example.test otp

  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]

  postiz_updates=$(jq -r '
    select(.method == "PUT")
    | select(.url | endswith("/access/apps/existing-postiz-bypass"))
    | .url
  ' "$log_file" | wc -l | tr -d ' ')
  n8n_updates=$(jq -r '
    select(.method == "PUT")
    | select(.url | endswith("/access/apps/existing-n8n-bypass"))
    | .url
  ' "$log_file" | wc -l | tr -d ' ')

  [ "$postiz_updates" -eq 1 ]
  [ "$n8n_updates" -eq 1 ]
}

@test "#170: runbook documents defaults and narrow-path warning" {
  grep -qF 'postiz.${WALTER_DOMAIN}/integrations/social/*' "$CF_README"
  grep -qF 'n8n.${WALTER_DOMAIN}/webhook/*' "$CF_README"
  grep -qF 'Keep entries as narrow as possible' "$CF_README"
}
