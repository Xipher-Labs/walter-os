#!/usr/bin/env bash
# secrets-identity-init.sh — one-time bootstrap of the local credential-store
# entry that holds the Infisical Machine Identity.
#
# Stores only the bootstrap identity in an OS credential store:
#   - macOS: Keychain via `security`
#   - Linux: Secret Service via `secret-tool`, or `pass` + GPG
#
# Hardware security keys are optional hardening configured at the OS/keyring
# layer. This script must not require a YubiKey to make first-run onboarding work
# for operators using Touch ID, login password, Secret Service, or pass.

set -euo pipefail

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "%s %s\n" "${c_g}✓${c_0}" "$*"; }
info() { printf "%s %s\n" "${c_d}·${c_0}" "$*"; }
warn() { printf "%s %s\n" "${c_y}!${c_0}" "$*"; }
err()  { printf "%s %s\n" "${c_r}✗${c_0}" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

STORE="auto"
DOMAIN_ARG=""
ASSUME_YES=0
REPLACING_IDENTITY=0

IDENTITY_SERVICE="walter-os.infisical-identity"
IDENTITY_ACCOUNT="${USER:-operator}"
PASS_ENTRY="${WALTER_SECRETS_PASS_ENTRY:-walter-os/infisical-identity}"

usage() {
  cat <<USAGE
Usage: walter-os secrets-identity-init [options]

Options:
  --store <auto|macos-keychain|secret-service|pass>
      Credential-store backend. auto chooses macOS Keychain on Darwin,
      Secret Service on Linux when available, then pass.
  --domain <url>
      Infisical URL. Fallback order:
      flag -> INFISICAL_DOMAIN -> WALTER_INFISICAL_DOMAIN -> https://secrets.\$WALTER_DOMAIN
  -y, --yes
      Replace an existing identity entry without an interactive prompt.
  -h, --help
      Show this help.

This command stores the Infisical Machine Identity in an OS credential store.
It never writes plaintext bootstrap credentials to a dotenv file.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --store)
      if [[ $# -lt 2 ]]; then
        err "--store requires a value"
        exit 2
      fi
      STORE="${2:-}"
      shift 2
      ;;
    --domain)
      if [[ $# -lt 2 ]]; then
        err "--domain requires a value"
        exit 2
      fi
      DOMAIN_ARG="${2:-}"
      shift 2
      ;;
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

resolve_domain() {
  local domain=""
  if [[ -n "$DOMAIN_ARG" ]]; then
    domain="$DOMAIN_ARG"
  elif [[ -n "${INFISICAL_DOMAIN:-}" ]]; then
    domain="$INFISICAL_DOMAIN"
  elif [[ -n "${WALTER_INFISICAL_DOMAIN:-}" ]]; then
    domain="$WALTER_INFISICAL_DOMAIN"
  elif [[ -n "${WALTER_DOMAIN:-}" ]]; then
    domain="https://secrets.${WALTER_DOMAIN}"
  fi

  if [[ -z "$domain" ]]; then
    err "Infisical domain is not configured."
    err "Pass --domain, export INFISICAL_DOMAIN, export WALTER_INFISICAL_DOMAIN,"
    err "or set WALTER_DOMAIN so https://secrets.\$WALTER_DOMAIN can be derived."
    exit 5
  fi

  domain="${domain%/}"
  if [[ "$domain" != https://* ]]; then
    err "Infisical domain must use https:// and must not rely on redirects."
    err "Received: $domain"
    exit 5
  fi

  printf "%s\n" "$domain"
}

secret_service_available() {
  command -v secret-tool >/dev/null 2>&1 || return 1

  local probe_service="walter-os.infisical-identity.probe.$$"
  local store_cmd=(secret-tool store --label="Walter-OS credential-store probe" service "$probe_service" account "$IDENTITY_ACCOUNT")

  if command -v timeout >/dev/null 2>&1; then
    printf "probe" | timeout 5s "${store_cmd[@]}" >/dev/null 2>&1 || return 1
  else
    printf "probe" | "${store_cmd[@]}" >/dev/null 2>&1 || return 1
  fi

  secret-tool clear service "$probe_service" account "$IDENTITY_ACCOUNT" >/dev/null 2>&1 || true
}

resolve_store() {
  case "$STORE" in
    auto)
      case "$(uname -s)" in
        Darwin)
          printf "%s\n" "macos-keychain"
          ;;
        Linux)
          if secret_service_available; then
            printf "%s\n" "secret-service"
          elif command -v pass >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
            printf "%s\n" "pass"
          else
            err "No supported Linux credential store found."
            err "Install libsecret-tools for Secret Service:"
            err "  sudo apt-get install -y libsecret-tools gnome-keyring"
            err "Or configure pass + GPG:"
            err "  sudo apt-get install -y pass gnupg"
            exit 3
          fi
          ;;
        *)
          err "Unsupported OS: $(uname -s). Supported: macOS and Linux."
          exit 3
          ;;
      esac
      ;;
    macos-keychain|secret-service|pass)
      printf "%s\n" "$STORE"
      ;;
    *)
      err "Invalid --store value: $STORE"
      err "Expected: auto, macos-keychain, secret-service, pass"
      exit 2
      ;;
  esac
}

require_cmd() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "$cmd not found. Install: $hint"
    exit 4
  fi
}

json_string() {
  jq -Rs .
}

identity_json() {
  local client_id_json client_secret_json domain_json
  client_id_json="$(printf "%s" "$CLIENT_ID" | json_string)"
  client_secret_json="$(printf "%s" "$CLIENT_SECRET" | json_string)"
  domain_json="$(printf "%s" "$INFISICAL_DOMAIN_RESOLVED" | json_string)"
  printf '{"client_id":%s,"client_secret":%s,"domain":%s}\n' \
    "$client_id_json" "$client_secret_json" "$domain_json"
}

infisical_login_json() {
  local client_id_json client_secret_json
  client_id_json="$(printf "%s" "$CLIENT_ID" | json_string)"
  client_secret_json="$(printf "%s" "$CLIENT_SECRET" | json_string)"
  printf '{"clientId":%s,"clientSecret":%s}\n' "$client_id_json" "$client_secret_json"
}

infisical_api_base() {
  local domain="${1%/}"
  if [[ "$domain" == */api ]]; then
    printf "%s\n" "$domain"
  else
    printf "%s/api\n" "$domain"
  fi
}

verify_infisical_identity() {
  local api_base login_url http_status
  api_base="$(infisical_api_base "$INFISICAL_DOMAIN_RESOLVED")"
  login_url="${api_base}/v1/auth/universal-auth/login"

  http_status="$(infisical_login_json | curl --silent --show-error \
    --connect-timeout 5 \
    --max-time 20 \
    --output /dev/null \
    --write-out "%{http_code}" \
    --request POST \
    --url "$login_url" \
    --header "Content-Type: application/json" \
    --data-binary @-)" || return 1

  [[ "$http_status" =~ ^2[0-9][0-9]$ ]]
}

preflight_backend() {
  local backend="$1"
  case "$backend" in
    macos-keychain)
      [[ "$(uname -s)" == "Darwin" ]] || {
        err "macos-keychain backend requires macOS."
        exit 4
      }
      require_cmd security "built into macOS; verify /usr/bin/security exists"
      ;;
    secret-service)
      require_cmd secret-tool "sudo apt-get install -y libsecret-tools gnome-keyring"
      if ! secret_service_available; then
        err "secret-service backend is installed but not usable."
        err "Start or unlock a Secret Service provider, or use --store pass."
        exit 4
      fi
      ;;
    pass)
      require_cmd pass "sudo apt-get install -y pass"
      require_cmd gpg "sudo apt-get install -y gnupg"
      ;;
  esac
}

identity_exists() {
  local backend="$1"
  case "$backend" in
    macos-keychain)
      security find-generic-password -s "$IDENTITY_SERVICE" -a "$IDENTITY_ACCOUNT" >/dev/null 2>&1
      ;;
    secret-service)
      secret-tool lookup service "$IDENTITY_SERVICE" account "$IDENTITY_ACCOUNT" >/dev/null 2>&1
      ;;
    pass)
      pass show "$PASS_ENTRY" >/dev/null 2>&1
      ;;
  esac
}

identity_store() {
  local backend="$1" json="$2"
  case "$backend" in
    macos-keychain)
      # macOS `security add-generic-password -w` without an argument prompts
      # twice and reads from stdin. Feed the compact JSON twice so the identity
      # never appears in `security -w <secret>` process arguments.
      printf "%s\n%s\n" "$json" "$json" | security add-generic-password \
        -s "$IDENTITY_SERVICE" \
        -a "$IDENTITY_ACCOUNT" \
        -T "" \
        -U \
        -j "Walter-OS Infisical Machine Identity (OS credential store, 12h session)" \
        -w
      ;;
    secret-service)
      printf "%s" "$json" | secret-tool store \
        --label="Walter-OS Infisical Machine Identity" \
        service "$IDENTITY_SERVICE" \
        account "$IDENTITY_ACCOUNT"
      ;;
    pass)
      printf "%s\n" "$json" | pass insert -m -f "$PASS_ENTRY"
      ;;
  esac
}

confirm_replace() {
  [[ "$ASSUME_YES" -eq 1 ]] && return 0

  printf "Replace it? [y/N] "
  local ans=""
  IFS= read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

INFISICAL_DOMAIN_RESOLVED="$(resolve_domain)"
BACKEND="$(resolve_store)"

step "Preflight"
require_cmd jq "brew install jq  # or: sudo apt-get install -y jq"
require_cmd curl "brew install curl  # or: sudo apt-get install -y curl"
require_cmd infisical "brew install infisical/get-cli/infisical  # Linux: see Infisical CLI docs"
preflight_backend "$BACKEND"
ok "Credential store: $BACKEND"
ok "Infisical domain: $INFISICAL_DOMAIN_RESOLVED"
ok "Infisical CLI: $(infisical --version 2>&1 | head -1)"

step "Existing identity entry?"
if identity_exists "$BACKEND"; then
  warn "An entry already exists for service=$IDENTITY_SERVICE account=$IDENTITY_ACCOUNT."
  if ! confirm_replace; then
    info "Aborted."
    exit 0
  fi
  REPLACING_IDENTITY=1
  info "Keeping prior entry until the replacement is verified and stored."
else
  info "No prior entry."
fi

step "Collect Machine Identity credentials"
echo "From Infisical → project → Access Control → Machine Identities → <your identity>:"
printf "  client_id: "
IFS= read -r CLIENT_ID
printf "  client_secret (hidden): "
IFS= read -rs CLIENT_SECRET
echo

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  err "Both client_id and client_secret are required."
  exit 6
fi

step "Verify credentials against Infisical"
if ! verify_infisical_identity >/dev/null 2>&1; then
  err "Login failed. Check the Machine Identity, permissions, and domain."
  exit 7
fi
ok "Credentials verified."

step "Store identity in local credential store"
IDENTITY_JSON="$(identity_json)"

identity_store "$BACKEND" "$IDENTITY_JSON"
unset IDENTITY_JSON CLIENT_SECRET
if [[ "$REPLACING_IDENTITY" -eq 1 ]]; then
  ok "Replaced Infisical Machine Identity in $BACKEND."
else
  ok "Stored Infisical Machine Identity in $BACKEND."
fi

cat <<NEXT

${c_b}Done.${c_0} Verify from a fresh shell:

  ${c_d}# Should trigger your OS credential-store prompt if configured:${c_0}
  walter_secrets_load
  walter_secrets_status

Hardware security keys are optional. To require one, configure that policy in
your OS credential store, smartcard, PAM, Secret Service, or pass/GPG setup.

To reset:
  walter-os secrets-identity-init

To revoke a lost device:
  Open Infisical → project → Machine Identities → delete this device identity.
NEXT
