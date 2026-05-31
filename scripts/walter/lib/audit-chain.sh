#!/usr/bin/env bash
# scripts/walter/lib/audit-chain.sh
#
# Tamper-evident audit-chain writer for Walter-OS.
# Refs: docs/specs/audit-chain-merkle-and-receipts.md

walter_audit_config_dir() {
  printf '%s\n' "${WALTER_CONFIG:-${HOME}/.config/walter-os}"
}

walter_audit_dir() {
  printf '%s\n' "${WALTER_AUDIT_DIR:-$(walter_audit_config_dir)/audit}"
}

walter_audit_date() {
  printf '%s\n' "${WALTER_AUDIT_DATE:-$(date -u +%Y-%m-%d)}"
}

walter_audit_chain_path() {
  local date_value="${1:-$(walter_audit_date)}"
  printf '%s/chain-%s.jsonl\n' "$(walter_audit_dir)" "$date_value"
}

walter_audit_lock_path() {
  printf '%s/.chain.lock\n' "$(walter_audit_dir)"
}

walter_audit_timestamp() {
  printf '%s\n' "${WALTER_AUDIT_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
}

walter_audit_date_from_timestamp() {
  local timestamp="$1"
  case "$timestamp" in
    ????-??-??T*) printf '%s\n' "${timestamp%%T*}" ;;
    *) walter_audit_date ;;
  esac
}

walter_audit_hash_bytes() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

walter_audit_hash_string() {
  printf '%s' "$1" | walter_audit_hash_bytes
}

walter_audit_normalize_row() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi
  jq -cS .
}

walter_audit_input_summary() {
  local input="$1" redactor=""
  if [[ -n "${WALTER_OS_HOME:-}" && -x "${WALTER_OS_HOME}/scripts/agent-secret-redactor.sh" ]]; then
    redactor="${WALTER_OS_HOME}/scripts/agent-secret-redactor.sh"
  else
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${lib_dir}/../../agent-secret-redactor.sh" ]]; then
      redactor="${lib_dir}/../../agent-secret-redactor.sh"
    fi
  fi
  if [[ -n "$redactor" ]]; then
    input="$(printf '%s' "$input" | "$redactor" 2>/dev/null)" || input="<REDACTED:redactor-error>"
  fi
  printf '%s' "$input" | tr '\n\r\t' '   ' | cut -c 1-200
}

_walter_audit_reclaim_lock() {
  local lock_path="$1" expected_pid="${2:-}" expected_identity="${3:-}" reaper_path stale_path current_pid current_identity reclaimed=1
  reaper_path="${lock_path}.reaper"
  mkdir "$reaper_path" 2>/dev/null || return 1
  current_pid=""
  current_identity=""
  if [[ -f "${lock_path}/pid" ]]; then
    current_pid="$(sed -n '1p' "${lock_path}/pid" 2>/dev/null || true)"
    current_identity="$(sed -n '2p' "${lock_path}/pid" 2>/dev/null || true)"
  fi
  if [[ "$current_pid" != "$expected_pid" || "$current_identity" != "$expected_identity" ]]; then
    rmdir "$reaper_path" 2>/dev/null || true
    return 1
  fi
  stale_path="${lock_path}.stale.${BASHPID:-$$}.${RANDOM:-0}"
  if mv "$lock_path" "$stale_path" 2>/dev/null; then
    rm -rf -- "$stale_path"
    reclaimed=0
  fi
  rmdir "$reaper_path" 2>/dev/null || true
  return "$reclaimed"
}

_walter_audit_process_identity() {
  local pid="$1"
  ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

_walter_audit_mtime_epoch() {
  local path="$1" fallback="$2" mtime=""
  mtime="$(stat -c %Y "$path" 2>/dev/null || true)"
  if [[ "$mtime" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$mtime"
    return 0
  fi

  mtime="$(stat -f %m "$path" 2>/dev/null || true)"
  if [[ "$mtime" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$mtime"
    return 0
  fi

  printf '%s\n' "$fallback"
}

_walter_audit_acquire_lock() {
  local lock_path="$1" wait_seconds="${WALTER_AUDIT_LOCK_WAIT_SECONDS:-10}" start pid_file owner_pid owner_identity current_identity now lock_mtime stale_after
  start="$(date +%s)"
  while ! mkdir "$lock_path" 2>/dev/null; do
    now="$(date +%s)"
    pid_file="${lock_path}/pid"
    owner_pid=""
    owner_identity=""
    if [[ -f "$pid_file" ]]; then
      owner_pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
      owner_identity="$(sed -n '2p' "$pid_file" 2>/dev/null || true)"
    fi
    lock_mtime="$(_walter_audit_mtime_epoch "$lock_path" "$now")"
    stale_after="${WALTER_AUDIT_STALE_LOCK_SECONDS:-300}"
    if [[ "$owner_pid" =~ ^[0-9]+$ ]]; then
      if ! kill -0 "$owner_pid" 2>/dev/null; then
        _walter_audit_reclaim_lock "$lock_path" "$owner_pid" "$owner_identity" || true
        continue
      fi
      if [[ -n "$owner_identity" ]]; then
        current_identity="$(_walter_audit_process_identity "$owner_pid")"
        if [[ -n "$current_identity" && "$current_identity" != "$owner_identity" && $((now - lock_mtime)) -ge "$stale_after" ]]; then
          _walter_audit_reclaim_lock "$lock_path" "$owner_pid" "$owner_identity" || true
          continue
        fi
      elif [[ $((now - lock_mtime)) -ge "$stale_after" ]]; then
        _walter_audit_reclaim_lock "$lock_path" "$owner_pid" "$owner_identity" || true
        continue
      fi
    else
      if [[ $((now - lock_mtime)) -ge "$stale_after" ]]; then
        _walter_audit_reclaim_lock "$lock_path" "$owner_pid" "$owner_identity" || true
        continue
      fi
    fi
    if [[ $(( $(date +%s) - start )) -ge "$wait_seconds" ]]; then
      echo "walter-audit-chain: timed out acquiring lock: $lock_path" >&2
      return 1
    fi
    sleep 0.05
  done
  printf '%s\n%s\n' "${BASHPID:-$$}" "$(_walter_audit_process_identity "${BASHPID:-$$}")" > "${lock_path}/pid" || {
    rmdir "$lock_path" 2>/dev/null || true
    return 1
  }
}

_walter_audit_release_lock() {
  local lock_path="$1"
  rm -f -- "${lock_path}/pid" 2>/dev/null || true
  rmdir "$lock_path" 2>/dev/null || true
}

walter_audit_append() {
  [[ "$#" -eq 5 ]] || {
    echo "walter-audit-chain: usage: walter_audit_append <tool> <input> <decision> <source> <reason>" >&2
    return 2
  }
  if ! command -v jq >/dev/null 2>&1; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local tool="$1" input="$2" decision="$3" source="$4" reason="$5"
  local audit_dir chain_path lock_path previous_line previous_hash row summary timestamp row_date chain_fd
  audit_dir="$(walter_audit_dir)"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1

  _walter_audit_acquire_lock "$lock_path" || return 1
  timestamp="$(walter_audit_timestamp)"
  row_date="$(walter_audit_date_from_timestamp "$timestamp")"
  chain_path="$(walter_audit_chain_path "$row_date")"

  exec {chain_fd}<>"$chain_path" || {
    _walter_audit_release_lock "$lock_path"
    return 1
  }

  previous_hash="null"
  previous_line="$(tail -n 1 <&"$chain_fd")"
  if [[ -n "$previous_line" ]]; then
    previous_hash="$(walter_audit_hash_string "$previous_line")"
  fi

  summary="$(walter_audit_input_summary "$input")"
  row="$(jq -ncS \
    --arg ts "$timestamp" \
    --arg session_id "${WALTER_SESSION_ID:-unknown}" \
    --arg operator "${USER:-unknown}" \
    --arg event "tool_invocation" \
    --arg tool "$tool" \
    --arg input_summary "$summary" \
    --arg decision "$decision" \
    --arg decision_source "$source" \
    --arg decision_reason "$reason" \
    --arg prev_hash "$previous_hash" \
    '{ts:$ts,session_id:$session_id,operator:$operator,event:$event,tool:$tool,input_summary:$input_summary,decision:$decision,decision_source:$decision_source,decision_reason:$decision_reason,prev_hash:$prev_hash}')" || {
      exec {chain_fd}>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    }

  printf '%s\n' "$row" >&"$chain_fd" || {
    exec {chain_fd}>&-
    _walter_audit_release_lock "$lock_path"
    return 1
  }
  exec {chain_fd}>&-
  _walter_audit_release_lock "$lock_path"
  printf '%s\n' "$chain_path"
}

walter_audit_verify_chain() {
  [[ "$#" -le 1 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain [date]" >&2
    return 2
  }
  if ! command -v jq >/dev/null 2>&1; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="${1:-$(walter_audit_date)}" chain_path line row_number prev_hash actual_hash expected_hash row_count
  chain_path="$(walter_audit_chain_path "$date_value")"
  if [[ ! -f "$chain_path" ]]; then
    echo "walter-audit-chain: chain not found: $chain_path" >&2
    return 1
  fi

  row_number=0
  row_count=0
  expected_hash="null"
  while IFS= read -r line || [[ -n "$line" ]]; do
    row_number=$((row_number + 1))
    if ! printf '%s\n' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
      echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
      return 1
    fi
    prev_hash="$(printf '%s\n' "$line" | jq -r '.prev_hash // empty')"
    if [[ -z "$prev_hash" ]]; then
      echo "walter-audit-chain: row ${row_number}: missing prev_hash" >&2
      return 1
    fi
    if [[ "$prev_hash" != "$expected_hash" ]]; then
      echo "walter-audit-chain: row ${row_number}: prev_hash mismatch" >&2
      echo "  expected: $expected_hash" >&2
      echo "  actual:   $prev_hash" >&2
      return 1
    fi
    actual_hash="$(walter_audit_hash_string "$line")"
    expected_hash="$actual_hash"
    row_count="$row_number"
  done < "$chain_path"

  if [[ "$row_count" -eq 0 ]]; then
    echo "walter-audit-chain: empty chain: $chain_path" >&2
    return 1
  fi

  printf 'ok: verified %s row(s): %s\n' "$row_count" "$chain_path"
}
