#!/usr/bin/env bash
# scripts/walter/lib/audit-chain.sh
#
# Tamper-evident audit-chain writer for Walter-OS.
# Refs: docs/specs/audit-chain-merkle-and-receipts.md

_walter_audit_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_walter_audit_lib_dir}/session-state.sh" ]]; then
  # shellcheck source=/dev/null
  source "${_walter_audit_lib_dir}/session-state.sh"
fi
unset _walter_audit_lib_dir

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

walter_audit_root_path() {
  local date_value="${1:-$(walter_audit_date)}"
  printf '%s/root-%s.txt\n' "$(walter_audit_dir)" "$date_value"
}

walter_audit_rekor_receipt_path() {
  local date_value="${1:-$(walter_audit_date)}"
  printf '%s/root-%s.rekor.json\n' "$(walter_audit_dir)" "$date_value"
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

_walter_audit_valid_date() {
  local date_value="$1"
  [[ "$date_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  _walter_audit_require_python3 || return 3
  python3 - "$date_value" <<'PY' >/dev/null 2>&1
from datetime import datetime
import sys

datetime.strptime(sys.argv[1], "%Y-%m-%d")
PY
}

_walter_audit_date_add_days() {
  local date_value="$1" day_delta="$2"
  _walter_audit_require_python3 || return 3
  python3 - "$date_value" "$day_delta" <<'PY'
from datetime import datetime, timedelta
import sys

try:
    date_value = datetime.strptime(sys.argv[1], "%Y-%m-%d")
    day_delta = int(sys.argv[2])
except (ValueError, IndexError):
    sys.exit(2)
print((date_value + timedelta(days=day_delta)).strftime("%Y-%m-%d"))
PY
}

_walter_audit_previous_date() {
  _walter_audit_date_add_days "$1" -1
}

_walter_audit_read_root_file() {
  local root_path="$1" root_hash
  [[ -f "$root_path" ]] || return 1
  root_hash="$(cat "$root_path")" || return 1
  if [[ ! "$root_hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "walter-audit-chain: invalid root hash: $root_path" >&2
    return 2
  fi
  printf '%s' "$root_hash"
}

_walter_audit_previous_chain_root() {
  local date_value="$1" previous_date previous_status previous_root_path previous_root
  previous_date="$(_walter_audit_previous_date "$date_value")"
  previous_status="$?"
  [[ "$previous_status" -eq 0 ]] || return "$previous_status"
  previous_root_path="$(walter_audit_root_path "$previous_date")"
  [[ -f "$previous_root_path" ]] || return 0
  previous_root="$(_walter_audit_read_root_file "$previous_root_path")" || return $?
  printf '%s' "$previous_root"
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

_walter_audit_require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "walter-audit-chain: required tool missing: $tool" >&2
    return 1
  fi
}

_walter_audit_require_python3() {
  _walter_audit_require_tool python3 || return 1
  if ! python3 - <<'PY' >/dev/null 2>&1
import json  # noqa: F401
PY
  then
    echo "walter-audit-chain: required tool missing: python3" >&2
    return 1
  fi
}

_walter_audit_resolve_openssl() {
  local openssl_bin=""
  if [[ "${_WALTER_AUDIT_OPENSSL_STATUS:-}" == "ok" ]]; then
    return 0
  fi
  if [[ "${_WALTER_AUDIT_OPENSSL_STATUS:-}" == "missing" ]]; then
    return 1
  fi
  if declare -F _walter_session_openssl >/dev/null 2>&1; then
    if openssl_bin="$(_walter_session_openssl)"; then
      _WALTER_AUDIT_OPENSSL_BIN="$openssl_bin"
      _WALTER_AUDIT_OPENSSL_STATUS="ok"
      return 0
    fi
    _WALTER_AUDIT_OPENSSL_STATUS="missing"
    return 1
  fi
  openssl_bin="$(command -v openssl 2>/dev/null || true)"
  if [[ -n "$openssl_bin" ]] && "$openssl_bin" genpkey -algorithm ED25519 >/dev/null 2>&1; then
    _WALTER_AUDIT_OPENSSL_BIN="$openssl_bin"
    _WALTER_AUDIT_OPENSSL_STATUS="ok"
    return 0
  fi
  _WALTER_AUDIT_OPENSSL_STATUS="missing"
  return 1
}

_walter_audit_openssl() {
  _walter_audit_resolve_openssl || return $?
  printf '%s' "$_WALTER_AUDIT_OPENSSL_BIN"
}

_walter_audit_mktemp_dir() {
  local label="${1:-audit-chain}"
  mktemp -d "${TMPDIR:-/tmp}/walter-${label}.XXXXXX" 2>/dev/null \
    || mktemp -d -t "walter-${label}.XXXXXX" 2>/dev/null
}

_walter_audit_state_dir() {
  if declare -F _walter_session_state_dir >/dev/null 2>&1; then
    _walter_session_state_dir
  else
    printf '%s/state' "$(walter_audit_config_dir)"
  fi
}

_walter_audit_private_key_file() {
  local session_id="$1"
  if declare -F _walter_session_private_key_file >/dev/null 2>&1; then
    _walter_session_private_key_file "$session_id"
  else
    printf '%s/session-%s.key' "$(_walter_audit_state_dir)" "$session_id"
  fi
}

_walter_audit_public_key_file() {
  local session_id="$1" public_key archive_key
  if declare -F _walter_session_public_key_file >/dev/null 2>&1; then
    public_key="$(_walter_session_public_key_file "$session_id")"
  else
    public_key="$(_walter_audit_state_dir)/session-${session_id}.pub"
  fi
  if [[ -f "$public_key" ]]; then
    printf '%s' "$public_key"
    return 0
  fi
  archive_key="$(_walter_audit_state_dir)/keys-archive/session-${session_id}.pub"
  if [[ -f "$archive_key" ]]; then
    printf '%s' "$archive_key"
    return 0
  fi
  return 1
}

_walter_audit_session_state_file() {
  local repo="${WALTER_AUDIT_REPO:-${PWD}}"
  if [[ -n "${WALTER_AUDIT_SESSION_STATE:-}" && -f "${WALTER_AUDIT_SESSION_STATE}" ]]; then
    printf '%s' "$WALTER_AUDIT_SESSION_STATE"
    return 0
  fi
  if declare -F walter_session_state_file >/dev/null 2>&1; then
    walter_session_state_file "$repo"
    return 0
  fi
  return 1
}

_walter_audit_current_session_id() {
  local state_file session_id from_state=0
  if [[ -n "${WALTER_SESSION_ID:-}" ]]; then
    session_id="$WALTER_SESSION_ID"
  else
    from_state=1
    state_file="$(_walter_audit_session_state_file)" || return 1
    [[ -f "$state_file" ]] || return 1
    if _walter_audit_jq_available; then
      session_id="$(jq -er 'if (.session_id | type) == "string" then .session_id else empty end' "$state_file" 2>/dev/null)" || {
        echo "walter-audit-chain: invalid session state: $state_file" >&2
        return 4
      }
    else
      _walter_audit_require_python3 || return 3
      session_id="$(python3 - "$state_file" 2>/dev/null <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        state = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

session_id = state.get("session_id", "")
if not isinstance(session_id, str) or not session_id:
    raise SystemExit(1)
print(session_id, end="")
PY
)" || {
        echo "walter-audit-chain: invalid session state: $state_file" >&2
        return 4
      }
    fi
  fi
  if [[ ! "$session_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    if [[ "$from_state" -eq 1 ]]; then
      echo "walter-audit-chain: invalid session state: $state_file" >&2
      return 4
    fi
    echo "walter-audit-chain: invalid session id for signed audit row" >&2
    return 2
  fi
  printf '%s' "$session_id"
}

walter_audit_set_repo_from_hook_input() {
  local hook_input="$1" repo_path
  if ! _walter_audit_jq_available; then
    return 0
  fi
  repo_path="$(printf '%s' "$hook_input" | jq -er '
    if (.cwd | type) == "string" and (.cwd | length) > 0 then
      .cwd
    elif (.workspace.current_dir | type) == "string" and (.workspace.current_dir | length) > 0 then
      .workspace.current_dir
    else
      empty
    end
  ' 2>/dev/null || true)"
  if [[ -n "$repo_path" && -d "$repo_path" ]]; then
    repo_path="$(cd "$repo_path" && pwd -P)" || return 0
    export WALTER_AUDIT_REPO="$repo_path"
  fi
}

_walter_audit_b64_encode_file() {
  local file="$1"
  _walter_audit_require_python3 || return 1
  python3 - "$file" <<'PY'
import base64
import pathlib
import sys

print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"), end="")
PY
}

_walter_audit_b64_any_decode_to_file() {
  local value="$1" out="$2"
  _walter_audit_require_python3 || return 1
  python3 - "$value" "$out" <<'PY'
import base64
import binascii
import pathlib
import sys

try:
    data = base64.b64decode(sys.argv[1].encode("ascii"), validate=True)
except (binascii.Error, UnicodeEncodeError, ValueError):
    raise SystemExit(1)
pathlib.Path(sys.argv[2]).write_bytes(data)
PY
}

_walter_audit_b64_decode_to_file() {
  local value="$1" out="$2"
  _walter_audit_require_python3 || return 1
  python3 - "$value" "$out" <<'PY'
import base64
import binascii
import pathlib
import re
import sys

value = sys.argv[1]
if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", value):
    raise SystemExit(1)
try:
    data = base64.b64decode(value.encode("ascii"), validate=True)
except (binascii.Error, ValueError):
    raise SystemExit(1)
if len(data) != 64:
    raise SystemExit(1)
if base64.b64encode(data).decode("ascii") != value:
    raise SystemExit(1)
pathlib.Path(sys.argv[2]).write_bytes(data)
PY
}

_walter_audit_hex_to_file() {
  local value="$1" out="$2"
  if [[ ! "$value" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "walter-audit-chain: invalid sha256 hex" >&2
    return 1
  fi
  _walter_audit_require_python3 || return 1
  python3 - "$value" "$out" <<'PY'
import pathlib
import sys

pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(sys.argv[1]))
PY
}

_walter_audit_sign_file() {
  local payload_file="$1" session_id="${2:-}" purpose="${3:-audit payload}"
  local session_status private_key openssl_bin tmp_dir sig_file sig
  _walter_audit_require_python3 || return 3
  if [[ -z "$session_id" ]]; then
    session_id="$(_walter_audit_current_session_id)"
    session_status="$?"
    if [[ "$session_status" -ne 0 ]]; then
      [[ "$session_status" -eq 3 ]] && return 3
      [[ "$session_status" -eq 2 ]] && return 2
      [[ "$session_status" -eq 4 ]] && return 1
      echo "walter-audit-chain: active session id required for ${purpose}" >&2
      return 2
    fi
  fi
  [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "walter-audit-chain: invalid session id for ${purpose}" >&2
    return 2
  }
  private_key="$(_walter_audit_private_key_file "$session_id")"
  [[ -f "$private_key" ]] || {
    echo "walter-audit-chain: session private key missing for ${purpose}: $session_id" >&2
    return 2
  }
  if ! _walter_audit_resolve_openssl; then
    echo "walter-audit-chain: ED25519-capable openssl missing" >&2
    return 3
  fi
  openssl_bin="$_WALTER_AUDIT_OPENSSL_BIN"

  tmp_dir="$(_walter_audit_mktemp_dir audit-sign)" || {
    echo "walter-audit-chain: temporary directory unavailable for signing" >&2
    return 1
  }
  sig_file="$tmp_dir/sig.bin"
  if ! "$openssl_bin" pkeyutl -sign -inkey "$private_key" -rawin -in "$payload_file" -out "$sig_file" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: failed to sign ${purpose}" >&2
    return 1
  fi
  sig="$(_walter_audit_b64_encode_file "$sig_file")" || {
    rm -rf "$tmp_dir"
    return 1
  }
  rm -rf "$tmp_dir"
  printf '%s' "$sig"
}

_walter_audit_sign_row() {
  local row_json="$1" session_id="${2:-}" tmp_dir payload_file sig sign_status
  _walter_audit_require_python3 || return 3
  tmp_dir="$(_walter_audit_mktemp_dir audit-sign-row)" || {
    echo "walter-audit-chain: temporary directory unavailable for signing" >&2
    return 1
  }
  payload_file="$tmp_dir/payload.json"
  printf '%s' "$row_json" > "$payload_file" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: unable to write signing payload" >&2
    return 1
  }
  if sig="$(_walter_audit_sign_file "$payload_file" "$session_id" "signed audit row")"; then
    :
  else
    sign_status="$?"
    rm -rf "$tmp_dir"
    return "$sign_status"
  fi
  rm -rf "$tmp_dir"
  printf '%s' "$sig"
}

_walter_audit_jq_available() {
  command -v jq >/dev/null 2>&1 && jq -n true >/dev/null 2>&1
}

walter_audit_normalize_row() {
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi
  jq -cS .
}

walter_audit_json_string() {
  local value="$1" output="" char="" escaped="" ordinal i
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      \\) output="${output}\\\\" ;;
      '"') output="${output}\\\"" ;;
      $'\b') output="${output}\\b" ;;
      $'\f') output="${output}\\f" ;;
      $'\n') output="${output}\\n" ;;
      $'\r') output="${output}\\r" ;;
      $'\t') output="${output}\\t" ;;
      *)
        LC_CTYPE=C printf -v ordinal '%d' "'$char"
        if [[ "$ordinal" -lt 32 ]]; then
          printf -v escaped '\\u%04x' "$ordinal"
          output="${output}${escaped}"
        else
          output="${output}${char}"
        fi
        ;;
    esac
  done
  printf '"%s"' "$output"
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
  else
    input="<REDACTED:redactor-unavailable>"
  fi
  printf '%s' "$input" | tr '\n\r\t' '   ' | cut -c 1-200
}

_walter_audit_acquire_lock() {
  local lock_path="$1" wait_seconds="${WALTER_AUDIT_LOCK_WAIT_SECONDS:-10}"
  WALTER_AUDIT_LOCK_KIND=""
  if command -v flock >/dev/null 2>&1; then
    exec 8>"$lock_path" || return 1
    chmod 600 "$lock_path" || {
      exec 8>&-
      return 1
    }
    flock -x -w "$wait_seconds" 8 || {
      exec 8>&-
      echo "walter-audit-chain: timed out acquiring lock: $lock_path" >&2
      return 1
    }
    WALTER_AUDIT_LOCK_KIND="flock"
    return 0
  fi

  _walter_audit_acquire_lock_dir "$lock_path" "$wait_seconds" || return 1
  WALTER_AUDIT_LOCK_KIND="dir"
}

_walter_audit_remove_lock_dir() {
  local lock_path="$1"
  rm -f -- "${lock_path}/pid" 2>/dev/null || return 1
  rmdir "$lock_path" 2>/dev/null || return 1
}

_walter_audit_reclaim_lock() {
  local lock_path="$1" expected_pid="${2:-}" expected_identity="${3:-}" reaper_path stale_path current_pid current_identity reclaimed=1
  reaper_path="${lock_path}.reaper"
  mkdir "$reaper_path" 2>/dev/null || return 1
  chmod 700 "$reaper_path" 2>/dev/null || {
    rmdir "$reaper_path" 2>/dev/null || true
    return 1
  }
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
    _walter_audit_remove_lock_dir "$stale_path" || true
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

_walter_audit_acquire_lock_dir() {
  local lock_path="$1" wait_seconds="$2" start pid_file owner_pid owner_identity current_identity now lock_mtime stale_after
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
  chmod 700 "$lock_path" || {
    rmdir "$lock_path" 2>/dev/null || true
    return 1
  }
  printf '%s\n%s\n' "${BASHPID:-$$}" "$(_walter_audit_process_identity "${BASHPID:-$$}")" > "${lock_path}/pid" || {
    rmdir "$lock_path" 2>/dev/null || true
    return 1
  }
  chmod 600 "${lock_path}/pid" || {
    rm -f -- "${lock_path}/pid" 2>/dev/null || true
    rmdir "$lock_path" 2>/dev/null || true
    return 1
  }
}

_walter_audit_release_lock() {
  local lock_path="${1:-}"
  if [[ "${WALTER_AUDIT_LOCK_KIND:-}" == "flock" ]]; then
    flock -u 8 2>/dev/null || true
    exec 8>&- 2>/dev/null || true
  elif [[ -n "$lock_path" ]]; then
    _walter_audit_remove_lock_dir "$lock_path" 2>/dev/null || true
  fi
  WALTER_AUDIT_LOCK_KIND=""
}

_walter_audit_path_identity() {
  local path="$1" identity=""
  identity="$(stat -Lc '%d:%i' "$path" 2>/dev/null || true)"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return 0
  fi

  identity="$(stat -c '%d:%i' "$path" 2>/dev/null || true)"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return 0
  fi

  identity="$(stat -f '%d:%i' "$path" 2>/dev/null || true)"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return 0
  fi

  return 1
}

_walter_audit_fd_matches_path() {
  local fd="$1" path="$2" fd_identity path_identity
  fd_identity="$(_walter_audit_fd_identity "$fd")" || return 1
  path_identity="$(_walter_audit_path_identity "$path")" || return 1
  [[ "$fd_identity" == "$path_identity" ]]
}

_walter_audit_fd_identity() {
  local fd="$1" identity=""
  if command -v perl >/dev/null 2>&1; then
    identity="$(perl -e '
      my $fd = shift;
      open my $fh, "+<&=", $fd or exit 1;
      my @stat = stat($fh);
      @stat or exit 1;
      print "$stat[0]:$stat[1]\n";
    ' "$fd" 2>/dev/null || true)"
    if [[ -n "$identity" ]]; then
      printf '%s\n' "$identity"
      return 0
    fi
  fi

  _walter_audit_path_identity "/dev/fd/${fd}"
}

_walter_audit_fd_size() {
  local fd="$1" size=""
  size="$(stat -Lc '%s' "/dev/fd/${fd}" 2>/dev/null || true)"
  if [[ -n "$size" ]]; then
    printf '%s\n' "$size"
    return 0
  fi

  size="$(stat -f '%z' "/dev/fd/${fd}" 2>/dev/null || true)"
  if [[ -n "$size" ]]; then
    printf '%s\n' "$size"
    return 0
  fi

  return 1
}

_walter_audit_truncate_fd() {
  local fd="$1" size="$2"
  command -v perl >/dev/null 2>&1 || return 1
  perl -e '
    my ($fd, $size) = @ARGV;
    open my $fh, "+<&=", $fd or exit 1;
    truncate($fh, $size) or exit 1;
  ' "$fd" "$size"
}

_walter_audit_verify_row_hash() {
  local line="$1" row_number="$2" stored_row_hash row_without_hash computed_row_hash
  stored_row_hash="$(printf '%s\n' "$line" | jq -r '.row_hash // empty' 2>/dev/null)" || {
    echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
    return 1
  }
  if [[ ! "$stored_row_hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "walter-audit-chain: row ${row_number}: missing row_hash" >&2
    return 1
  fi
  row_without_hash="$(printf '%s\n' "$line" | jq -cS 'del(.row_hash, .sig)' 2>/dev/null)" || {
    echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
    return 1
  }
  computed_row_hash="$(walter_audit_hash_string "$row_without_hash")"
  if [[ "$stored_row_hash" != "$computed_row_hash" ]]; then
    echo "walter-audit-chain: row ${row_number}: row_hash mismatch" >&2
    echo "  expected: $computed_row_hash" >&2
    echo "  actual:   $stored_row_hash" >&2
    return 1
  fi
}

_walter_audit_verify_row_signature() {
  local line="$1" row_number="$2" tmp_dir="${3:-}" cleanup_tmp=0
  local session_id sig public_key openssl_bin payload payload_file sig_file
  sig="$(printf '%s\n' "$line" | jq -r '.sig // empty' 2>/dev/null)" || {
    echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
    return 1
  }
  if [[ -z "$sig" ]]; then
    echo "walter-audit-chain: row ${row_number}: missing sig (legacy unsigned audit chain; rotate or start a fresh chain for this date before enforcing signed verification)" >&2
    return 1
  fi
  if [[ ! "$sig" =~ ^[A-Za-z0-9+/]{86}==$ ]]; then
    echo "walter-audit-chain: row ${row_number}: invalid sig format" >&2
    return 1
  fi
  session_id="$(printf '%s\n' "$line" | jq -r '.session_id // empty' 2>/dev/null)" || {
    echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
    return 1
  }
  if [[ ! "$session_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "walter-audit-chain: row ${row_number}: invalid session_id" >&2
    return 1
  fi
  public_key="$(_walter_audit_public_key_file "$session_id")" || {
    echo "walter-audit-chain: row ${row_number}: cannot verify session ${session_id}: public key missing" >&2
    return 2
  }
  if ! _walter_audit_resolve_openssl; then
    echo "walter-audit-chain: ED25519-capable openssl missing" >&2
    return 3
  fi
  openssl_bin="$_WALTER_AUDIT_OPENSSL_BIN"
  _walter_audit_require_python3 || return 3

  if [[ -z "$tmp_dir" ]]; then
    tmp_dir="$(_walter_audit_mktemp_dir audit-verify-row)" || {
      echo "walter-audit-chain: temporary directory unavailable for signature verification" >&2
      return 1
    }
    cleanup_tmp=1
  fi
  payload_file="$tmp_dir/payload.json"
  sig_file="$tmp_dir/sig.bin"
  payload="$(printf '%s\n' "$line" | jq -cS 'del(.sig)' 2>/dev/null)" || {
    [[ "$cleanup_tmp" -eq 1 ]] && rm -rf "$tmp_dir"
    echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
    return 1
  }
  printf '%s' "$payload" > "$payload_file" || {
    [[ "$cleanup_tmp" -eq 1 ]] && rm -rf "$tmp_dir"
    return 1
  }
  if ! _walter_audit_b64_decode_to_file "$sig" "$sig_file" >/dev/null 2>&1; then
    [[ "$cleanup_tmp" -eq 1 ]] && rm -rf "$tmp_dir"
    echo "walter-audit-chain: row ${row_number}: invalid sig encoding" >&2
    return 1
  fi
  if ! "$openssl_bin" pkeyutl -verify -pubin -inkey "$public_key" -rawin -in "$payload_file" -sigfile "$sig_file" >/dev/null 2>&1; then
    [[ "$cleanup_tmp" -eq 1 ]] && rm -rf "$tmp_dir"
    echo "walter-audit-chain: row ${row_number}: signature verification failed" >&2
    return 1
  fi
  [[ "$cleanup_tmp" -eq 1 ]] && rm -rf "$tmp_dir"
  return 0
}

_walter_audit_verify_chain_file_unlocked() {
  local chain_path="$1" line row_number prev_hash actual_hash expected_hash canonical last_hex sig_tmp_dir verify_status
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi
  if [[ -s "$chain_path" ]]; then
    last_hex="$(tail -c 1 "$chain_path" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    if [[ "$last_hex" != "0a" ]]; then
      echo "walter-audit-chain: unterminated final row: $chain_path" >&2
      return 1
    fi
  fi
  sig_tmp_dir="$(_walter_audit_mktemp_dir audit-verify-chain)" || {
    echo "walter-audit-chain: temporary directory unavailable for signature verification" >&2
    return 1
  }
  row_number=0
  expected_hash="null"
  while IFS= read -r line || [[ -n "$line" ]]; do
    row_number=$((row_number + 1))
    canonical="$(printf '%s\n' "$line" | jq -cS . 2>/dev/null)" || {
      rm -rf "$sig_tmp_dir"
      echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
      return 1
    }
    if [[ "$canonical" != "$line" ]]; then
      rm -rf "$sig_tmp_dir"
      echo "walter-audit-chain: row ${row_number}: non-canonical JSON" >&2
      return 1
    fi
    if ! printf '%s\n' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
      rm -rf "$sig_tmp_dir"
      echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
      return 1
    fi
    _walter_audit_verify_row_hash "$line" "$row_number" || {
      rm -rf "$sig_tmp_dir"
      return 1
    }
    prev_hash="$(printf '%s\n' "$line" | jq -r '.prev_hash // empty')"
    if [[ -z "$prev_hash" ]]; then
      rm -rf "$sig_tmp_dir"
      echo "walter-audit-chain: row ${row_number}: missing prev_hash" >&2
      return 1
    fi
    if [[ "$prev_hash" != "$expected_hash" ]]; then
      rm -rf "$sig_tmp_dir"
      echo "walter-audit-chain: row ${row_number}: prev_hash mismatch" >&2
      echo "  expected: $expected_hash" >&2
      echo "  actual:   $prev_hash" >&2
      return 1
    fi
    _walter_audit_verify_row_signature "$line" "$row_number" "$sig_tmp_dir"
    verify_status="$?"
    if [[ "$verify_status" -ne 0 ]]; then
      rm -rf "$sig_tmp_dir"
      return "$verify_status"
    fi
    actual_hash="$(walter_audit_hash_string "$line")"
    expected_hash="$actual_hash"
  done < "$chain_path"

  if [[ "$row_number" -eq 0 ]]; then
    rm -rf "$sig_tmp_dir"
    echo "walter-audit-chain: empty chain: $chain_path" >&2
    return 1
  fi

  rm -rf "$sig_tmp_dir"
  printf '%s\n' "$row_number"
}

_walter_audit_write_root_unlocked() {
  local root_path="$1" root_hash="$2" tmp_path
  [[ "$root_hash" =~ ^[0-9a-f]{64}$ ]] || {
    echo "walter-audit-chain: invalid root hash: $root_hash" >&2
    return 1
  }
  tmp_path="$(mktemp "${root_path}.XXXXXX")" || return 1
  printf '%s' "$root_hash" > "$tmp_path" || {
    rm -f "$tmp_path"
    return 1
  }
  chmod 600 "$tmp_path" || {
    rm -f "$tmp_path"
    return 1
  }
  mv "$tmp_path" "$root_path" || {
    rm -f "$tmp_path"
    return 1
  }
}

_walter_audit_verify_root_unlocked() {
  local root_path="$1" expected_hash="$2" root_hash
  if [[ ! -f "$root_path" ]]; then
    echo "walter-audit-chain: root hash not found: $root_path" >&2
    return 1
  fi
  root_hash="$(cat "$root_path")" || return 1
  if [[ "$root_hash" != "$expected_hash" ]]; then
    echo "walter-audit-chain: root hash mismatch: $root_path" >&2
    echo "  expected: $expected_hash" >&2
    echo "  actual:   $root_hash" >&2
    return 1
  fi
}

_walter_audit_root_matches_rotated_chain() {
  local chain_path="$1" root_path="$2" root_hash rotated previous_line last_hex
  [[ -f "$root_path" ]] || return 1
  root_hash="$(cat "$root_path")" || return 1
  [[ "$root_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  for rotated in "$chain_path".*; do
    [[ -f "$rotated" && -s "$rotated" ]] || continue
    last_hex="$(tail -c 1 "$rotated" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    [[ "$last_hex" == "0a" ]] || continue
    previous_line="$(tail -n 1 "$rotated")" || continue
    [[ -n "$previous_line" ]] || continue
    [[ "$(walter_audit_hash_string "$previous_line")" == "$root_hash" ]] && return 0
  done
  return 1
}

walter_audit_append() {
  [[ "$#" -eq 5 ]] || {
    echo "walter-audit-chain: usage: walter_audit_append <tool> <input> <decision> <source> <reason>" >&2
    return 2
  }
  local tool="$1" input="$2" decision="$3" source="$4" reason="$5"
  local audit_dir chain_path root_path last_hex lock_path previous_line previous_hash pre_write_size retry_count row row_hash row_without_hash summary timestamp row_date root_hash session_id session_status sig sign_status chain_created prev_chain_root prev_chain_root_status prev_chain_root_field row_date_status
  audit_dir="$(walter_audit_dir)"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1

  _walter_audit_acquire_lock "$lock_path" || return 1
  timestamp="$(walter_audit_timestamp)"
  row_date="$(walter_audit_date_from_timestamp "$timestamp")"
  _walter_audit_check_date_arg "$row_date" "audit row date"
  row_date_status="$?"
  if [[ "$row_date_status" -ne 0 ]]; then
    _walter_audit_release_lock "$lock_path"
    return "$row_date_status"
  fi
  chain_path="$(walter_audit_chain_path "$row_date")"
  root_path="$(walter_audit_root_path "$row_date")"

  chain_created=0
  if [[ ! -e "$chain_path" ]]; then
    if [[ -e "$root_path" ]] && ! _walter_audit_root_matches_rotated_chain "$chain_path" "$root_path"; then
      echo "walter-audit-chain: chain missing with existing root: $chain_path" >&2
      _walter_audit_release_lock "$lock_path"
      return 1
    fi
    : > "$chain_path" || {
      _walter_audit_release_lock "$lock_path"
      return 1
    }
    chain_created=1
  elif [[ ! -f "$chain_path" ]]; then
    echo "walter-audit-chain: chain path is not a file: $chain_path" >&2
    _walter_audit_release_lock "$lock_path"
    return 1
  fi
  chmod 600 "$chain_path" || {
    _walter_audit_release_lock "$lock_path"
    return 1
  }
  exec 9<>"$chain_path" || {
    _walter_audit_release_lock "$lock_path"
    return 1
  }

  previous_hash="null"
  previous_line="$(tail -n 1 <&9)"
  if [[ "$chain_created" -eq 0 && ! -s "$chain_path" && -f "$root_path" ]]; then
    echo "walter-audit-chain: empty chain with existing root: $chain_path" >&2
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    return 1
  fi
  if [[ -s "$chain_path" ]]; then
    last_hex="$(tail -c 1 "$chain_path" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    if [[ "$last_hex" != "0a" ]]; then
      echo "walter-audit-chain: unterminated final row: $chain_path" >&2
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    fi
    if [[ -z "$previous_line" ]]; then
      echo "walter-audit-chain: blank final row: $chain_path" >&2
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    fi
    if ! _walter_audit_jq_available; then
      echo "walter-audit-chain: jq required to append to existing chain: $chain_path" >&2
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    fi
    _walter_audit_verify_chain_file_unlocked "$chain_path" >/dev/null || {
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    }
    previous_hash="$(walter_audit_hash_string "$previous_line")"
    _walter_audit_verify_root_unlocked "$root_path" "$previous_hash" || {
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    }
  fi

  prev_chain_root=""
  if [[ "$previous_hash" == "null" ]]; then
    prev_chain_root="$(_walter_audit_previous_chain_root "$row_date")"
    prev_chain_root_status="$?"
    if [[ "$prev_chain_root_status" -ne 0 ]]; then
      exec 9>&-
      if [[ "$chain_created" -eq 1 ]]; then
        rm -f -- "$chain_path" || true
      fi
      _walter_audit_release_lock "$lock_path"
      return "$prev_chain_root_status"
    fi
  fi

  summary="$(walter_audit_input_summary "$input")"
  session_id="$(_walter_audit_current_session_id)"
  session_status="$?"
  if [[ "$session_status" -ne 0 ]]; then
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    [[ "$session_status" -eq 3 ]] && return 3
    [[ "$session_status" -eq 2 ]] && return 2
    [[ "$session_status" -eq 4 ]] && return 1
    echo "walter-audit-chain: active session id required for signed audit row" >&2
    return 2
  fi
  if _walter_audit_jq_available; then
    row_without_hash="$(jq -ncS \
      --arg ts "$timestamp" \
      --arg session_id "$session_id" \
      --arg operator "${USER:-unknown}" \
      --arg event "tool_invocation" \
      --arg tool "$tool" \
      --arg input_summary "$summary" \
      --arg decision "$decision" \
      --arg decision_source "$source" \
      --arg decision_reason "$reason" \
      --arg prev_hash "$previous_hash" \
      --arg prev_chain_root "$prev_chain_root" \
      '{ts:$ts,session_id:$session_id,operator:$operator,event:$event,tool:$tool,input_summary:$input_summary,decision:$decision,decision_source:$decision_source,decision_reason:$decision_reason,prev_hash:$prev_hash}
       | if $prev_chain_root == "" then . else . + {prev_chain_root:$prev_chain_root} end')" || {
        exec 9>&-
        _walter_audit_release_lock "$lock_path"
        return 1
      }
    row_hash="$(walter_audit_hash_string "$row_without_hash")"
    row="$(printf '%s\n' "$row_without_hash" | jq -cS --arg row_hash "$row_hash" '. + {row_hash:$row_hash}')" || {
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    }
    if sig="$(_walter_audit_sign_row "$row" "$session_id")"; then
      :
    else
      sign_status="$?"
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return "$sign_status"
    fi
    row="$(printf '%s\n' "$row" | jq -cS --arg sig "$sig" '. + {sig:$sig}')" || {
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return 1
    }
  else
    prev_chain_root_field=""
    if [[ -n "$prev_chain_root" ]]; then
      prev_chain_root_field=",\"prev_chain_root\":$(walter_audit_json_string "$prev_chain_root")"
    fi
    row_without_hash="{\"decision\":$(walter_audit_json_string "$decision"),\"decision_reason\":$(walter_audit_json_string "$reason"),\"decision_source\":$(walter_audit_json_string "$source"),\"event\":\"tool_invocation\",\"input_summary\":$(walter_audit_json_string "$summary"),\"operator\":$(walter_audit_json_string "${USER:-unknown}"),\"prev_hash\":$(walter_audit_json_string "$previous_hash")${prev_chain_root_field},\"session_id\":$(walter_audit_json_string "$session_id"),\"tool\":$(walter_audit_json_string "$tool"),\"ts\":$(walter_audit_json_string "$timestamp")}"
    row_hash="$(walter_audit_hash_string "$row_without_hash")"
    row="{\"decision\":$(walter_audit_json_string "$decision"),\"decision_reason\":$(walter_audit_json_string "$reason"),\"decision_source\":$(walter_audit_json_string "$source"),\"event\":\"tool_invocation\",\"input_summary\":$(walter_audit_json_string "$summary"),\"operator\":$(walter_audit_json_string "${USER:-unknown}"),\"prev_hash\":$(walter_audit_json_string "$previous_hash")${prev_chain_root_field},\"row_hash\":$(walter_audit_json_string "$row_hash"),\"session_id\":$(walter_audit_json_string "$session_id"),\"tool\":$(walter_audit_json_string "$tool"),\"ts\":$(walter_audit_json_string "$timestamp")}"
    if sig="$(_walter_audit_sign_row "$row" "$session_id")"; then
      :
    else
      sign_status="$?"
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return "$sign_status"
    fi
    row="{\"decision\":$(walter_audit_json_string "$decision"),\"decision_reason\":$(walter_audit_json_string "$reason"),\"decision_source\":$(walter_audit_json_string "$source"),\"event\":\"tool_invocation\",\"input_summary\":$(walter_audit_json_string "$summary"),\"operator\":$(walter_audit_json_string "${USER:-unknown}"),\"prev_hash\":$(walter_audit_json_string "$previous_hash")${prev_chain_root_field},\"row_hash\":$(walter_audit_json_string "$row_hash"),\"session_id\":$(walter_audit_json_string "$session_id"),\"sig\":$(walter_audit_json_string "$sig"),\"tool\":$(walter_audit_json_string "$tool"),\"ts\":$(walter_audit_json_string "$timestamp")}"
  fi

  if ! _walter_audit_fd_matches_path 9 "$chain_path"; then
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    retry_count="${WALTER_AUDIT_APPEND_RETRY:-0}"
    if [[ "$retry_count" -ge 3 ]]; then
      echo "walter-audit-chain: chain path changed during append: $chain_path" >&2
      return 1
    fi
    WALTER_AUDIT_APPEND_RETRY=$((retry_count + 1)) walter_audit_append "$tool" "$input" "$decision" "$source" "$reason"
    return "$?"
  fi

  pre_write_size="$(_walter_audit_fd_size 9)" || {
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    return 1
  }
  printf '%s\n' "$row" >&9 || {
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    return 1
  }
  if ! _walter_audit_fd_matches_path 9 "$chain_path"; then
    _walter_audit_truncate_fd 9 "$pre_write_size" || {
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      echo "walter-audit-chain: chain path changed after append: $chain_path" >&2
      return 1
    }
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    retry_count="${WALTER_AUDIT_APPEND_RETRY:-0}"
    if [[ "$retry_count" -ge 3 ]]; then
      echo "walter-audit-chain: chain path changed after append: $chain_path" >&2
      return 1
    fi
    WALTER_AUDIT_APPEND_RETRY=$((retry_count + 1)) walter_audit_append "$tool" "$input" "$decision" "$source" "$reason"
    return "$?"
  fi
  root_hash="$(walter_audit_hash_string "$row")"
  _walter_audit_write_root_unlocked "$root_path" "$root_hash" || {
    _walter_audit_truncate_fd 9 "$pre_write_size" || true
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    return 1
  }
  exec 9>&-
  _walter_audit_release_lock "$lock_path"
  printf '%s\n' "$chain_path"
}

_walter_audit_check_date_arg() {
  local date_value="$1" label="$2" valid_status
  _walter_audit_valid_date "$date_value"
  valid_status="$?"
  if [[ "$valid_status" -eq 0 ]]; then
    return 0
  fi
  if [[ "$valid_status" -eq 3 ]]; then
    return 3
  fi
  echo "walter-audit-chain: invalid ${label}: $date_value" >&2
  return 2
}

_walter_audit_check_sha256_arg() {
  local value="$1" label="$2"
  if [[ "$value" =~ ^[0-9a-f]{64}$ ]]; then
    return 0
  fi
  echo "walter-audit-chain: invalid ${label}: $value" >&2
  return 2
}

_walter_audit_verify_chain_day_unlocked() {
  local date_value="$1" chain_path root_path row_count root_hash previous_line
  chain_path="$(walter_audit_chain_path "$date_value")"
  root_path="$(walter_audit_root_path "$date_value")"
  if [[ ! -f "$chain_path" ]]; then
    echo "walter-audit-chain: chain not found: $chain_path" >&2
    return 1
  fi

  row_count="$(_walter_audit_verify_chain_file_unlocked "$chain_path")" || return $?
  previous_line="$(tail -n 1 "$chain_path")" || return 1
  root_hash="$(walter_audit_hash_string "$previous_line")"
  _walter_audit_verify_root_unlocked "$root_path" "$root_hash" || return $?
  printf '%s %s\n' "$row_count" "$root_hash"
}

walter_audit_verify_chain() {
  [[ "$#" -le 1 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain [date]" >&2
    return 2
  }
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="${1:-$(walter_audit_date)}" audit_dir chain_path lock_path row_count verify_result verify_status
  _walter_audit_check_date_arg "$date_value" "date" || return $?

  audit_dir="$(walter_audit_dir)"
  chain_path="$(walter_audit_chain_path "$date_value")"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1
  _walter_audit_acquire_lock "$lock_path" || return 1
  if verify_result="$(_walter_audit_verify_chain_day_unlocked "$date_value")"; then
    verify_status=0
    read -r row_count _ <<< "$verify_result"
  else
    verify_status="$?"
  fi
  _walter_audit_release_lock "$lock_path"
  [[ "$verify_status" -eq 0 ]] || return "$verify_status"

  printf 'ok: verified %s row(s): %s\n' "$row_count" "$chain_path"
}

_walter_audit_rekor_url() {
  local configured="${1:-${WALTER_AUDIT_REKOR_URL:-https://rekor.sigstore.dev}}" rekor_url
  rekor_url="$(_walter_audit_trim "$configured")"
  if [[ -z "$rekor_url" ]]; then
    echo "walter-audit-chain: Rekor URL required" >&2
    return 2
  fi
  case "$rekor_url" in
    http://*|https://*) ;;
    *)
      echo "walter-audit-chain: Rekor URL must start with http:// or https://" >&2
      return 2
      ;;
  esac
  printf '%s' "${rekor_url%/}"
}

_walter_audit_rekor_timeout() {
  local timeout="${WALTER_AUDIT_REKOR_TIMEOUT_SECONDS:-10}"
  if [[ ! "$timeout" =~ ^[1-9][0-9]*$ ]]; then
    echo "walter-audit-chain: WALTER_AUDIT_REKOR_TIMEOUT_SECONDS must be a positive integer" >&2
    return 2
  fi
  if [[ "$timeout" -gt 300 ]]; then
    echo "walter-audit-chain: WALTER_AUDIT_REKOR_TIMEOUT_SECONDS must be <= 300" >&2
    return 2
  fi
  printf '%s' "$timeout"
}

_walter_audit_operator_hash() {
  local operator="${WALTER_AUDIT_OPERATOR_ID:-${USER:-unknown}}"
  walter_audit_hash_string "walter-os-audit-operator:${operator}"
}

_walter_audit_version() {
  local version_file="" version=""
  if [[ -n "${WALTER_OS_HOME:-}" ]]; then
    version_file="${WALTER_OS_HOME}/VERSION"
  fi
  if [[ -n "$version_file" && -f "$version_file" ]]; then
    version="$(sed -n '1p' "$version_file" 2>/dev/null || true)"
    version="$(_walter_audit_trim "$version")"
  fi
  printf '%s' "${version:-unknown}"
}

_walter_audit_last_session_id_for_day() {
  local chain_path="$1" session_id
  session_id="$(tail -n 1 "$chain_path" | jq -er '
    if (.session_id | type) == "string" and (.session_id | test("^[A-Za-z0-9._-]+$")) then
      .session_id
    else
      empty
    end
  ' 2>/dev/null)" || {
    echo "walter-audit-chain: unable to read final audit session id: $chain_path" >&2
    return 1
  }
  printf '%s' "$session_id"
}

_walter_audit_chain_root_for_path() {
  local chain_path="$1" previous_line root_hash
  _walter_audit_verify_chain_file_unlocked "$chain_path" >/dev/null || return $?
  if ! previous_line="$(tail -n 1 "$chain_path")" || [[ -z "$previous_line" ]]; then
    echo "walter-audit-chain: unable to read final row: $chain_path" >&2
    return 1
  fi
  root_hash="$(walter_audit_hash_string "$previous_line")"
  printf '%s' "$root_hash"
}

_walter_audit_rekor_payload() {
  local date_value="$1" root_hash="$2" operator_hash version
  operator_hash="$(_walter_audit_operator_hash)"
  version="$(_walter_audit_version)"
  jq -cS -n \
    --arg date "$date_value" \
    --arg operator "$operator_hash" \
    --arg root "$root_hash" \
    --arg version "$version" \
    '{date:$date, operator:$operator, root:$root, walter_os_version:$version}'
}

_walter_audit_rekor_request_body() {
  local payload="$1" sig="$2" public_key="$3" payload_hash="${4:-}"
  if [[ -z "$payload_hash" ]]; then
    payload_hash="$(walter_audit_hash_string "$payload")"
  fi
  jq -cS -n \
    --arg hash "$payload_hash" \
    --arg public_key "$public_key" \
    --arg sig "$sig" \
    '{
      apiVersion: "0.0.1",
      kind: "hashedrekord",
      spec: {
        data: {hash: {algorithm: "sha256", value: $hash}},
        signature: {content: $sig, publicKey: {content: $public_key}}
      }
    }'
}

_walter_audit_rekor_entry_id() {
  local response_file="$1" entry_id
  entry_id="$(jq -er 'if type == "object" then keys_unsorted[0] else empty end' "$response_file" 2>/dev/null)" || {
    echo "walter-audit-chain: Rekor response missing entry id" >&2
    return 1
  }
  [[ -n "$entry_id" && "$entry_id" != "null" ]] || {
    echo "walter-audit-chain: Rekor response missing entry id" >&2
    return 1
  }
  printf '%s' "$entry_id"
}

_walter_audit_rekor_conflict_entry_id() {
  local headers_file="$1" response_file="$2" entry_id location message_entry_id
  entry_id="$(jq -er '
    if type == "object" then
      .uuid // .entryUUID // .entry_uuid // .entryID // .entry_id // .id // empty
    else
      empty
    end
  ' "$response_file" 2>/dev/null || true)"
  if [[ -z "$entry_id" && -s "$headers_file" ]]; then
    location="$(python3 - "$headers_file" <<'PY'
import pathlib
import sys

for raw_line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines():
    if raw_line.lower().startswith("location:"):
        print(raw_line.split(":", 1)[1].strip(), end="")
        break
PY
)" || location=""
    case "$location" in
      */api/v1/log/entries/*)
        entry_id="${location##*/}"
        entry_id="${entry_id%%\?*}"
        ;;
      *)
        entry_id="$location"
        ;;
    esac
  fi
  if [[ -z "$entry_id" ]]; then
    message_entry_id="$(jq -er '
      if type == "object" and (.message | type) == "string" then
        .message
        | capture("(?<id>[A-Za-z0-9._:-]+)$").id
      else
        empty
      end
    ' "$response_file" 2>/dev/null || true)"
    entry_id="$message_entry_id"
  fi
  if [[ -z "$entry_id" || "$entry_id" == "null" || ! "$entry_id" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "walter-audit-chain: Rekor duplicate response missing existing entry id" >&2
    return 1
  fi
  printf '%s' "$entry_id"
}

_walter_audit_rekor_stderr_snippet() {
  local path="$1"
  [[ -s "$path" ]] || return 0
  sed -n 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//; /^[[:space:]]*$/d; p; q' "$path"
}

_walter_audit_rekor_status_allowed() {
  local http_status="$1" allowed_statuses="$2" status
  [[ -n "$allowed_statuses" ]] || return 1
  local old_ifs="$IFS"
  IFS=,
  for status in $allowed_statuses; do
    if [[ "$http_status" == "$status" ]]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

_walter_audit_rekor_curl() {
  local method="$1" url="$2" output="$3" error="$4" timeout="$5" data_file="${6:-}"
  local allowed_statuses="${7:-}" status_file="${8:-}" headers_file="${9:-}"
  local http_status curl_status errexit_was_set=0
  local -a curl_args

  curl_args=(-sS -o "$output" -w "%{http_code}" --connect-timeout "$timeout" --max-time "$timeout")
  if [[ -n "$headers_file" ]]; then
    curl_args+=(-D "$headers_file")
  fi
  if [[ "$method" == "POST" ]]; then
    curl_args+=(-X POST -H "Content-Type: application/json" --data-binary "@${data_file}")
  fi
  curl_args+=("$url")

  case "$-" in
    *e*)
      errexit_was_set=1
      set +e
      ;;
  esac
  http_status="$(curl "${curl_args[@]}" 2>"$error")"
  curl_status="$?"
  if [[ "$errexit_was_set" -eq 1 ]]; then
    set -e
  fi
  if [[ -n "$status_file" ]]; then
    printf '%s' "$http_status" > "$status_file" || return 1
  fi
  if [[ "$curl_status" -ne 0 ]]; then
    local stderr_snippet
    stderr_snippet="$(_walter_audit_rekor_stderr_snippet "$error")"
    echo "walter-audit-chain: unable to contact Rekor (curl exit ${curl_status}); check WALTER_AUDIT_REKOR_URL/--rekor-url and network reachability" >&2
    if [[ -n "$stderr_snippet" ]]; then
      echo "walter-audit-chain: curl stderr: $stderr_snippet" >&2
    fi
    return 1
  fi
  if [[ "$http_status" == "401" || "$http_status" == "403" ]]; then
    echo "walter-audit-chain: Rekor authentication failed (HTTP ${http_status})" >&2
    return 1
  fi
  if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    if _walter_audit_rekor_status_allowed "$http_status" "$allowed_statuses"; then
      return 0
    fi
    echo "walter-audit-chain: Rekor request failed (HTTP ${http_status})" >&2
    return 1
  fi
  return 0
}

_walter_audit_rekor_verify_response_material() {
  local response_file="$1" entry_id="$2" expected_hash="$3" expected_sig="$4" expected_public_key="$5" final_public_key="${6:-}"
  local tmp_dir body_file sig_file pub_file digest_file body_value remote_hash remote_sig remote_public_key
  local openssl_bin

  tmp_dir="$(_walter_audit_mktemp_dir audit-rekor-binding)" || return 1
  body_file="$tmp_dir/body.json"
  sig_file="$tmp_dir/sig.bin"
  pub_file="$tmp_dir/pub.pem"
  digest_file="$tmp_dir/digest.bin"
  body_value="$(jq -er --arg entry_id "$entry_id" '.[$entry_id].body // empty' "$response_file" 2>/dev/null)" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor response missing decodable entry body" >&2
    return 1
  }
  if ! _walter_audit_b64_any_decode_to_file "$body_value" "$body_file"; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor response missing decodable entry body" >&2
    return 1
  fi
  remote_hash="$(jq -er '.spec.data.hash.value // empty' "$body_file" 2>/dev/null)" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry body missing payload hash" >&2
    return 1
  }
  if [[ "$remote_hash" != "$expected_hash" ]]; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry payload hash mismatch for ${entry_id}" >&2
    echo "  expected: $expected_hash" >&2
    echo "  actual:   $remote_hash" >&2
    return 1
  fi
  remote_sig="$(jq -er '.spec.signature.content // empty' "$body_file" 2>/dev/null)" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry body missing signature" >&2
    return 1
  }
  remote_public_key="$(jq -er '.spec.signature.publicKey.content // empty' "$body_file" 2>/dev/null)" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry body missing public key" >&2
    return 1
  }
  if [[ -n "$final_public_key" && "$remote_public_key" != "$final_public_key" ]]; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry public key does not match final audit session key for ${entry_id}" >&2
    return 1
  fi
  if [[ "$remote_sig" != "$expected_sig" ]]; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry signature mismatch for ${entry_id}" >&2
    return 1
  fi
  if [[ "$remote_public_key" != "$expected_public_key" ]]; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry public key mismatch for ${entry_id}" >&2
    return 1
  fi
  if ! _walter_audit_resolve_openssl; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: ED25519-capable openssl missing" >&2
    return 3
  fi
  openssl_bin="$_WALTER_AUDIT_OPENSSL_BIN"
  _walter_audit_hex_to_file "$expected_hash" "$digest_file" || {
    rm -rf "$tmp_dir"
    return 1
  }
  _walter_audit_b64_decode_to_file "$remote_sig" "$sig_file" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry signature is invalid" >&2
    return 1
  }
  _walter_audit_b64_any_decode_to_file "$remote_public_key" "$pub_file" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry public key is invalid" >&2
    return 1
  }
  if ! "$openssl_bin" pkeyutl -verify -pubin -inkey "$pub_file" -rawin -in "$digest_file" -sigfile "$sig_file" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: Rekor entry signature verification failed for ${entry_id}" >&2
    return 1
  fi
  rm -rf "$tmp_dir" || true
  return 0
}

_walter_audit_rekor_verify_response_binding() {
  local response_file="$1" entry_id="$2" expected_hash="$3" receipt_path="$4" expected_public_key="${5:-}"
  local receipt_sig receipt_public_key

  receipt_sig="$(jq -er '.sig // empty' "$receipt_path" 2>/dev/null)" || {
    echo "walter-audit-chain: Rekor receipt missing signature: $receipt_path" >&2
    return 1
  }
  receipt_public_key="$(jq -er '.public_key // empty' "$receipt_path" 2>/dev/null)" || {
    echo "walter-audit-chain: Rekor receipt missing public key: $receipt_path" >&2
    return 1
  }
  if [[ -n "$expected_public_key" && "$receipt_public_key" != "$expected_public_key" ]]; then
    echo "walter-audit-chain: Rekor receipt public key does not match final audit session key: $receipt_path" >&2
    return 1
  fi
  _walter_audit_rekor_verify_response_material "$response_file" "$entry_id" "$expected_hash" "$receipt_sig" "$receipt_public_key" "$expected_public_key"
}

_walter_audit_rekor_write_receipt() {
  local receipt_path="$1" entry_id="$2" rekor_url="$3" payload="$4" sig="$5" public_key="$6" response_file="$7"
  local payload_hash tmp_receipt
  payload_hash="$(walter_audit_hash_string "$payload")"
  tmp_receipt="${receipt_path}.tmp.${BASHPID:-$$}"
  jq -cS -n \
    --arg entry_id "$entry_id" \
    --arg payload_sha256 "$payload_hash" \
    --arg public_key "$public_key" \
    --arg rekor_url "$rekor_url" \
    --arg sig "$sig" \
    --argjson payload "$payload" \
    --slurpfile response "$response_file" \
    '{
      entry_id: $entry_id,
      payload: $payload,
      payload_sha256: $payload_sha256,
      public_key: $public_key,
      rekor_url: $rekor_url,
      response: $response[0],
      sig: $sig
    }' > "$tmp_receipt" || {
      rm -f "$tmp_receipt"
      return 1
    }
  chmod 600 "$tmp_receipt" || {
    rm -f "$tmp_receipt"
    return 1
  }
  mv "$tmp_receipt" "$receipt_path"
}

_walter_audit_rekor_receipt_payload_hash() {
  local receipt_path="$1" payload payload_hash stored_payload_hash
  payload="$(jq -cS '.payload' "$receipt_path" 2>/dev/null)" || {
    echo "walter-audit-chain: invalid Rekor receipt JSON: $receipt_path" >&2
    return 1
  }
  payload_hash="$(walter_audit_hash_string "$payload")"
  stored_payload_hash="$(jq -r '.payload_sha256 // empty' "$receipt_path" 2>/dev/null)" || {
    echo "walter-audit-chain: invalid Rekor receipt JSON: $receipt_path" >&2
    return 1
  }
  if [[ "$payload_hash" != "$stored_payload_hash" ]]; then
    echo "walter-audit-chain: Rekor receipt payload hash mismatch: $receipt_path" >&2
    return 1
  fi
  printf '%s' "$payload_hash"
}

_walter_audit_rekor_receipt_required_fields() {
  local receipt_path="$1" field
  for field in entry_id sig public_key; do
    jq -er --arg field "$field" '.[$field] // empty' "$receipt_path" >/dev/null 2>&1 || {
      echo "walter-audit-chain: Rekor receipt missing ${field}: $receipt_path" >&2
      return 1
    }
  done
}

walter_audit_rekor_upload() {
  [[ "$#" -ge 3 && "$#" -le 4 ]] || {
    echo "walter-audit-chain: usage: walter_audit_rekor_upload <date> <root> <chain-path> [rekor-url]" >&2
    return 2
  }
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="$1" root_hash="$2" chain_path="$3" configured_url="${4:-}" audit_dir chain_root
  local receipt_path receipt_url stored_rekor_url rekor_url timeout session_id payload payload_hash sig public_key_file public_key request_body entry_id
  local sign_status
  local receipt_date tmp_dir digest_file request_file response_file error_file headers_file status_file endpoint post_status fetched_entry_id

  _walter_audit_check_date_arg "$date_value" "date" || return $?
  _walter_audit_check_sha256_arg "$root_hash" "root hash" || return $?
  if [[ ! -f "$chain_path" ]]; then
    echo "walter-audit-chain: chain not found: $chain_path" >&2
    return 2
  fi
  chain_root="$(_walter_audit_chain_root_for_path "$chain_path")" || return $?
  if [[ "$chain_root" != "$root_hash" ]]; then
    echo "walter-audit-chain: Rekor root does not match final chain row: $chain_path" >&2
    echo "  expected: $chain_root" >&2
    echo "  actual:   $root_hash" >&2
    return 2
  fi

  audit_dir="$(walter_audit_dir)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1

  rekor_url="$(_walter_audit_rekor_url "$configured_url")" || return $?
  receipt_path="$(walter_audit_rekor_receipt_path "$date_value")"
  if [[ -f "$receipt_path" ]]; then
    _walter_audit_rekor_receipt_payload_hash "$receipt_path" >/dev/null || return $?
    _walter_audit_rekor_receipt_required_fields "$receipt_path" || return $?
    receipt_date="$(jq -r '.payload.date // empty' "$receipt_path")" || {
      echo "walter-audit-chain: invalid Rekor receipt JSON: $receipt_path" >&2
      return 1
    }
    if [[ "$receipt_date" != "$date_value" ]]; then
      echo "walter-audit-chain: Rekor receipt date mismatch: $receipt_path" >&2
      return 1
    fi
    if [[ "$(jq -r '.payload.root // empty' "$receipt_path")" != "$root_hash" ]]; then
      echo "walter-audit-chain: Rekor receipt root mismatch: $receipt_path" >&2
      return 1
    fi
    receipt_url="$(jq -r '.rekor_url // empty' "$receipt_path")" || {
      echo "walter-audit-chain: invalid Rekor receipt JSON: $receipt_path" >&2
      return 1
    }
    if [[ -z "$receipt_url" ]]; then
      echo "walter-audit-chain: Rekor receipt URL missing: $receipt_path" >&2
      return 1
    fi
    stored_rekor_url="$(_walter_audit_rekor_url "$receipt_url")" || {
      echo "walter-audit-chain: Rekor receipt URL invalid: $receipt_path" >&2
      return 1
    }
    if [[ "$stored_rekor_url" != "$rekor_url" ]]; then
      echo "walter-audit-chain: Rekor receipt URL mismatch: $receipt_path" >&2
      echo "  expected: $rekor_url" >&2
      echo "  actual:   $stored_rekor_url" >&2
      return 1
    fi
    session_id="$(_walter_audit_last_session_id_for_day "$chain_path")" || return $?
    public_key_file="$(_walter_audit_public_key_file "$session_id")" || {
      echo "walter-audit-chain: cannot verify Rekor receipt: public key missing for session ${session_id}" >&2
      return 2
    }
    public_key="$(_walter_audit_b64_encode_file "$public_key_file")" || return 1
    walter_audit_verify_rekor_anchor "$date_value" "$root_hash" "$rekor_url" "$public_key" || return $?
    printf 'ok: Rekor receipt already exists: %s\n' "$receipt_path"
    return 0
  fi

  timeout="$(_walter_audit_rekor_timeout)" || return $?
  if ! command -v curl >/dev/null 2>&1; then
    echo "walter-audit-chain: curl required for Rekor upload" >&2
    return 3
  fi
  _walter_audit_require_python3 || return 3

  session_id="$(_walter_audit_last_session_id_for_day "$chain_path")" || return $?
  payload="$(_walter_audit_rekor_payload "$date_value" "$root_hash")" || return $?
  payload_hash="$(walter_audit_hash_string "$payload")"
  tmp_dir="$(_walter_audit_mktemp_dir audit-rekor-upload)" || return 1
  digest_file="$tmp_dir/payload.sha256.bin"
  _walter_audit_hex_to_file "$payload_hash" "$digest_file" || {
    rm -rf "$tmp_dir"
    return 1
  }
  if sig="$(_walter_audit_sign_file "$digest_file" "$session_id" "Rekor payload digest")"; then
    :
  else
    sign_status="$?"
    rm -rf "$tmp_dir"
    return "$sign_status"
  fi
  public_key_file="$(_walter_audit_public_key_file "$session_id")" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: cannot anchor Rekor receipt: public key missing for session ${session_id}" >&2
    return 2
  }
  public_key="$(_walter_audit_b64_encode_file "$public_key_file")" || {
    rm -rf "$tmp_dir"
    return 1
  }
  request_body="$(_walter_audit_rekor_request_body "$payload" "$sig" "$public_key" "$payload_hash")" || {
    rm -rf "$tmp_dir"
    return 1
  }

  request_file="$tmp_dir/request.json"
  response_file="$tmp_dir/response.json"
  error_file="$tmp_dir/error.txt"
  headers_file="$tmp_dir/headers.txt"
  status_file="$tmp_dir/status.txt"
  printf '%s' "$request_body" > "$request_file" || {
    rm -rf "$tmp_dir"
    return 1
  }
  endpoint="${rekor_url}/api/v1/log/entries"
  if ! _walter_audit_rekor_curl "POST" "$endpoint" "$response_file" "$error_file" "$timeout" "$request_file" "409" "$status_file" "$headers_file"; then
    rm -rf "$tmp_dir"
    return 1
  fi
  post_status="$(cat "$status_file" 2>/dev/null || true)"
  if [[ "$post_status" == "409" ]]; then
    entry_id="$(_walter_audit_rekor_conflict_entry_id "$headers_file" "$response_file")" || {
      rm -rf "$tmp_dir"
      return 1
    }
    endpoint="${rekor_url}/api/v1/log/entries/${entry_id}"
    if ! _walter_audit_rekor_curl "GET" "$endpoint" "$response_file" "$error_file" "$timeout"; then
      rm -rf "$tmp_dir"
      return 1
    fi
    fetched_entry_id="$(_walter_audit_rekor_entry_id "$response_file")" || {
      rm -rf "$tmp_dir"
      return 1
    }
    if [[ "$fetched_entry_id" != "$entry_id" ]]; then
      echo "walter-audit-chain: Rekor duplicate entry id mismatch for ${entry_id}" >&2
      rm -rf "$tmp_dir"
      return 1
    fi
  else
    entry_id="$(_walter_audit_rekor_entry_id "$response_file")" || {
      rm -rf "$tmp_dir"
      return 1
    }
  fi
  _walter_audit_rekor_verify_response_material "$response_file" "$entry_id" "$payload_hash" "$sig" "$public_key" "$public_key" || {
    rm -rf "$tmp_dir"
    return 1
  }
  _walter_audit_rekor_write_receipt "$receipt_path" "$entry_id" "$rekor_url" "$payload" "$sig" "$public_key" "$response_file" || {
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: unable to write Rekor receipt: $receipt_path" >&2
    return 1
  }
  rm -rf "$tmp_dir"
  printf 'ok: anchored audit root in Rekor %s: %s\n' "$entry_id" "$receipt_path"
}

walter_audit_verify_rekor_anchor() {
  [[ "$#" -ge 2 && "$#" -le 4 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_rekor_anchor <date> <root> [rekor-url] [expected-public-key]" >&2
    return 2
  }
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="$1" root_hash="$2" configured_url="${3:-}" expected_public_key="${4:-}"
  local receipt_path receipt_root receipt_url entry_id payload_hash rekor_url timeout tmp_dir response_file error_file endpoint

  _walter_audit_check_date_arg "$date_value" "date" || return $?
  _walter_audit_check_sha256_arg "$root_hash" "root hash" || return $?

  receipt_path="$(walter_audit_rekor_receipt_path "$date_value")"
  if [[ ! -f "$receipt_path" ]]; then
    echo "walter-audit-chain: Rekor receipt not found: $receipt_path" >&2
    return 1
  fi
  receipt_root="$(jq -r '.payload.root // empty' "$receipt_path" 2>/dev/null)" || {
    echo "walter-audit-chain: invalid Rekor receipt JSON: $receipt_path" >&2
    return 1
  }
  if [[ "$receipt_root" != "$root_hash" ]]; then
    echo "walter-audit-chain: Rekor receipt root mismatch: $receipt_path" >&2
    return 1
  fi
  if [[ "$(jq -r '.payload.date // empty' "$receipt_path")" != "$date_value" ]]; then
    echo "walter-audit-chain: Rekor receipt date mismatch: $receipt_path" >&2
    return 1
  fi
  payload_hash="$(_walter_audit_rekor_receipt_payload_hash "$receipt_path")" || return $?
  entry_id="$(jq -er '.entry_id // empty' "$receipt_path" 2>/dev/null)" || {
    echo "walter-audit-chain: Rekor receipt missing entry id: $receipt_path" >&2
    return 1
  }
  receipt_url="$(jq -r '.rekor_url // empty' "$receipt_path")" || {
    echo "walter-audit-chain: invalid Rekor receipt JSON: $receipt_path" >&2
    return 1
  }
  if [[ -z "$receipt_url" ]]; then
    echo "walter-audit-chain: Rekor receipt URL missing: $receipt_path" >&2
    return 1
  fi
  if [[ -n "$configured_url" ]]; then
    rekor_url="$(_walter_audit_rekor_url "$configured_url")" || return $?
  elif [[ -n "${WALTER_AUDIT_REKOR_URL:-}" ]]; then
    rekor_url="$(_walter_audit_rekor_url)" || return $?
  else
    rekor_url="$(_walter_audit_rekor_url "$receipt_url")" || return $?
  fi
  timeout="$(_walter_audit_rekor_timeout)" || return $?
  if ! command -v curl >/dev/null 2>&1; then
    echo "walter-audit-chain: curl required for Rekor verification" >&2
    return 3
  fi
  _walter_audit_require_python3 || return 3

  tmp_dir="$(_walter_audit_mktemp_dir audit-rekor-verify)" || return 1
  response_file="$tmp_dir/response.json"
  error_file="$tmp_dir/error.txt"
  endpoint="${rekor_url}/api/v1/log/entries/${entry_id}"
  if ! _walter_audit_rekor_curl "GET" "$endpoint" "$response_file" "$error_file" "$timeout"; then
    rm -rf "$tmp_dir"
    return 1
  fi
  _walter_audit_rekor_verify_response_binding "$response_file" "$entry_id" "$payload_hash" "$receipt_path" "$expected_public_key" || {
    rm -rf "$tmp_dir"
    return 1
  }
  rm -rf "$tmp_dir"
  printf 'ok: verified Rekor anchor %s\n' "$entry_id"
}

walter_audit_verify_chain_with_rekor() {
  [[ "$#" -le 2 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain_with_rekor [date] [rekor-url]" >&2
    return 2
  }
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="${1:-$(walter_audit_date)}" configured_url="${2:-}" audit_dir lock_path chain_path verify_result verify_status row_count root_hash
  local expected_session_id expected_public_key_file expected_public_key
  _walter_audit_check_date_arg "$date_value" "date" || return $?

  audit_dir="$(walter_audit_dir)"
  chain_path="$(walter_audit_chain_path "$date_value")"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1
  _walter_audit_acquire_lock "$lock_path" || return 1
  if verify_result="$(_walter_audit_verify_chain_day_unlocked "$date_value")"; then
    verify_status=0
    read -r row_count root_hash <<< "$verify_result"
    expected_session_id="$(_walter_audit_last_session_id_for_day "$chain_path")" || {
      verify_status="$?"
      _walter_audit_release_lock "$lock_path"
      return "$verify_status"
    }
    expected_public_key_file="$(_walter_audit_public_key_file "$expected_session_id")" || {
      echo "walter-audit-chain: cannot verify Rekor receipt: public key missing for session ${expected_session_id}" >&2
      _walter_audit_release_lock "$lock_path"
      return 2
    }
    expected_public_key="$(_walter_audit_b64_encode_file "$expected_public_key_file")" || {
      _walter_audit_release_lock "$lock_path"
      return 1
    }
    if walter_audit_verify_rekor_anchor "$date_value" "$root_hash" "$configured_url" "$expected_public_key"; then
      verify_status=0
      printf 'ok: verified %s row(s): %s\n' "$row_count" "$chain_path"
    else
      verify_status="$?"
    fi
  else
    verify_status="$?"
  fi
  _walter_audit_release_lock "$lock_path"
  return "$verify_status"
}

walter_audit_close_day() {
  local rekor_url="" positional=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --rekor-url)
        if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
          echo "walter-audit-chain: --rekor-url <url> required" >&2
          return 2
        fi
        rekor_url="$2"
        shift 2
        ;;
      --*)
        echo "walter-audit-chain: unsupported close-day option: $1" >&2
        echo "walter-audit-chain: usage: walter_audit_close_day [--rekor-url <url>] [date]" >&2
        return 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  [[ "${#positional[@]}" -le 1 ]] || {
    echo "walter-audit-chain: usage: walter_audit_close_day [--rekor-url <url>] [date]" >&2
    return 2
  }
  if [[ -n "$rekor_url" && "${WALTER_AUDIT_REKOR_UPLOAD:-0}" != "1" ]]; then
    echo "walter-audit-chain: --rekor-url requires WALTER_AUDIT_REKOR_UPLOAD=1" >&2
    return 2
  fi
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="${positional[0]:-$(walter_audit_date)}" audit_dir chain_path root_path lock_path row_count close_status root_hash previous_line upload_status=0
  _walter_audit_check_date_arg "$date_value" "date" || return $?
  audit_dir="$(walter_audit_dir)"
  chain_path="$(walter_audit_chain_path "$date_value")"
  root_path="$(walter_audit_root_path "$date_value")"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1
  _walter_audit_acquire_lock "$lock_path" || return 1
  if [[ ! -f "$chain_path" ]]; then
    echo "walter-audit-chain: chain not found: $chain_path" >&2
    _walter_audit_release_lock "$lock_path"
    return 1
  fi

  close_status=0
  if row_count="$(_walter_audit_verify_chain_file_unlocked "$chain_path")"; then
    if ! previous_line="$(tail -n 1 "$chain_path")" || [[ -z "$previous_line" ]]; then
      echo "walter-audit-chain: unable to read final row: $chain_path" >&2
      close_status=1
    else
      root_hash="$(walter_audit_hash_string "$previous_line")"
    fi
    if [[ "$close_status" -ne 0 ]]; then
      :
    elif [[ -f "$root_path" ]]; then
      if _walter_audit_verify_root_unlocked "$root_path" "$root_hash"; then
        close_status=0
      else
        close_status="$?"
      fi
    elif _walter_audit_write_root_unlocked "$root_path" "$root_hash"; then
      close_status=0
    else
      close_status="$?"
    fi
  else
    close_status="$?"
  fi
  if [[ "$close_status" -eq 0 ]]; then
    if [[ "${WALTER_AUDIT_REKOR_UPLOAD:-0}" == "1" ]]; then
      if walter_audit_rekor_upload "$date_value" "$root_hash" "$chain_path" "$rekor_url"; then
        upload_status=0
      else
        upload_status="$?"
      fi
    fi
    if [[ "$upload_status" -eq 0 ]]; then
      printf 'ok: closed audit day %s (%s row(s)): %s\n' "$date_value" "$row_count" "$root_path"
    fi
  fi
  _walter_audit_release_lock "$lock_path"
  [[ "$close_status" -eq 0 ]] || return "$close_status"
  return "$upload_status"
}

_walter_audit_verify_prev_chain_root() {
  local date_value="$1" expected_root="$2" chain_path first_line actual_root
  chain_path="$(walter_audit_chain_path "$date_value")"
  first_line="$(sed -n '1p' "$chain_path")" || return 1
  actual_root="$(printf '%s\n' "$first_line" | jq -r '.prev_chain_root // empty')" || {
    echo "walter-audit-chain: ${date_value}: invalid first row" >&2
    return 1
  }
  if [[ "$actual_root" != "$expected_root" ]]; then
    echo "walter-audit-chain: ${date_value}: prev_chain_root mismatch" >&2
    echo "  expected: $expected_root" >&2
    echo "  actual:   ${actual_root:-<missing>}" >&2
    return 1
  fi
}

_walter_audit_date_step() {
  local date_value="$1" next_date next_status
  next_date="$(_walter_audit_date_add_days "$date_value" 1)"
  next_status="$?"
  [[ "$next_status" -eq 0 ]] || return "$next_status"
  printf '%s' "$next_date"
}

_walter_audit_previous_date_checked() {
  local date_value="$1" previous_date previous_status
  previous_date="$(_walter_audit_previous_date "$date_value")"
  previous_status="$?"
  [[ "$previous_status" -eq 0 ]] || return "$previous_status"
  printf '%s' "$previous_date"
}

_walter_audit_verify_chain_range_unlocked() {
  local since_date="$1" until_date="$2" current_date previous_date expected_root current_root day_count=0 verify_result step_status

  current_date="$since_date"
  expected_root=""
  while [[ "$current_date" == "$until_date" || "$current_date" < "$until_date" ]]; do
    verify_result="$(_walter_audit_verify_chain_day_unlocked "$current_date")" || return $?
    read -r _ current_root <<< "$verify_result"

    if [[ "$day_count" -eq 0 ]]; then
      previous_date="$(_walter_audit_previous_date_checked "$current_date")"
      step_status="$?"
      [[ "$step_status" -eq 0 ]] || return "$step_status"
      if [[ -f "$(walter_audit_root_path "$previous_date")" ]]; then
        expected_root="$(_walter_audit_read_root_file "$(walter_audit_root_path "$previous_date")")" || return $?
        _walter_audit_verify_prev_chain_root "$current_date" "$expected_root" || return $?
      fi
    else
      _walter_audit_verify_prev_chain_root "$current_date" "$expected_root" || return $?
    fi

    expected_root="$current_root"
    day_count=$((day_count + 1))
    [[ "$current_date" != "$until_date" ]] || break
    current_date="$(_walter_audit_date_step "$current_date")"
    step_status="$?"
    [[ "$step_status" -eq 0 ]] || return "$step_status"
  done

  printf 'ok: verified %s day(s): %s..%s\n' "$day_count" "$since_date" "$until_date"
}

walter_audit_verify_chain_range() {
  [[ "$#" -ge 1 && "$#" -le 2 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain_range <since> [until]" >&2
    return 2
  }
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local since_date="$1" until_date="${2:-$(walter_audit_date)}" audit_dir lock_path range_status
  _walter_audit_check_date_arg "$since_date" "since date" || return $?
  _walter_audit_check_date_arg "$until_date" "until date" || return $?
  if [[ "$since_date" > "$until_date" ]]; then
    echo "walter-audit-chain: --since must be on or before --until" >&2
    return 2
  fi

  audit_dir="$(walter_audit_dir)"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1
  _walter_audit_acquire_lock "$lock_path" || return 1
  if _walter_audit_verify_chain_range_unlocked "$since_date" "$until_date"; then
    range_status=0
  else
    range_status="$?"
  fi
  _walter_audit_release_lock "$lock_path"
  return "$range_status"
}

_walter_audit_remove_loki_tmp() {
  local tmp_config="$1"
  case "$tmp_config" in
    "${TMPDIR:-/tmp}"/walter-audit-loki.*|/tmp/walter-audit-loki.*|/var/tmp/walter-audit-loki.*)
      rm -rf "$tmp_config"
      ;;
  esac
}

_walter_audit_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

_walter_audit_loki_positive_int() {
  local value="$1" label="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "walter-audit-chain: ${label} must be a positive integer" >&2
    return 2
  fi
  return 0
}

_walter_audit_loki_stderr_snippet() {
  local path="$1"
  [[ -s "$path" ]] || return 0
  sed -n 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//; /^[[:space:]]*$/d; p; q' "$path"
}

_walter_audit_loki_date_epoch() {
  local date_value="$1" epoch
  if [[ ! "$date_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "walter-audit-chain: invalid Loki date: $date_value" >&2
    return 2
  fi
  if epoch="$(date -u -j -f "%Y-%m-%d" "$date_value" "+%s" 2>/dev/null)"; then
    printf '%s' "$epoch"
    return 0
  fi
  if epoch="$(date -u -d "${date_value}T00:00:00Z" "+%s" 2>/dev/null)"; then
    printf '%s' "$epoch"
    return 0
  fi
  echo "walter-audit-chain: invalid Loki date: $date_value" >&2
  return 2
}

_walter_audit_loki_range_ns() {
  local date_value="$1" start_epoch end_epoch
  start_epoch="$(_walter_audit_loki_date_epoch "$date_value")" || return $?
  end_epoch=$((start_epoch + 86400))
  printf '%s\n%s\n' "$((start_epoch * 1000000000))" "$(((end_epoch * 1000000000) - 1))"
}

_walter_audit_verify_chain_from_loki_response() {
  [[ "$#" -eq 4 ]] || {
    echo "walter-audit-chain: usage: _walter_audit_verify_chain_from_loki_response <response> <date> <source-label> <success-label>" >&2
    return 2
  }
  local response_file="$1" date_value="$2" source_label="$3" success_label="$4"
  local tmp_config tmp_audit values_count previous_line root_hash verify_status

  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi
  _walter_audit_loki_date_epoch "$date_value" >/dev/null || return $?

  tmp_config="$(mktemp -d "${TMPDIR:-/tmp}/walter-audit-loki.XXXXXX")" || return 1
  tmp_audit="${tmp_config}/audit"
  mkdir -p "$tmp_audit" || {
    _walter_audit_remove_loki_tmp "$tmp_config"
    return 1
  }

  values_count="$(jq 'reduce .data.result[]? as $stream (0; . + (($stream.values // []) | length))' "$response_file" 2>/dev/null)" || {
    _walter_audit_remove_loki_tmp "$tmp_config"
    echo "walter-audit-chain: invalid Loki response JSON: $source_label" >&2
    return 1
  }
  if [[ "$values_count" -eq 0 ]]; then
    _walter_audit_remove_loki_tmp "$tmp_config"
    echo "walter-audit-chain: no audit-chain rows found in Loki response: $source_label" >&2
    return 1
  fi

  jq -r '[.data.result[]?.values[]?] | sort_by(.[0]) | .[][1]' \
    "$response_file" > "${tmp_audit}/chain-${date_value}.jsonl" || {
      _walter_audit_remove_loki_tmp "$tmp_config"
      echo "walter-audit-chain: failed to extract Loki response rows: $source_label" >&2
      return 1
    }
  if [[ ! -s "${tmp_audit}/chain-${date_value}.jsonl" ]]; then
    _walter_audit_remove_loki_tmp "$tmp_config"
    echo "walter-audit-chain: no audit-chain rows found in Loki response: $source_label" >&2
    return 1
  fi

  previous_line="$(tail -n 1 "${tmp_audit}/chain-${date_value}.jsonl")"
  root_hash="$(walter_audit_hash_string "$previous_line")"
  printf '%s' "$root_hash" > "${tmp_audit}/root-${date_value}.txt" || {
    _walter_audit_remove_loki_tmp "$tmp_config"
    return 1
  }

  if WALTER_AUDIT_DIR="$tmp_audit" walter_audit_verify_chain "$date_value"; then
    verify_status=0
  else
    verify_status="$?"
  fi
  _walter_audit_remove_loki_tmp "$tmp_config"
  [[ "$verify_status" -eq 0 ]] || return "$verify_status"

  printf 'ok: verified %s\n' "$success_label"
}

walter_audit_verify_chain_from_loki_fixture() {
  [[ "$#" -ge 1 && "$#" -le 2 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain_from_loki_fixture <fixture> [date]" >&2
    return 2
  }
  local fixture="$1" date_value="${2:-$(walter_audit_date)}"

  if [[ ! -f "$fixture" ]]; then
    echo "walter-audit-chain: Loki fixture not found: $fixture" >&2
    return 1
  fi
  _walter_audit_verify_chain_from_loki_response \
    "$fixture" \
    "$date_value" \
    "Loki fixture: $fixture" \
    "from Loki fixture: $fixture"
}

walter_audit_verify_chain_from_loki_live() {
  [[ "$#" -le 2 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain_from_loki_live [date] [url]" >&2
    return 2
  }
  local date_value="${1:-$(walter_audit_date)}" configured_url="${2:-${WALTER_AUDIT_LOKI_URL:-}}"
  local loki_url endpoint token timeout limit query range_ns start_ns end_ns tmp_response tmp_error http_status curl_status verify_status errexit_was_set=0
  local -a curl_args

  loki_url="$(_walter_audit_trim "$configured_url")"
  if [[ -z "$loki_url" ]]; then
    echo "walter-audit-chain: live Loki URL required; set WALTER_AUDIT_LOKI_URL or pass --loki-url" >&2
    return 2
  fi
  case "$loki_url" in
    http://*|https://*) ;;
    *)
      echo "walter-audit-chain: live Loki URL from WALTER_AUDIT_LOKI_URL or --loki-url must start with http:// or https://" >&2
      return 2
      ;;
  esac
  if ! command -v curl >/dev/null 2>&1; then
    echo "walter-audit-chain: curl required for live Loki verification" >&2
    return 3
  fi

  timeout="${WALTER_AUDIT_LOKI_TIMEOUT_SECONDS:-10}"
  _walter_audit_loki_positive_int "$timeout" "WALTER_AUDIT_LOKI_TIMEOUT_SECONDS" || return $?
  if [[ "$timeout" -gt 300 ]]; then
    echo "walter-audit-chain: WALTER_AUDIT_LOKI_TIMEOUT_SECONDS must be <= 300" >&2
    return 2
  fi

  limit="${WALTER_AUDIT_LOKI_LIMIT:-5000}"
  _walter_audit_loki_positive_int "$limit" "WALTER_AUDIT_LOKI_LIMIT" || return $?

  range_ns="$(_walter_audit_loki_range_ns "$date_value")" || return $?
  start_ns="$(printf '%s\n' "$range_ns" | sed -n '1p')"
  end_ns="$(printf '%s\n' "$range_ns" | sed -n '2p')"
  query="${WALTER_AUDIT_LOKI_QUERY:-{app=\"walter-os\", kind=\"audit-chain\"}}"
  token="${WALTER_AUDIT_LOKI_TOKEN:-}"
  endpoint="${loki_url%/}/loki/api/v1/query_range"

  tmp_response="$(mktemp "${TMPDIR:-/tmp}/walter-audit-loki-response.XXXXXX")" || return 1
  tmp_error="$(mktemp "${TMPDIR:-/tmp}/walter-audit-loki-error.XXXXXX")" || {
    rm -f "$tmp_response"
    return 1
  }

  curl_args=(-sS -o "$tmp_response" -w "%{http_code}" --connect-timeout "$timeout" --max-time "$timeout")
  if [[ -n "$token" ]]; then
    curl_args+=(-H "Authorization: Bearer $token")
  fi
  curl_args+=(--get "$endpoint" --data-urlencode "query=$query" --data-urlencode "start=$start_ns" --data-urlencode "end=$end_ns" --data-urlencode "limit=$limit")

  case "$-" in
    *e*)
      errexit_was_set=1
      set +e
      ;;
  esac
  http_status="$(curl "${curl_args[@]}" 2>"$tmp_error")"
  curl_status="$?"
  if [[ "$errexit_was_set" -eq 1 ]]; then
    set -e
  fi
  if [[ "$curl_status" -ne 0 ]]; then
    local stderr_snippet
    stderr_snippet="$(_walter_audit_loki_stderr_snippet "$tmp_error")"
    rm -f "$tmp_response" "$tmp_error"
    echo "walter-audit-chain: unable to query Loki (curl exit ${curl_status}); check WALTER_AUDIT_LOKI_URL/--loki-url and network reachability" >&2
    if [[ -n "$stderr_snippet" ]]; then
      echo "walter-audit-chain: curl stderr: $stderr_snippet" >&2
    fi
    return 1
  fi
  if [[ "$http_status" == "401" || "$http_status" == "403" ]]; then
    rm -f "$tmp_response" "$tmp_error"
    echo "walter-audit-chain: Loki authentication failed (HTTP ${http_status}); check WALTER_AUDIT_LOKI_TOKEN" >&2
    return 1
  fi
  if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "$tmp_response" "$tmp_error"
    echo "walter-audit-chain: Loki query failed (HTTP ${http_status})" >&2
    return 1
  fi

  if _walter_audit_verify_chain_from_loki_response \
    "$tmp_response" \
    "$date_value" \
    "live Loki response" \
    "from live Loki"; then
    verify_status=0
  else
    verify_status="$?"
  fi
  rm -f "$tmp_response" "$tmp_error"
  return "$verify_status"
}
