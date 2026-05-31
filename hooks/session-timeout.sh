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

_escape_glob_pattern() {
  local pattern="$1"
  pattern="${pattern//\\/\\\\}"
  pattern="${pattern//\*/\\*}"
  pattern="${pattern//\?/\\?}"
  pattern="${pattern//\[/\\[}"
  pattern="${pattern//\]/\\]}"
  printf '%s' "$pattern"
}

_replace_literal() {
  local detail="$1" needle="$2" replacement="$3" pattern
  [[ -n "$needle" ]] || {
    printf '%s' "$detail"
    return 0
  }
  pattern="$(_escape_glob_pattern "$needle")"
  printf '%s' "${detail//$pattern/$replacement}"
}

_sanitize_hook_detail() {
  local detail="$1" config_label
  config_label="~"
  config_label+="/.config/walter-os"
  detail="${detail//$'\r'/ }"
  detail="${detail//$'\n'/; }"
  if [[ -n "${HOME:-}" ]]; then
    detail="$(_replace_literal "$detail" "$HOME" "~")"
  fi
  if [[ -n "${WALTER_CONFIG:-}" ]]; then
    detail="$(_replace_literal "$detail" "$WALTER_CONFIG" "$config_label")"
  fi
  detail="$(_replace_literal "$detail" "${WALTER_OS_HOME:-$REPO_ROOT}" "<walter-os>")"
  printf '%.300s' "$detail"
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
if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  _block "Walter-OS session timeout: non-object hook input — failing closed for safety."
fi

_env_loader="${WALTER_OS_HOME:-$REPO_ROOT}/scripts/walter/lib/env-loader.sh"
if [[ -f "$_env_loader" ]]; then
  # shellcheck source=/dev/null
  source "$_env_loader"
  walter_env_load_allowlist "${HOME}/.config/walter-os/overlay/personal.env"
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
_prompt_text="$(printf '%s' "$INPUT" | jq -r '.prompt // .message // empty')"

_result="$(walter_session_touch "$_repo_path" 2>/dev/null)"
_status=$?

if [[ "$_status" -eq 0 ]]; then
  _session_status="$(printf '%s' "$_result" | jq -r '.status // empty' 2>/dev/null || true)"
  if [[ "$_session_status" == "started" ]]; then
    _skill_cap_loader="${WALTER_OS_HOME}/scripts/walter/lib/skill-cap-loader.sh"
    if [[ ! -f "$_skill_cap_loader" ]]; then
      _block "Walter-OS session timeout: skill-cap-loader library missing - failing closed for safety."
    fi
    # shellcheck source=/dev/null
    source "$_skill_cap_loader"
    _mint_error=""
    if ! _mint_error="$(walter_skill_caps_mint_defaults "$_repo_path" 2>&1 >/dev/null)"; then
      walter_session_end "$_repo_path" >/dev/null 2>&1 || true
      _mint_error="$(_sanitize_hook_detail "$_mint_error")"
      _mint_reason="Walter-OS session timeout: default skill capability minting failed - failing closed for safety."
      if [[ -n "$_mint_error" ]]; then
        _mint_reason="${_mint_reason} Detail: ${_mint_error}"
      fi
      _block "$_mint_reason"
    fi
  fi
  _allow
fi

_trigger="$(printf '%s' "$_result" | jq -r '.trigger // "unknown"' 2>/dev/null || printf 'unknown')"
_trigger="${_trigger:-unknown}"
if [[ "$_status" -eq 12 && "$_trigger" == "unknown" ]]; then
  _trigger="state-write"
fi
if [[ "$_prompt_text" =~ ^[[:space:]]*/session[[:space:]]+restart([[:space:]]|$) ]]; then
  if walter_session_end "$_repo_path" >/dev/null 2>&1; then
    _allow
  fi
  _trigger="state-delete"
fi
case "$_trigger" in
  max-hours)
    _limit="$(_walter_session_effective_max_hours)h"
    _block "Walter-OS session expired at $(date -u +%H:%M) (max-hours=${_limit}). Type /session restart to begin a new session, or close this terminal."
    ;;
  max-idle)
    _limit="$(_walter_session_effective_idle_min)m"
    _block "Walter-OS session expired at $(date -u +%H:%M) (max-idle=${_limit}). Type /session restart to begin a new session, or close this terminal."
    ;;
  malformed-state|clock-rewind|legacy-session)
    _block "Walter-OS session invalid (${_trigger}). Type /session restart to begin a new session."
    ;;
  state-write|state-delete)
    _block "Walter-OS session state error (${_trigger}). Fix state permissions or run /session restart."
    ;;
  *)
    _block "Walter-OS session timeout failed closed (${_trigger}). Type /session restart to begin a new session."
    ;;
esac
