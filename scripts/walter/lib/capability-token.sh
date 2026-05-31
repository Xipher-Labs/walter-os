#!/usr/bin/env bash
# scripts/walter/lib/capability-token.sh
#
# PASETO v4.public-compatible capability token helper. It intentionally avoids
# a third-party CLI dependency: the proposed `paseto-cli` package is not
# available from PyPI, so Walter-OS builds the v4.public signing shape from
# OpenSSL Ed25519, PASETO PAE, and JSON/base64 helpers from Python stdlib.

# shellcheck disable=SC2034 # used by sourced callers for diagnostics
WALTER_CAPABILITY_TOKEN_LIB_VERSION=1

_walter_cap_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_walter_cap_lib_dir}/session-state.sh"
unset _walter_cap_lib_dir

_walter_cap_require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "walter-cap: required tool missing: $tool" >&2
    return 1
  fi
}

_walter_cap_require_runtime() {
  _walter_cap_require_tool jq || return 1
  _walter_cap_require_tool python3 || return 1
}

_walter_cap_b64url_encode_file() {
  local file="$1"
  python3 - "$file" <<'PY'
import base64
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
print(base64.urlsafe_b64encode(data).decode("ascii").rstrip("="), end="")
PY
}

_walter_cap_b64url_decode_to_file() {
  local value="$1" out="$2"
  python3 - "$value" "$out" <<'PY'
import base64
import pathlib
import sys

value = sys.argv[1]
padding = "=" * (-len(value) % 4)
try:
    data = base64.urlsafe_b64decode((value + padding).encode("ascii"))
except Exception as exc:
    raise SystemExit(f"base64url decode failed: {exc}")
pathlib.Path(sys.argv[2]).write_bytes(data)
PY
}

_walter_cap_pae_to_file() {
  local payload_file="$1" footer_file="$2" out="$3"
  python3 - "$payload_file" "$footer_file" "$out" <<'PY'
import pathlib
import struct
import sys

pieces = [
    b"v4.public.",
    pathlib.Path(sys.argv[1]).read_bytes(),
    pathlib.Path(sys.argv[2]).read_bytes(),
    b"",
]
encoded = struct.pack("<Q", len(pieces))
for piece in pieces:
    encoded += struct.pack("<Q", len(piece)) + piece
pathlib.Path(sys.argv[3]).write_bytes(encoded)
PY
}

_walter_cap_split_body_to_files() {
  local body_file="$1" payload_file="$2" sig_file="$3"
  python3 - "$body_file" "$payload_file" "$sig_file" <<'PY'
import pathlib
import sys

body = pathlib.Path(sys.argv[1]).read_bytes()
if len(body) <= 64:
    raise SystemExit("token body too short")
pathlib.Path(sys.argv[2]).write_bytes(body[:-64])
pathlib.Path(sys.argv[3]).write_bytes(body[-64:])
PY
}

walter_cap_duration_to_seconds() {
  local duration="$1" value unit
  if [[ ! "$duration" =~ ^([1-9][0-9]*)([smh])$ ]]; then
    echo "walter-cap: duration must include a unit, e.g. 30s, 45m, or 4h" >&2
    return 2
  fi
  value="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"
  case "$unit" in
    s) printf '%s' "$value" ;;
    m) printf '%s' $((value * 60)) ;;
    h) printf '%s' $((value * 3600)) ;;
  esac
}

_walter_cap_state_field() {
  local state_file="$1" field="$2"
  jq -r --arg field "$field" '.[$field] // empty' "$state_file"
}

_walter_cap_validate_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || {
    echo "walter-cap: session state missing: $state_file" >&2
    return 1
  }
  jq -e '
    (.session_id | type == "string" and length > 0) and
    (.capability_private_key_path | type == "string" and length > 0) and
    (.capability_public_key_path | type == "string" and length > 0) and
    (.capability_tokens_dir | type == "string" and length > 0)
  ' "$state_file" >/dev/null
}

_walter_cap_session_end_epoch() {
  local state_file="$1" started_at max_hours started_epoch
  started_at="$(jq -r '.started_at // empty' "$state_file")"
  max_hours="$(jq -r '.max_hours_at_start // empty' "$state_file")"
  [[ "$max_hours" =~ ^[1-9][0-9]*$ ]] || return 1
  started_epoch="$(_walter_session_epoch "$started_at")"
  [[ "$started_epoch" =~ ^[0-9]+$ ]] || return 1
  printf '%s' $((started_epoch + (max_hours * 3600)))
}

_walter_cap_validate_active_session() {
  local state_file="$1" started_at last_activity_at started_epoch last_epoch now_epoch max_hours max_idle expired_trigger=""
  started_at="$(jq -r '.started_at // empty' "$state_file")"
  last_activity_at="$(jq -r '.last_activity_at // empty' "$state_file")"
  max_hours="$(jq -r '.max_hours_at_start // empty' "$state_file")"
  max_idle="$(jq -r '.max_idle_min_at_start // empty' "$state_file")"
  [[ "$max_hours" =~ ^[1-9][0-9]*$ && "$max_idle" =~ ^[1-9][0-9]*$ ]] || {
    echo "walter-cap: malformed session limits" >&2
    return 1
  }
  if ! started_epoch="$(_walter_session_epoch "$started_at")" || [[ ! "$started_epoch" =~ ^[0-9]+$ ]]; then
    echo "walter-cap: malformed session start" >&2
    return 1
  fi
  if ! last_epoch="$(_walter_session_epoch "$last_activity_at")" || [[ ! "$last_epoch" =~ ^[0-9]+$ ]]; then
    echo "walter-cap: malformed session activity" >&2
    return 1
  fi
  now_epoch="$(_walter_session_now_epoch)"
  if (( now_epoch < started_epoch || now_epoch < last_epoch )); then
    echo "walter-cap: session clock rewind" >&2
    return 1
  fi
  if (( now_epoch - last_epoch > max_idle * 60 )); then
    expired_trigger="max-idle"
  elif (( now_epoch - started_epoch > max_hours * 3600 )); then
    expired_trigger="max-hours"
  fi
  if [[ -n "$expired_trigger" ]]; then
    _walter_session_revoke_capability_material "$state_file" || true
    echo "walter-cap: session expired ($expired_trigger)" >&2
    return 1
  fi
}

walter_cap_sign_claims() {
  local state_file="$1" claims_json="$2"
  local session_id private_key tmp_dir payload_file footer_file pae_file sig_file body_file token_body token_footer openssl_bin exp exp_epoch session_end
  _walter_cap_require_runtime || return 1
  _walter_cap_validate_state "$state_file" || return 1
  _walter_cap_validate_active_session "$state_file" || return 1
  if ! openssl_bin="$(_walter_session_openssl)"; then
    echo "walter-cap: ED25519-capable openssl missing" >&2
    return 1
  fi

  session_id="$(_walter_cap_state_field "$state_file" session_id)"
  private_key="$(_walter_cap_state_field "$state_file" capability_private_key_path)"
  [[ -f "$private_key" ]] || {
    echo "walter-cap: session private key missing" >&2
    return 1
  }

  tmp_dir="$(mktemp -d)"
  payload_file="$tmp_dir/payload.json"
  footer_file="$tmp_dir/footer.json"
  pae_file="$tmp_dir/pae.bin"
  sig_file="$tmp_dir/sig.bin"
  body_file="$tmp_dir/body.bin"

  if ! printf '%s' "$claims_json" | jq -cS --arg sid "$session_id" '
    if .session_id != $sid then error("claims session_id does not match active session") else . end
  ' > "$payload_file"; then
    rm -r "$tmp_dir"
    return 1
  fi
  exp="$(jq -r '.exp // empty' "$payload_file")"
  if [[ -z "$exp" ]] || ! exp_epoch="$(_walter_session_epoch "$exp")" || [[ ! "$exp_epoch" =~ ^[0-9]+$ ]]; then
    echo "walter-cap: invalid exp claim" >&2
    rm -r "$tmp_dir"
    return 1
  fi
  session_end="$(_walter_cap_session_end_epoch "$state_file")" || {
    echo "walter-cap: cannot derive session end" >&2
    rm -r "$tmp_dir"
    return 1
  }
  if (( exp_epoch > session_end )); then
    echo "walter-cap: token exp exceeds session end" >&2
    rm -r "$tmp_dir"
    return 1
  fi
  jq -ncS --arg kid "$session_id" '{alg:"Ed25519", kid:$kid}' > "$footer_file"
  if ! _walter_cap_pae_to_file "$payload_file" "$footer_file" "$pae_file"; then
    rm -r "$tmp_dir"
    return 1
  fi
  if ! "$openssl_bin" pkeyutl -sign -inkey "$private_key" -rawin -in "$pae_file" -out "$sig_file" >/dev/null 2>&1; then
    rm -r "$tmp_dir"
    return 1
  fi
  cat "$payload_file" "$sig_file" > "$body_file"
  token_body="$(_walter_cap_b64url_encode_file "$body_file")"
  token_footer="$(_walter_cap_b64url_encode_file "$footer_file")"
  rm -r "$tmp_dir"
  printf 'v4.public.%s.%s' "$token_body" "$token_footer"
}

walter_cap_verify_token() {
  local state_file="$1" token="$2"
  local prefix purpose body footer extra session_id public_key tmp_dir body_file payload_file footer_file sig_file pae_file openssl_bin exp exp_epoch now_epoch session_end
  _walter_cap_require_runtime || return 1
  _walter_cap_validate_state "$state_file" || return 1
  _walter_cap_validate_active_session "$state_file" || return 1
  if ! openssl_bin="$(_walter_session_openssl)"; then
    echo "walter-cap: ED25519-capable openssl missing" >&2
    return 1
  fi

  IFS='.' read -r prefix purpose body footer extra <<< "$token"
  if [[ "$prefix" != "v4" || "$purpose" != "public" || -z "$body" || -z "$footer" || -n "${extra:-}" ]]; then
    echo "walter-cap: invalid token shape" >&2
    return 1
  fi

  session_id="$(_walter_cap_state_field "$state_file" session_id)"
  public_key="$(_walter_cap_state_field "$state_file" capability_public_key_path)"
  [[ -f "$public_key" ]] || {
    echo "walter-cap: session public key missing" >&2
    return 1
  }

  tmp_dir="$(mktemp -d)"
  body_file="$tmp_dir/body.bin"
  payload_file="$tmp_dir/payload.json"
  footer_file="$tmp_dir/footer.json"
  sig_file="$tmp_dir/sig.bin"
  pae_file="$tmp_dir/pae.bin"

  if ! _walter_cap_b64url_decode_to_file "$body" "$body_file" || ! _walter_cap_b64url_decode_to_file "$footer" "$footer_file"; then
    rm -r "$tmp_dir"
    return 1
  fi
  if ! _walter_cap_split_body_to_files "$body_file" "$payload_file" "$sig_file"; then
    rm -r "$tmp_dir"
    return 1
  fi
  if ! jq -e --arg sid "$session_id" '.kid == $sid and .alg == "Ed25519"' "$footer_file" >/dev/null; then
    echo "walter-cap: footer does not match active session" >&2
    rm -r "$tmp_dir"
    return 1
  fi
  if ! jq -e --arg sid "$session_id" '.session_id == $sid and .iss == "walter-os"' "$payload_file" >/dev/null; then
    echo "walter-cap: claims do not match active session" >&2
    rm -r "$tmp_dir"
    return 1
  fi
  if ! _walter_cap_pae_to_file "$payload_file" "$footer_file" "$pae_file"; then
    rm -r "$tmp_dir"
    return 1
  fi
  if ! "$openssl_bin" pkeyutl -verify -pubin -inkey "$public_key" -rawin -in "$pae_file" -sigfile "$sig_file" >/dev/null 2>&1; then
    echo "walter-cap: signature verification failed" >&2
    rm -r "$tmp_dir"
    return 1
  fi

  exp="$(jq -r '.exp // empty' "$payload_file")"
  if [[ -z "$exp" ]] || ! exp_epoch="$(_walter_session_epoch "$exp")" || [[ ! "$exp_epoch" =~ ^[0-9]+$ ]]; then
    echo "walter-cap: invalid exp claim" >&2
    rm -r "$tmp_dir"
    return 1
  fi
  session_end="$(_walter_cap_session_end_epoch "$state_file")" || {
    echo "walter-cap: cannot derive session end" >&2
    rm -r "$tmp_dir"
    return 1
  }
  if (( exp_epoch > session_end )); then
    echo "walter-cap: token exp exceeds session end" >&2
    rm -r "$tmp_dir"
    return 1
  fi
  now_epoch="$(_walter_session_now_epoch)"
  if (( now_epoch >= exp_epoch )); then
    echo "walter-cap: token expired" >&2
    rm -r "$tmp_dir"
    return 1
  fi

  jq -cS . "$payload_file"
  rm -r "$tmp_dir"
}
