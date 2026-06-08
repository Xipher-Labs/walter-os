#!/usr/bin/env bats
# Static assertions for subscription-router deploy smoke tests.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
  PATTERN_DIR="$ROUTER_ROOT/subscription-router-pattern"
  LITELLM_CONFIG="$ROUTER_ROOT/litellm/config.yaml"
  LITELLM_COMPOSE="$ROUTER_ROOT/litellm/compose.yml"
}

assert_router_deploy_contract() {
  local router="$1"
  local port="$2"
  local key_env="$3"
  local litellm_aliases="$4"
  local deploy="$ROUTER_ROOT/$router/deploy.sh"

  [[ -x "$deploy" ]]
  grep -Fq 'subscription-router-pattern/deploy-router.sh' "$deploy"
  grep -Fq "\"$router\"" "$deploy"
  grep -Fq "\"$port\"" "$deploy"
  grep -Fq "\"$key_env\"" "$deploy"
  grep -Fq "\"$litellm_aliases\"" "$deploy"
}

make_fake_curl() {
  local fakebin="$1"
  cat > "$fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""
headers=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -H)
      headers+=("$2")
      shift 2
      ;;
    -w|--max-time|-X|--data-binary)
      shift 2
      ;;
    -sS)
      shift
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

{
  printf 'URL=%s\n' "$url"
  for header in "${headers[@]}"; do
    printf 'HEADER=%s\n' "$header"
  done
} >> "${CURL_LOG:?CURL_LOG required}"

if [[ "$url" == */v1/models ]]; then
  printf '{"data":[{"id":"router-model"}]}' > "$out"
else
  printf '{"choices":[{"message":{"content":"ROUTER_SMOKE_OK"}}]}' > "$out"
fi
printf '200'
SH
  chmod +x "$fakebin/curl"
}

make_fake_docker() {
  local fakebin="$1"
  cat > "$fakebin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  compose)
    exit 0
    ;;
  inspect)
    printf 'healthy\n'
    exit 0
    ;;
  logs)
    exit 0
    ;;
  *)
    echo "unexpected docker command: $*" >&2
    exit 1
    ;;
esac
SH
  chmod +x "$fakebin/docker"
}

run_deploy_smoke_with_litellm_env() {
  local env_line="$1"
  local tmpdir fakebin litellm_env
  tmpdir="$(mktemp -d)"
  fakebin="$tmpdir/bin"
  mkdir -p "$fakebin"
  make_fake_curl "$fakebin"
  litellm_env="$tmpdir/litellm.env"
  printf '%s\n' "$env_line" > "$litellm_env"

  CURL_LOG="$tmpdir/curl.log" \
    PATH="$fakebin:$PATH" \
    ROUTER_BASE_URL="http://router.local" \
    ROUTER_API_KEY="router-key" \
    LITELLM_ENV_FILE="$litellm_env" \
    LITELLM_BASE_URL="http://litellm.local" \
    LITELLM_SMOKE_MODELS="litellm-model" \
    "$PATTERN_DIR/deploy-smoke.sh" >/dev/null

  cat "$tmpdir/curl.log"
  rm -rf "$tmpdir"
}

@test "shared deploy smoke helper probes advertised router models" {
  local smoke="$PATTERN_DIR/deploy-smoke.sh"
  local curl_lines
  [[ -x "$smoke" ]]

  curl_lines="$(grep -F 'curl ' "$smoke")"
  grep -Fq '/v1/models' "$smoke"
  grep -Fq 'ROUTER_API_KEY' "$smoke"
  grep -Fq 'models_code=' "$smoke"
  grep -Fq 'HTTP ${models_code}' "$smoke"
  grep -Fq ': > "$tmp_body"' "$smoke"
  [[ "$curl_lines" != *'2>/dev/null'* ]]
  grep -Fq 'sed -n' "$smoke"
  grep -Fq 'failed to parse ${ROUTER_NAME} /v1/models response' "$smoke"
  grep -Fq 'payload.get("data"' "$smoke"
  grep -Fq '/v1/chat/completions' "$smoke"
  grep -Fq 'max_tokens' "$smoke"
  grep -Fq 'ROUTER_SMOKE_TIMEOUT_SECONDS' "$smoke"
  grep -Fq 'no advertised models' "$smoke"
}

@test "shared deploy smoke helper can verify LiteLLM alias hop" {
  local smoke="$PATTERN_DIR/deploy-smoke.sh"
  [[ -x "$smoke" ]]

  grep -Fq 'LITELLM_SMOKE_MODELS' "$smoke"
  grep -Fq 'LITELLM_BASE_URL' "$smoke"
  grep -Fq 'LITELLM_MASTER_KEY' "$smoke"
  grep -Fq 'LITELLM_API_KEY' "$smoke"
  grep -Fq 'LITELLM_ENV_FILE' "$smoke"
}

@test "router deploy helper waits for health and runs smoke" {
  local helper="$PATTERN_DIR/deploy-router.sh"
  [[ -x "$helper" ]]

  grep -Fq 'docker compose' "$helper"
  grep -Fq 'docker inspect' "$helper"
  grep -Fq 'State.Health.Status' "$helper"
  grep -Fq 'deploy-smoke.sh' "$helper"
  grep -Fq 'ROUTER_BASE_URL' "$helper"
  grep -Fq 'ROUTER_HEALTH_WAIT_ATTEMPTS:-190' "$helper"
  grep -Fq 'ROUTER_HEALTH_WAIT_SECONDS:-10' "$helper"
  grep -Fq 'LITELLM_SMOKE_MODELS="${LITELLM_SMOKE_MODELS-$DEFAULT_LITELLM_SMOKE_MODELS}"' "$helper"
  grep -Fq 'invalid router port' "$helper"
  grep -Fq 'invalid router API-key env var name' "$helper"
}

@test "each subscription router deploys with a real model smoke" {
  assert_router_deploy_contract "chatgpt-codex-router" "1456" "CCR_APIKEY" "codex-sub,codex-sub-think"
  assert_router_deploy_contract "claude-sub-router" "1457" "CSR_APIKEY" "claude-sub,claude-sub-opus"
  assert_router_deploy_contract "gemini-sub-router" "1458" "GSR_APIKEY" "gemini-sub,gemini-sub-flash"
}

@test "LiteLLM subscription aliases point at the current sub-routers" {
  [[ -f "$LITELLM_CONFIG" ]]

  grep -Fq "model_name: codex-sub" "$LITELLM_CONFIG"
  grep -Fq "model_name: codex-sub-think" "$LITELLM_CONFIG"
  grep -Fq "api_base: http://chatgpt-codex-router:1456/v1" "$LITELLM_CONFIG"
  grep -Fq "api_key: os.environ/CCR_APIKEY" "$LITELLM_CONFIG"

  grep -Fq "model_name: claude-sub" "$LITELLM_CONFIG"
  grep -Fq "model_name: claude-sub-opus" "$LITELLM_CONFIG"
  grep -Fq "api_base: http://claude-sub-router:1457/v1" "$LITELLM_CONFIG"
  grep -Fq "api_key: os.environ/CSR_APIKEY" "$LITELLM_CONFIG"

  grep -Fq "model_name: gemini-sub" "$LITELLM_CONFIG"
  grep -Fq "model_name: gemini-sub-flash" "$LITELLM_CONFIG"
  grep -Fq "api_base: http://gemini-sub-router:1458/v1" "$LITELLM_CONFIG"
  grep -Fq "api_key: os.environ/GSR_APIKEY" "$LITELLM_CONFIG"

  ! grep -Fq "claude-code-router:3456" "$LITELLM_CONFIG"
}

@test "LiteLLM compose passes subscription router keys" {
  [[ -f "$LITELLM_COMPOSE" ]]

  grep -Fq 'CCR_APIKEY: ${CCR_APIKEY:-}' "$LITELLM_COMPOSE"
  grep -Fq 'CSR_APIKEY: ${CSR_APIKEY:-}' "$LITELLM_COMPOSE"
  grep -Fq 'GSR_APIKEY: ${GSR_APIKEY:-}' "$LITELLM_COMPOSE"
}

@test "deploy-smoke strips unquoted inline comments from LiteLLM key" {
  run run_deploy_smoke_with_litellm_env "LITELLM_MASTER_KEY=sk-litellm # rotate"

  [ "$status" -eq 0 ]
  [[ "$output" == *"URL=http://litellm.local/v1/chat/completions"* ]]
  [[ "$output" == *"HEADER=Authorization: Bearer sk-litellm"* ]]
  [[ "$output" != *"Bearer sk-litellm # rotate"* ]]
}

@test "deploy-smoke preserves quoted hashes and strips trailing comments" {
  run run_deploy_smoke_with_litellm_env 'LITELLM_MASTER_KEY="sk#litellm" # rotate'

  [ "$status" -eq 0 ]
  [[ "$output" == *"HEADER=Authorization: Bearer sk#litellm"* ]]
  [[ "$output" != *"rotate"* ]]
}

@test "deploy-smoke preserves single-quoted literal comments" {
  run run_deploy_smoke_with_litellm_env "LITELLM_MASTER_KEY='sk # literal' # rotate"

  [ "$status" -eq 0 ]
  [[ "$output" == *"HEADER=Authorization: Bearer sk # literal"* ]]
  [[ "$output" != *"rotate"* ]]
}

@test "deploy-router strips unquoted inline comments from router API key" {
  local tmpdir fakebin router_dir log
  tmpdir="$(mktemp -d)"
  fakebin="$tmpdir/bin"
  router_dir="$tmpdir/router"
  mkdir -p "$fakebin" "$router_dir"
  make_fake_curl "$fakebin"
  make_fake_docker "$fakebin"
  printf '%s\n' "CCR_APIKEY=sk-router # rotate" > "$router_dir/.env"

  run env \
    CURL_LOG="$tmpdir/curl.log" \
    PATH="$fakebin:$PATH" \
    SVC_DIR="$router_dir" \
    ENV_FILE="$router_dir/.env" \
    ROUTER_HEALTH_WAIT_ATTEMPTS=1 \
    ROUTER_HEALTH_WAIT_SECONDS=1 \
    "$PATTERN_DIR/deploy-router.sh" "test-router" "1456" "CCR_APIKEY" ""

  [ "$status" -eq 0 ]
  log="$(cat "$tmpdir/curl.log")"
  [[ "$log" == *"URL=http://127.0.0.1:1456/v1/models"* ]]
  [[ "$log" == *"HEADER=Authorization: Bearer sk-router"* ]]
  [[ "$log" != *"Bearer sk-router # rotate"* ]]
  rm -rf "$tmpdir"
}

@test "deploy-router preserves env override literally" {
  local tmpdir fakebin router_dir log
  tmpdir="$(mktemp -d)"
  fakebin="$tmpdir/bin"
  router_dir="$tmpdir/router"
  mkdir -p "$fakebin" "$router_dir"
  make_fake_curl "$fakebin"
  make_fake_docker "$fakebin"
  printf '%s\n' "CCR_APIKEY=from-file" > "$router_dir/.env"

  run env \
    CURL_LOG="$tmpdir/curl.log" \
    PATH="$fakebin:$PATH" \
    SVC_DIR="$router_dir" \
    ENV_FILE="$router_dir/.env" \
    CCR_APIKEY="sk-router # literal" \
    ROUTER_HEALTH_WAIT_ATTEMPTS=1 \
    ROUTER_HEALTH_WAIT_SECONDS=1 \
    "$PATTERN_DIR/deploy-router.sh" "test-router" "1456" "CCR_APIKEY" ""

  [ "$status" -eq 0 ]
  log="$(cat "$tmpdir/curl.log")"
  [[ "$log" == *"HEADER=Authorization: Bearer sk-router # literal"* ]]
  rm -rf "$tmpdir"
}
