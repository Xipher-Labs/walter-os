#!/usr/bin/env bash
# daily-audit-gate.sh
# Hooked into Claude Code's SessionStart event.
#
# Behavior:
# - If today's audit hasn't run yet: kick it off in BACKGROUND, allow session
#   to start with an info banner. Don't block on first-run-of-the-day latency.
# - If today's audit ran AND found CRITICAL: block the session.
# - Otherwise: allow with a status summary banner.
#
# This trades a tiny window (between session start and audit completion) for
# instant session startup. The audit hook itself is launchd-scheduled at 08:30
# so on most days the audit is already done before the first session.

set -uo pipefail

# Drain stdin so Claude Code's hook protocol doesn't block. The payload
# isn't used here — gate decisions are based on local state, not the JSON
# event — but reading is required.
cat >/dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
TRUSTED_WALTER_CONFIG="$WALTER_CONFIG"
TRUSTED_WALTER_OS_HOME="$REPO_ROOT"

# Load operator env via the allowlist parser, NOT bash `source` (audit
# P1-09). Sourcing the raw file lets any attacker who can write to
# ~/.config/walter-os/env execute arbitrary shell at every Claude Code
# session start.
_walter_env_loader_lib="${TRUSTED_WALTER_OS_HOME}/scripts/walter/lib/env-loader.sh"
if [[ -f "$_walter_env_loader_lib" ]]; then
  # shellcheck source=/dev/null
  source "$_walter_env_loader_lib"
  WALTER_ENV_ALLOWLIST_ROOT="$TRUSTED_WALTER_CONFIG" \
  WALTER_ENV_PROTECTED_KEYS="WALTER_CONFIG WALTER_OS_HOME TRUSTED_WALTER_CONFIG TRUSTED_WALTER_OS_HOME" \
    walter_env_load_allowlist "${TRUSTED_WALTER_CONFIG}/env"
fi
unset _walter_env_loader_lib

WALTER_CONFIG="$TRUSTED_WALTER_CONFIG"
WALTER_OS_HOME="$TRUSTED_WALTER_OS_HOME"

TODAY="$(date +%Y-%m-%d)"
STATUS="${WALTER_CONFIG}/audit-status.json"
TODAY_REPORT="${WALTER_CONFIG}/audit-${TODAY}.md"
AUDIT_SCRIPT="${WALTER_OS_HOME}/skills/daily-supply-chain-audit/scripts/audit.sh"

allow() {
  local notice="${1:-}"
  if [[ -n "$notice" ]]; then
    # Escape inner quotes for JSON
    notice="${notice//\\/\\\\}"
    notice="${notice//\"/\\\"}"
    echo "{\"decision\":\"allow\",\"systemMessage\":\"${notice}\"}"
  else
    echo '{"decision":"allow"}'
  fi
  exit 0
}

block() {
  local reason="$1"
  reason="${reason//\\/\\\\}"
  reason="${reason//\"/\\\"}"
  echo "{\"decision\":\"block\",\"reason\":\"${reason}\"}"
  exit 0
}

# 1. If the latest status JSON shows CRITICAL findings from any prior run that
#    hasn't been resolved, hard-block. Do this before anything else.
if [[ -f "$STATUS" ]] && command -v jq >/dev/null 2>&1; then
  SEV="$(jq -r '.severity // 0' "$STATUS" 2>/dev/null || echo 0)"
  STATUS_DATE="$(jq -r '.date // "unknown"' "$STATUS" 2>/dev/null || echo unknown)"
  if [[ "$SEV" -ge 3 ]]; then
    block "Walter-OS audit (${STATUS_DATE}): CRITICAL findings unresolved. See ${TODAY_REPORT}. Run 'walter-os ack <id>' or fix before continuing."
  fi
fi

# 2. If today's audit hasn't run, kick it off in background and let session
#    start. The hook returns immediately.
if [[ ! -f "$TODAY_REPORT" ]]; then
  if [[ -x "$AUDIT_SCRIPT" ]]; then
    nohup "$AUDIT_SCRIPT" >>"${WALTER_CONFIG}/audit.log" 2>>"${WALTER_CONFIG}/audit.err" &
    disown 2>/dev/null || true
    allow "Walter-OS audit started in background. Check ${TODAY_REPORT} when ready."
  else
    allow "Walter-OS audit script missing at ${AUDIT_SCRIPT}. Skipping gate."
  fi
fi

# 3. Today's audit completed — surface its severity.
if [[ -f "$STATUS" ]] && command -v jq >/dev/null 2>&1; then
  SEV="$(jq -r '.severity // 0' "$STATUS")"
  case "$SEV" in
    2) allow "Walter-OS audit ${TODAY}: HIGH-severity findings. See ${TODAY_REPORT}" ;;
    1) allow "Walter-OS audit ${TODAY}: informational findings only." ;;
    *) allow ;;
  esac
fi

allow
