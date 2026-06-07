#!/usr/bin/env bash
# walter doctor — diagnose install state of Walter-OS on this Mac
#
# Usage:
#   walter doctor                  full check (local + remote)
#   walter doctor --client-only    local tools only, skip SSH/remote checks
set -euo pipefail

# Validate WALTER_OS_HOME before any use: must be an absolute path containing
# only safe characters. Reject single quotes, semicolons, $, backticks, etc.
# This prevents injection via check() even if eval is used inside.
# See: docs/operational/security-audit-2026-05-11.md P0-04
WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
if [[ ! "$WALTER_OS_HOME" =~ ^[A-Za-z0-9/_.-]+$ ]]; then
  echo "doctor: invalid WALTER_OS_HOME value (contains unsafe characters)" >&2
  exit 2
fi
WALTER_CONFIG="${WALTER_CONFIG:-$HOME/.config/walter-os}"

# ---------- arg parse ----------
CLIENT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --client-only) CLIENT_ONLY=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "doctor: unknown option: $arg" >&2; exit 2 ;;
  esac
done

source "$WALTER_OS_HOME/scripts/walter/lib/log.sh"

ok=0; warn=0; fail=0

# check() and checkw() run test commands via bash -c in a subshell.
# The cmd strings are hardcoded in this file (not attacker-controlled),
# but we use bash -c instead of eval to isolate each check and avoid
# polluting the main shell's environment.
check() {
  local label="$1" cmd="$2"
  if bash -c "$cmd" >/dev/null 2>&1; then
    log_ok "$label"
    ok=$((ok + 1))
  else
    log_err "$label"
    fail=$((fail + 1))
  fi
}
checkw() {
  local label="$1" cmd="$2"
  if bash -c "$cmd" >/dev/null 2>&1; then
    log_ok "$label"
    ok=$((ok + 1))
  else
    log_warn "$label"
    warn=$((warn + 1))
  fi
}
check_secret_runtime() {
  local secrets_file="$WALTER_CONFIG/secrets.env"
  local env_file="$WALTER_CONFIG/env"
  local has_infisical=0

  if [[ -n "${INFISICAL_CLIENT_ID:-}" ]] \
      || ([[ -f "$env_file" ]] && grep -qE '^(export[[:space:]]+)?INFISICAL_CLIENT_ID=.+' "$env_file" 2>/dev/null); then
    has_infisical=1
  fi

  if [[ "$has_infisical" -eq 1 && ! -f "$secrets_file" ]]; then
    log_ok "Infisical runtime configured (no legacy secrets.env)"
    ok=$((ok + 1))
  elif [[ "$has_infisical" -eq 1 && -f "$secrets_file" ]]; then
    log_warn "Infisical runtime configured; legacy plaintext secrets.env still exists"
    warn=$((warn + 1))
    check_legacy_secrets_file_mode "$secrets_file"
  elif [[ -f "$secrets_file" ]]; then
    log_warn "legacy plaintext secrets.env detected; migrate to Infisical machine identity"
    warn=$((warn + 1))
    check_legacy_secrets_file_mode "$secrets_file"
  else
    log_err "secrets runtime missing (configure Infisical identity or legacy secrets.env)"
    fail=$((fail + 1))
  fi
}
check_legacy_secrets_file_mode() {
  local secrets_file="$1"
  local mode

  mode="$(stat -f '%Lp' "$secrets_file" 2>/dev/null || stat -c '%a' "$secrets_file" 2>/dev/null || true)"
  if [[ "$mode" == "600" ]]; then
    log_ok "legacy secrets.env mode 600"
    ok=$((ok + 1))
  else
    log_warn "legacy secrets.env mode should be 600"
    warn=$((warn + 1))
  fi
}
check_legacy_secret_key() {
  local label="$1" key="$2"
  local secrets_file="$WALTER_CONFIG/secrets.env"

  if [[ ! -f "$secrets_file" ]]; then
    log_info "$label skipped (no legacy secrets.env; use Infisical runtime)"
    return
  fi

  if grep -E "^(export[[:space:]]+)?${key}=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d "'\"" | grep -q .; then
    log_ok "$label"
    ok=$((ok + 1))
  else
    log_warn "$label"
    warn=$((warn + 1))
  fi
}

log_step "Walter-OS doctor"

check "WALTER_OS_HOME exists ($WALTER_OS_HOME)" "[[ -d '$WALTER_OS_HOME' ]]"
check "AGENTS.md present"             "[[ -f '$WALTER_OS_HOME/AGENTS.md' ]]"
check "\$HOME/.claude/CLAUDE.md symlink"   "[[ -L $HOME/.claude/CLAUDE.md ]]"
check "\$HOME/.codex/AGENTS.md symlink"    "[[ -L $HOME/.codex/AGENTS.md ]]"
check_secret_runtime

check "brew installed"                "command -v brew"
check "infisical CLI"                 "command -v infisical"
check "infisical session valid"       "infisical user get token 2>&1 | grep -q '^eyJ'"
check "gh CLI"                        "command -v gh"
check "gh authenticated"              "gh auth status 2>&1 | grep -qi 'logged in'"
check "cloudflared"                   "command -v cloudflared"
check "hcloud CLI"                    "command -v hcloud"
check "rclone"                        "command -v rclone"
check "jq"                            "command -v jq"
check "docker daemon (mac orbstack)"  "docker info"

if [[ $CLIENT_ONLY -ne 1 ]]; then
  checkw "ssh walter-vm reachable"    "ssh -o ConnectTimeout=5 walter-vm 'true'"
fi
check_legacy_secret_key "Anthropic API key set" "ANTHROPIC_API_KEY"
check_legacy_secret_key "OpenAI API key set" "OPENAI_API_KEY"

echo
echo "Result: $ok ok / $warn warn / $fail fail"
[[ $fail -gt 0 ]] && exit 1 || exit 0
