#!/usr/bin/env bash
# scripts/walter/lib/session-state.sh
#
# Foundation library for time-bounded Walter-OS sessions. This file only owns
# state tracking; hooks and CLI commands consume it in follow-up PRs.

# shellcheck disable=SC2034 # used by sourced callers
WALTER_SESSION_STATE_LIB_VERSION=1

_walter_session_now_epoch() {
  if [[ "${WALTER_SESSION_TEST_CLOCK:-0}" == "1" && -n "${WALTER_SESSION_NOW_EPOCH:-}" ]]; then
    printf '%s' "$WALTER_SESSION_NOW_EPOCH"
  else
    date -u +%s
  fi
}

_walter_session_iso() {
  local epoch="$1"
  date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
}

_walter_session_epoch() {
  local iso="$1"
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || date -u -d "$iso" +%s 2>/dev/null
}

_walter_session_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf 'session-%s-%s' "$(_walter_session_now_epoch)" "$$"
  fi
}

_walter_session_hash() {
  local value="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$value" | shasum -a 256 | awk '{print substr($1,1,16)}'
  else
    printf '%s' "$value" | sha256sum | awk '{print substr($1,1,16)}'
  fi
}

_walter_session_state_dir() {
  printf '%s/state' "${WALTER_CONFIG:-$HOME/.config/walter-os}"
}

_walter_session_positive_int_or_default() {
  local value="$1" default="$2"
  if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default"
  fi
}

_walter_session_effective_max_hours() {
  local configured
  configured="$(_walter_session_positive_int_or_default "${WALTER_SESSION_MAX_HOURS:-8}" 8)"
  if [[ "${WALTER_PHI_MODE:-0}" == "1" ]]; then
    if awk -v v="$configured" 'BEGIN { exit !(v > 4) }'; then
      echo 4
      return 0
    fi
  fi
  echo "$configured"
}

_walter_session_effective_idle_min() {
  local configured
  configured="$(_walter_session_positive_int_or_default "${WALTER_SESSION_MAX_IDLE_MIN:-60}" 60)"
  if [[ "${WALTER_PHI_MODE:-0}" == "1" ]]; then
    if awk -v v="$configured" 'BEGIN { exit !(v > 30) }'; then
      echo 30
      return 0
    fi
  fi
  echo "$configured"
}

walter_session_state_file() {
  local repo="${1:-${PWD}}"
  local resolved
  resolved="$(cd "$repo" 2>/dev/null && pwd -P || printf '%s' "$repo")"
  printf '%s/session-%s.json' "$(_walter_session_state_dir)" "$(_walter_session_hash "$resolved")"
}

walter_session_get() {
  local repo="${1:-${PWD}}"
  local file
  file="$(walter_session_state_file "$repo")"
  [[ -f "$file" ]] || return 1
  cat "$file"
}

_walter_session_write_new() {
  local repo="$1" file="$2" now_epoch="$3"
  local state_dir now_iso max_hours max_idle tmp_file
  state_dir="$(dirname "$file")"
  now_iso="$(_walter_session_iso "$now_epoch")"
  max_hours="$(_walter_session_effective_max_hours)"
  max_idle="$(_walter_session_effective_idle_min)"

  mkdir -p "$state_dir" || return 1
  chmod 700 "$state_dir" 2>/dev/null || true
  tmp_file="$(mktemp "${state_dir}/session.XXXXXX")" || return 1

  if ! jq -n \
    --arg session_id "$(_walter_session_uuid)" \
    --arg started_at "$now_iso" \
    --arg last_activity_at "$now_iso" \
    --arg repo_path "$repo" \
    --argjson max_hours "$max_hours" \
    --argjson max_idle "$max_idle" \
    '{
      session_id: $session_id,
      started_at: $started_at,
      last_activity_at: $last_activity_at,
      repo_path: $repo_path,
      max_hours_at_start: $max_hours,
      max_idle_min_at_start: $max_idle,
      extensions: []
    }' > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  chmod 600 "$tmp_file" 2>/dev/null || true
  if ! mv "$tmp_file" "$file"; then
    rm -f "$tmp_file"
    return 1
  fi
}

_walter_session_result() {
  local status="$1" trigger="${2:-}" file="${3:-}"
  jq -nc \
    --arg status "$status" \
    --arg trigger "$trigger" \
    --arg state_file "$file" \
    '{status:$status} + (if $trigger != "" then {trigger:$trigger} else {} end) + (if $state_file != "" then {state_file:$state_file} else {} end)'
}

walter_session_touch() {
  local repo="${1:-${PWD}}"
  local file now_epoch now_iso max_hours max_idle
  file="$(walter_session_state_file "$repo")"
  now_epoch="$(_walter_session_now_epoch)"
  now_iso="$(_walter_session_iso "$now_epoch")"
  max_hours="$(_walter_session_effective_max_hours)"
  max_idle="$(_walter_session_effective_idle_min)"

  if [[ ! -f "$file" ]]; then
    if ! _walter_session_write_new "$repo" "$file" "$now_epoch"; then
      _walter_session_result "error" "state-write" "$file"
      return 12
    fi
    _walter_session_result "started" "" "$file"
    return 0
  fi

  local started_at last_activity_at started_epoch last_epoch
  started_at="$(jq -r '.started_at // empty' "$file")"
  last_activity_at="$(jq -r '.last_activity_at // empty' "$file")"
  if [[ -z "$started_at" || -z "$last_activity_at" ]]; then
    _walter_session_result "invalid" "malformed-state" "$file"
    return 11
  fi

  if ! started_epoch="$(_walter_session_epoch "$started_at")" || [[ ! "$started_epoch" =~ ^[0-9]+$ ]]; then
    _walter_session_result "invalid" "malformed-state" "$file"
    return 11
  fi
  if ! last_epoch="$(_walter_session_epoch "$last_activity_at")" || [[ ! "$last_epoch" =~ ^[0-9]+$ ]]; then
    _walter_session_result "invalid" "malformed-state" "$file"
    return 11
  fi

  if (( now_epoch < started_epoch || now_epoch < last_epoch )); then
    _walter_session_result "invalid" "clock-rewind" "$file"
    return 11
  fi

  if awk -v now="$now_epoch" -v last="$last_epoch" -v idle="$max_idle" 'BEGIN { exit !((now - last) > (idle * 60)) }'; then
    _walter_session_result "expired" "max-idle" "$file"
    return 10
  fi

  if awk -v now="$now_epoch" -v started="$started_epoch" -v hours="$max_hours" 'BEGIN { exit !((now - started) > (hours * 3600)) }'; then
    _walter_session_result "expired" "max-hours" "$file"
    return 10
  fi

  local tmp_file
  tmp_file="$(mktemp "${file}.XXXXXX")"
  if ! jq --arg now "$now_iso" '.last_activity_at = $now' "$file" > "$tmp_file"; then
    rm -f "$tmp_file"
    return 12
  fi
  chmod 600 "$tmp_file" 2>/dev/null || true
  if ! mv "$tmp_file" "$file"; then
    rm -f "$tmp_file"
    return 12
  fi
  _walter_session_result "active" "" "$file"
}

walter_session_end() {
  local repo="${1:-${PWD}}"
  local file
  file="$(walter_session_state_file "$repo")"
  if ! rm -f "$file"; then
    _walter_session_result "error" "state-delete" "$file"
    return 12
  fi
  _walter_session_result "ended" "" "$file"
}
