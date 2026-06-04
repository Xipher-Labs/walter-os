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
  local state_file session_id
  if [[ -n "${WALTER_SESSION_ID:-}" ]]; then
    session_id="$WALTER_SESSION_ID"
  else
    state_file="$(_walter_audit_session_state_file)" || return 1
    [[ -f "$state_file" ]] || return 1
    if _walter_audit_jq_available; then
      session_id="$(jq -r '.session_id // empty' "$state_file" 2>/dev/null || true)"
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
if isinstance(session_id, str):
    print(session_id, end="")
PY
)" || {
        echo "walter-audit-chain: invalid session state: $state_file" >&2
        return 1
      }
    fi
  fi
  [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
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
    raise SystemExit("invalid signature base64")
try:
    data = base64.b64decode(value.encode("ascii"), validate=True)
except (binascii.Error, ValueError) as exc:
    raise SystemExit(f"invalid signature base64: {exc}")
if len(data) != 64:
    raise SystemExit("invalid signature length")
if base64.b64encode(data).decode("ascii") != value:
    raise SystemExit("non-canonical signature base64")
pathlib.Path(sys.argv[2]).write_bytes(data)
PY
}

_walter_audit_sign_row() {
  local row_json="$1" session_id="${2:-}" session_status private_key openssl_bin tmp_dir payload_file sig_file sig
  _walter_audit_require_python3 || return 1
  if [[ -z "$session_id" ]]; then
    session_id="$(_walter_audit_current_session_id)"
    session_status="$?"
    if [[ "$session_status" -ne 0 ]]; then
      [[ "$session_status" -eq 3 ]] && return 3
      echo "walter-audit-chain: active session id required for signed audit row" >&2
      return 2
    fi
  fi
  [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "walter-audit-chain: invalid session id for signed audit row" >&2
    return 2
  }
  private_key="$(_walter_audit_private_key_file "$session_id")"
  [[ -f "$private_key" ]] || {
    echo "walter-audit-chain: session private key missing for signed audit row: $session_id" >&2
    return 2
  }
  if ! _walter_audit_resolve_openssl; then
    echo "walter-audit-chain: ED25519-capable openssl missing" >&2
    return 3
  fi
  openssl_bin="$_WALTER_AUDIT_OPENSSL_BIN"

  tmp_dir="$(mktemp -d)" || {
    echo "walter-audit-chain: temporary directory unavailable for signing" >&2
    return 1
  }
  payload_file="$tmp_dir/payload.json"
  sig_file="$tmp_dir/sig.bin"
  printf '%s' "$row_json" > "$payload_file"
  if ! "$openssl_bin" pkeyutl -sign -inkey "$private_key" -rawin -in "$payload_file" -out "$sig_file" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    return 1
  fi
  sig="$(_walter_audit_b64_encode_file "$sig_file")" || {
    rm -rf "$tmp_dir"
    return 1
  }
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
  stored_row_hash="$(printf '%s\n' "$line" | jq -r '.row_hash // empty')" || {
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
  local line="$1" row_number="$2" session_id sig public_key openssl_bin tmp_dir payload payload_file sig_file
  sig="$(printf '%s\n' "$line" | jq -r '.sig // empty')" || {
    echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
    return 1
  }
  if [[ -z "$sig" ]]; then
    echo "walter-audit-chain: row ${row_number}: missing sig" >&2
    return 1
  fi
  if [[ ! "$sig" =~ ^[A-Za-z0-9+/]{86}==$ ]]; then
    echo "walter-audit-chain: row ${row_number}: invalid sig format" >&2
    return 1
  fi
  session_id="$(printf '%s\n' "$line" | jq -r '.session_id // empty')" || {
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

  tmp_dir="$(mktemp -d)" || {
    echo "walter-audit-chain: temporary directory unavailable for signature verification" >&2
    return 1
  }
  payload_file="$tmp_dir/payload.json"
  sig_file="$tmp_dir/sig.bin"
  payload="$(printf '%s\n' "$line" | jq -cS 'del(.sig)')" || {
    rm -rf "$tmp_dir"
    return 1
  }
  printf '%s' "$payload" > "$payload_file" || {
    rm -rf "$tmp_dir"
    return 1
  }
  _walter_audit_require_python3 || {
    rm -rf "$tmp_dir"
    return 1
  }
  if ! _walter_audit_b64_decode_to_file "$sig" "$sig_file" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: row ${row_number}: invalid sig encoding" >&2
    return 1
  fi
  if ! "$openssl_bin" pkeyutl -verify -pubin -inkey "$public_key" -rawin -in "$payload_file" -sigfile "$sig_file" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    echo "walter-audit-chain: row ${row_number}: signature verification failed" >&2
    return 1
  fi
  rm -rf "$tmp_dir"
}

_walter_audit_verify_chain_file_unlocked() {
  local chain_path="$1" line row_number prev_hash actual_hash expected_hash canonical last_hex
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
  row_number=0
  expected_hash="null"
  while IFS= read -r line || [[ -n "$line" ]]; do
    row_number=$((row_number + 1))
    canonical="$(printf '%s\n' "$line" | jq -cS . 2>/dev/null)" || {
      echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
      return 1
    }
    if [[ "$canonical" != "$line" ]]; then
      echo "walter-audit-chain: row ${row_number}: non-canonical JSON" >&2
      return 1
    fi
    if ! printf '%s\n' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
      echo "walter-audit-chain: row ${row_number}: invalid JSON object" >&2
      return 1
    fi
    _walter_audit_verify_row_hash "$line" "$row_number" || return 1
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
    _walter_audit_verify_row_signature "$line" "$row_number" || return $?
    actual_hash="$(walter_audit_hash_string "$line")"
    expected_hash="$actual_hash"
  done < "$chain_path"

  if [[ "$row_number" -eq 0 ]]; then
    echo "walter-audit-chain: empty chain: $chain_path" >&2
    return 1
  fi

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

walter_audit_append() {
  [[ "$#" -eq 5 ]] || {
    echo "walter-audit-chain: usage: walter_audit_append <tool> <input> <decision> <source> <reason>" >&2
    return 2
  }
  local tool="$1" input="$2" decision="$3" source="$4" reason="$5"
  local audit_dir chain_path root_path last_hex lock_path previous_line previous_hash pre_write_size retry_count row row_hash row_without_hash summary timestamp row_date root_hash session_id session_status sig sign_status chain_created
  audit_dir="$(walter_audit_dir)"
  lock_path="$(walter_audit_lock_path)"
  mkdir -p "$audit_dir" || return 1
  chmod 700 "$audit_dir" || return 1

  _walter_audit_acquire_lock "$lock_path" || return 1
  timestamp="$(walter_audit_timestamp)"
  row_date="$(walter_audit_date_from_timestamp "$timestamp")"
  chain_path="$(walter_audit_chain_path "$row_date")"
  root_path="$(walter_audit_root_path "$row_date")"

  chain_created=0
  if [[ ! -e "$chain_path" ]]; then
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

  summary="$(walter_audit_input_summary "$input")"
  session_id="$(_walter_audit_current_session_id)"
  session_status="$?"
  if [[ "$session_status" -ne 0 ]]; then
    exec 9>&-
    _walter_audit_release_lock "$lock_path"
    [[ "$session_status" -eq 3 ]] && return 3
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
      '{ts:$ts,session_id:$session_id,operator:$operator,event:$event,tool:$tool,input_summary:$input_summary,decision:$decision,decision_source:$decision_source,decision_reason:$decision_reason,prev_hash:$prev_hash}')" || {
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
    row_without_hash="{\"decision\":$(walter_audit_json_string "$decision"),\"decision_reason\":$(walter_audit_json_string "$reason"),\"decision_source\":$(walter_audit_json_string "$source"),\"event\":\"tool_invocation\",\"input_summary\":$(walter_audit_json_string "$summary"),\"operator\":$(walter_audit_json_string "${USER:-unknown}"),\"prev_hash\":$(walter_audit_json_string "$previous_hash"),\"session_id\":$(walter_audit_json_string "$session_id"),\"tool\":$(walter_audit_json_string "$tool"),\"ts\":$(walter_audit_json_string "$timestamp")}"
    row_hash="$(walter_audit_hash_string "$row_without_hash")"
    row="{\"decision\":$(walter_audit_json_string "$decision"),\"decision_reason\":$(walter_audit_json_string "$reason"),\"decision_source\":$(walter_audit_json_string "$source"),\"event\":\"tool_invocation\",\"input_summary\":$(walter_audit_json_string "$summary"),\"operator\":$(walter_audit_json_string "${USER:-unknown}"),\"prev_hash\":$(walter_audit_json_string "$previous_hash"),\"row_hash\":$(walter_audit_json_string "$row_hash"),\"session_id\":$(walter_audit_json_string "$session_id"),\"tool\":$(walter_audit_json_string "$tool"),\"ts\":$(walter_audit_json_string "$timestamp")}"
    if sig="$(_walter_audit_sign_row "$row" "$session_id")"; then
      :
    else
      sign_status="$?"
      exec 9>&-
      _walter_audit_release_lock "$lock_path"
      return "$sign_status"
    fi
    row="{\"decision\":$(walter_audit_json_string "$decision"),\"decision_reason\":$(walter_audit_json_string "$reason"),\"decision_source\":$(walter_audit_json_string "$source"),\"event\":\"tool_invocation\",\"input_summary\":$(walter_audit_json_string "$summary"),\"operator\":$(walter_audit_json_string "${USER:-unknown}"),\"prev_hash\":$(walter_audit_json_string "$previous_hash"),\"row_hash\":$(walter_audit_json_string "$row_hash"),\"session_id\":$(walter_audit_json_string "$session_id"),\"sig\":$(walter_audit_json_string "$sig"),\"tool\":$(walter_audit_json_string "$tool"),\"ts\":$(walter_audit_json_string "$timestamp")}"
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

walter_audit_verify_chain() {
  [[ "$#" -le 1 ]] || {
    echo "walter-audit-chain: usage: walter_audit_verify_chain [date]" >&2
    return 2
  }
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  local date_value="${1:-$(walter_audit_date)}" audit_dir chain_path root_path lock_path row_count verify_status root_hash previous_line
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

  if row_count="$(_walter_audit_verify_chain_file_unlocked "$chain_path")"; then
    previous_line="$(tail -n 1 "$chain_path")"
    root_hash="$(walter_audit_hash_string "$previous_line")"
    if _walter_audit_verify_root_unlocked "$root_path" "$root_hash"; then
      verify_status=0
    else
      verify_status="$?"
    fi
  else
    verify_status="$?"
  fi
  _walter_audit_release_lock "$lock_path"
  [[ "$verify_status" -eq 0 ]] || return "$verify_status"

  printf 'ok: verified %s row(s): %s\n' "$row_count" "$chain_path"
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

_walter_audit_loki_range_ns() {
  local date_value="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "walter-audit-chain: python3 required for Loki date range calculation" >&2
    return 3
  fi
  python3 - "$date_value" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

date_value = sys.argv[1]
try:
    start = datetime.strptime(date_value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
except ValueError:
    print(f"walter-audit-chain: invalid Loki date: {date_value}", file=sys.stderr)
    sys.exit(2)
end = start + timedelta(days=1)
print(int(start.timestamp() * 1_000_000_000))
print(int(end.timestamp() * 1_000_000_000))
PY
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

  tmp_config="$(mktemp -d "${TMPDIR:-/tmp}/walter-audit-loki.XXXXXX")" || return 1
  tmp_audit="${tmp_config}/audit"
  mkdir -p "$tmp_audit" || {
    _walter_audit_remove_loki_tmp "$tmp_config"
    return 1
  }

  values_count="$(jq '[.data.result[]?.values[]?] | length' "$response_file" 2>/dev/null)" || {
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
