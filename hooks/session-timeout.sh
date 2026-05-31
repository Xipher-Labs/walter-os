#!/usr/bin/env bash
# hooks/session-timeout.sh
#
# UserPromptSubmit hook for time-bounded Walter-OS sessions.
# Parent: #122 OSS Trust epic, AC-2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"

INPUT="$(cat)"

_user_prompt_json() {
  local decision="$1" reason="${2:-}"
  if [[ -n "$reason" ]]; then
    jq -nc \
      --arg decision "$decision" \
      --arg reason "$reason" \
      '{
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          permissionDecision: $decision,
          permissionDecisionReason: $reason
        }
      }'
  else
    jq -nc \
      --arg decision "$decision" \
      '{
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          permissionDecision: $decision
        }
      }'
  fi
}

_block_fixed_no_jq() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","permissionDecision":"block","permissionDecisionReason":"Walter-OS session timeout: jq missing - failing closed for safety."}}'
  exit 0
}

_block() {
  _user_prompt_json "block" "$1"
  exit 0
}

_allow() {
  _user_prompt_json "allow"
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  _block_fixed_no_jq
fi

if [[ -z "$INPUT" ]]; then
  _block "Walter-OS session timeout: empty hook input — failing closed for safety."
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  _block "Walter-OS session timeout: malformed hook input — failing closed for safety."
fi

_env_loader="${WALTER_OS_HOME:-$REPO_ROOT}/scripts/walter/lib/env-loader.sh"
if [[ -f "$_env_loader" ]]; then
  # shellcheck source=/dev/null
  source "$_env_loader"
  walter_env_load_allowlist "${WALTER_CONFIG}/env"
fi
unset _env_loader

WALTER_OS_HOME="${WALTER_OS_HOME:-$REPO_ROOT}"
_session_lib="${WALTER_OS_HOME}/scripts/walter/lib/session-state.sh"
if [[ ! -f "$_session_lib" ]]; then
  _block "Walter-OS session timeout: session-state library missing — failing closed for safety."
fi
# shellcheck source=/dev/null
source "$_session_lib"

_repo_path="$(printf '%s' "$INPUT" | jq -r '.cwd // .workspace.current_dir // empty')"
if [[ -z "$_repo_path" ]]; then
  _repo_path="$PWD"
fi

_result="$(walter_session_touch "$_repo_path" 2>/dev/null)"
_status=$?

if [[ "$_status" -eq 0 ]]; then
  _allow
fi

_trigger="$(printf '%s' "$_result" | jq -r '.trigger // "unknown"' 2>/dev/null || printf 'unknown')"
case "$_trigger" in
  max-hours)
    _limit="$(_walter_session_effective_max_hours)h"
    _block "Walter-OS session expired at $(date -u +%H:%M) (max-hours=${_limit}). Type /session restart to begin a new session."
    ;;
  max-idle)
    _limit="$(_walter_session_effective_idle_min)m"
    _block "Walter-OS session expired at $(date -u +%H:%M) (max-idle=${_limit}). Type /session restart to begin a new session."
    ;;
  malformed-state|clock-rewind)
    _block "Walter-OS session invalid (${_trigger}). Type /session restart to begin a new session."
    ;;
  state-write|state-delete)
    _block "Walter-OS session state error (${_trigger}). Fix state permissions or run /session restart."
    ;;
  *)
    _block "Walter-OS session timeout failed closed (${_trigger}). Type /session restart to begin a new session."
    ;;
esac
