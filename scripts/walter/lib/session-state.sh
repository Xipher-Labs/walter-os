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

_walter_session_openssl_supports_ed25519() {
  local openssl_bin="$1"
  "$openssl_bin" genpkey -algorithm ED25519 >/dev/null 2>&1
}

_walter_session_openssl() {
  local candidate resolved
  for candidate in \
    "${WALTER_OPENSSL_BIN:-}" \
    openssl \
    /opt/homebrew/opt/openssl@3/bin/openssl \
    /opt/homebrew/bin/openssl \
    /usr/local/opt/openssl@3/bin/openssl \
    /usr/local/bin/openssl \
    /usr/bin/openssl; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */* ]]; then
      [[ -x "$candidate" ]] || continue
      resolved="$candidate"
    else
      resolved="$(command -v "$candidate" 2>/dev/null || true)"
      [[ -n "$resolved" ]] || continue
    fi
    if _walter_session_openssl_supports_ed25519 "$resolved"; then
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

_walter_session_state_dir() {
  printf '%s/state' "${WALTER_CONFIG:-$HOME/.config/walter-os}"
}

_walter_session_private_key_file() {
  local session_id="$1"
  printf '%s/session-%s.key' "$(_walter_session_state_dir)" "$session_id"
}

_walter_session_public_key_file() {
  local session_id="$1"
  printf '%s/session-%s.pub' "$(_walter_session_state_dir)" "$session_id"
}

_walter_session_caps_dir() {
  local session_id="$1"
  printf '%s/caps-%s' "$(_walter_session_state_dir)" "$session_id"
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

_walter_session_revoke_capability_material() {
  local file="$1" session_id private_key caps_dir
  [[ -f "$file" ]] || return 0
  session_id="$(jq -r '.session_id // empty' "$file" 2>/dev/null || true)"
  [[ -n "$session_id" ]] || return 0
  [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  private_key="$(_walter_session_private_key_file "$session_id")"
  caps_dir="$(_walter_session_caps_dir "$session_id")"

  if [[ -e "$private_key" ]] && ! rm -f "$private_key"; then
    return 1
  fi

  if [[ -d "$caps_dir" ]] && ! rm -r "$caps_dir"; then
    return 1
  fi
}

_walter_session_release_lock() {
  local lock_dir="$1"
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rm -f "$lock_dir/created_epoch" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

_walter_session_reclaim_stale_lock() {
  local lock_dir="$1" pid created_epoch now_epoch stale_after
  [[ -d "$lock_dir" ]] || return 0
  stale_after="$(_walter_session_positive_int_or_default "${WALTER_SESSION_LOCK_STALE_SEC:-30}" 30)"
  now_epoch="$(_walter_session_now_epoch)"
  created_epoch="$(cat "$lock_dir/created_epoch" 2>/dev/null || true)"
  if [[ "$created_epoch" =~ ^[0-9]+$ ]] && (( now_epoch - created_epoch > stale_after )); then
    _walter_session_release_lock "$lock_dir"
    [[ ! -d "$lock_dir" ]]
    return
  fi

  if [[ ! -f "$lock_dir/pid" ]]; then
    return 1
  fi
  pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  if kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  _walter_session_release_lock "$lock_dir"
  [[ ! -d "$lock_dir" ]]
}

_walter_session_write_lock_owner() {
  local lock_dir="$1"
  printf '%s\n' "$(_walter_session_now_epoch)" > "$lock_dir/created_epoch" \
    && printf '%s\n' "$$" > "$lock_dir/pid"
}

_walter_session_mark_lock_or_fail() {
  local lock_dir="$1" file="$2"
  if ! _walter_session_write_lock_owner "$lock_dir"; then
    _walter_session_release_lock "$lock_dir"
    _walter_session_result "error" "state-write" "$file"
    return 12
  fi
}

_walter_session_has_capability_material() {
  local file="$1" session_id private_key public_key caps_dir stored_private stored_public stored_caps
  [[ -f "$file" ]] || return 1
  session_id="$(jq -r '.session_id // empty' "$file" 2>/dev/null || true)"
  [[ -n "$session_id" ]] || return 1
  [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  private_key="$(_walter_session_private_key_file "$session_id")"
  public_key="$(_walter_session_public_key_file "$session_id")"
  caps_dir="$(_walter_session_caps_dir "$session_id")"
  stored_private="$(jq -r '.capability_private_key_path // empty' "$file" 2>/dev/null || true)"
  stored_public="$(jq -r '.capability_public_key_path // empty' "$file" 2>/dev/null || true)"
  stored_caps="$(jq -r '.capability_tokens_dir // empty' "$file" 2>/dev/null || true)"

  [[ "$stored_private" == "$private_key" ]] || return 1
  [[ "$stored_public" == "$public_key" ]] || return 1
  [[ "$stored_caps" == "$caps_dir" ]] || return 1
  [[ -f "$private_key" && -f "$public_key" && -d "$caps_dir" ]]
}

_walter_session_write_new() {
  local repo="$1" file="$2" now_epoch="$3"
  local state_dir now_iso max_hours max_idle tmp_file session_id private_key public_key caps_dir tmp_key tmp_pub openssl_bin
  state_dir="$(dirname "$file")"
  now_iso="$(_walter_session_iso "$now_epoch")"
  max_hours="$(_walter_session_effective_max_hours)"
  max_idle="$(_walter_session_effective_idle_min)"
  session_id="$(_walter_session_uuid)"
  private_key="$(_walter_session_private_key_file "$session_id")"
  public_key="$(_walter_session_public_key_file "$session_id")"
  caps_dir="$(_walter_session_caps_dir "$session_id")"

  mkdir -p "$state_dir" || return 1
  chmod 700 "$state_dir" 2>/dev/null || true
  mkdir -p "$caps_dir" || return 1
  chmod 700 "$caps_dir" 2>/dev/null || true

  if ! openssl_bin="$(_walter_session_openssl)"; then
    rm -r "$caps_dir"
    return 1
  fi
  tmp_key="$(mktemp "${state_dir}/session-key.XXXXXX")" || {
    rm -r "$caps_dir"
    return 1
  }
  tmp_pub="$(mktemp "${state_dir}/session-pub.XXXXXX")" || {
    rm -f "$tmp_key"
    rm -r "$caps_dir"
    return 1
  }
  if ! "$openssl_bin" genpkey -algorithm ED25519 -out "$tmp_key" >/dev/null 2>&1; then
    rm -f "$tmp_key" "$tmp_pub"
    rm -r "$caps_dir"
    return 1
  fi
  chmod 600 "$tmp_key" 2>/dev/null || true
  if ! "$openssl_bin" pkey -in "$tmp_key" -pubout -out "$tmp_pub" >/dev/null 2>&1; then
    rm -f "$tmp_key" "$tmp_pub"
    rm -r "$caps_dir"
    return 1
  fi
  chmod 644 "$tmp_pub" 2>/dev/null || true
  if ! mv "$tmp_key" "$private_key" || ! mv "$tmp_pub" "$public_key"; then
    rm -f "$tmp_key" "$tmp_pub" "$private_key" "$public_key"
    rm -r "$caps_dir"
    return 1
  fi

  tmp_file="$(mktemp "${state_dir}/session.XXXXXX")" || {
    rm -f "$private_key" "$public_key"
    rm -r "$caps_dir"
    return 1
  }

  if ! jq -n \
    --arg session_id "$session_id" \
    --arg started_at "$now_iso" \
    --arg last_activity_at "$now_iso" \
    --arg repo_path "$repo" \
    --arg private_key "$private_key" \
    --arg public_key "$public_key" \
    --arg caps_dir "$caps_dir" \
    --argjson max_hours "$max_hours" \
    --argjson max_idle "$max_idle" \
    '{
      session_id: $session_id,
      started_at: $started_at,
      last_activity_at: $last_activity_at,
      repo_path: $repo_path,
      capability_private_key_path: $private_key,
      capability_public_key_path: $public_key,
      capability_tokens_dir: $caps_dir,
      max_hours_at_start: $max_hours,
      max_idle_min_at_start: $max_idle,
      extensions: []
    }' > "$tmp_file"; then
    rm -f "$tmp_file"
    rm -f "$private_key" "$public_key"
    rm -r "$caps_dir"
    return 1
  fi
  chmod 600 "$tmp_file" 2>/dev/null || true
  if ! mv "$tmp_file" "$file"; then
    rm -f "$tmp_file"
    rm -f "$private_key" "$public_key"
    rm -r "$caps_dir"
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
    local lock_dir lock_attempts=0
    lock_dir="${file}.lock"
    mkdir -p "$(dirname "$file")" || {
      _walter_session_result "error" "state-write" "$file"
      return 12
    }
    if mkdir "$lock_dir" 2>/dev/null; then
      _walter_session_mark_lock_or_fail "$lock_dir" "$file" || return 12
      if [[ ! -f "$file" ]]; then
        if ! _walter_session_write_new "$repo" "$file" "$now_epoch"; then
          _walter_session_release_lock "$lock_dir"
          _walter_session_result "error" "state-write" "$file"
          return 12
        fi
        _walter_session_release_lock "$lock_dir"
        _walter_session_result "started" "" "$file"
        return 0
      fi
      _walter_session_release_lock "$lock_dir"
    else
      while [[ ! -f "$file" && "$lock_attempts" -lt 50 ]]; do
        sleep 0.1
        lock_attempts=$((lock_attempts + 1))
      done
      if [[ ! -f "$file" ]] && _walter_session_reclaim_stale_lock "$lock_dir"; then
        if mkdir "$lock_dir" 2>/dev/null; then
          _walter_session_mark_lock_or_fail "$lock_dir" "$file" || return 12
          if ! _walter_session_write_new "$repo" "$file" "$now_epoch"; then
            _walter_session_release_lock "$lock_dir"
            _walter_session_result "error" "state-write" "$file"
            return 12
          fi
          _walter_session_release_lock "$lock_dir"
          _walter_session_result "started" "" "$file"
          return 0
        fi
      fi
      if [[ ! -f "$file" ]]; then
        _walter_session_result "error" "state-write" "$file"
        return 12
      fi
    fi
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

  local expiry_trigger=""
  if awk -v now="$now_epoch" -v last="$last_epoch" -v idle="$max_idle" 'BEGIN { exit !((now - last) > (idle * 60)) }'; then
    expiry_trigger="max-idle"
  elif awk -v now="$now_epoch" -v started="$started_epoch" -v hours="$max_hours" 'BEGIN { exit !((now - started) > (hours * 3600)) }'; then
    expiry_trigger="max-hours"
  fi

  if [[ -n "$expiry_trigger" ]]; then
    if ! _walter_session_revoke_capability_material "$file"; then
      _walter_session_result "error" "state-delete" "$file"
      return 12
    fi
    _walter_session_result "expired" "$expiry_trigger" "$file"
    return 10
  fi

  if ! _walter_session_has_capability_material "$file"; then
    _walter_session_result "invalid" "legacy-session" "$file"
    return 11
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
  if ! _walter_session_revoke_capability_material "$file"; then
    _walter_session_result "error" "state-delete" "$file"
    return 12
  fi
  if ! rm -f "$file"; then
    _walter_session_result "error" "state-delete" "$file"
    return 12
  fi
  _walter_session_result "ended" "" "$file"
}
