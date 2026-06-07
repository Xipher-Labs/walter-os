#!/usr/bin/env bats
# tests/walter/audit-chain-verify.bats
#
# OSS Trust B-1 audit-chain verifier coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-verify.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-05-31"
  export WALTER_AUDIT_NOW="2026-05-31T12:00:00Z"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_ROOT'" >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_ROOT'")"
  export WALTER_SESSION_ID="$(jq -r '.session_id' "$state_file")"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-audit-verify.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-05-31.jsonl\n' "$WALTER_CONFIG"
}

_root_path() {
  printf '%s/audit/root-2026-05-31.txt\n' "$WALTER_CONFIG"
}

_state_file() {
  bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_ROOT'"
}

_public_key_path() {
  jq -r '.capability_public_key_path' "$(_state_file)"
}

_private_key_path() {
  jq -r '.capability_private_key_path' "$(_state_file)"
}

_make_chain() {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  WALTER_AUDIT_NOW="2026-05-31T12:00:01Z" \
    bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'rm -rf /tmp/nope' block bash-denylist destructive >/dev/null"
}

_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

_rehash_row() {
  local row="$1" without_hash row_hash
  without_hash="$(printf '%s' "$row" | jq -cS 'del(.row_hash, .sig)')"
  row_hash="$(_sha256 "$without_hash")"
  _resign_row "$(printf '%s' "$without_hash" | jq -cS --arg row_hash "$row_hash" '. + {row_hash:$row_hash}')"
}

_base64_file() {
  python3 - "$1" <<'PY'
import base64
import pathlib
import sys
print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"), end="")
PY
}

_sign_payload() {
  local payload="$1" tmp_dir payload_file sig_file
  tmp_dir="$(mktemp -d "$TMP_HOME/sign.XXXXXX")"
  payload_file="$tmp_dir/payload.json"
  sig_file="$tmp_dir/sig.bin"
  printf '%s' "$payload" > "$payload_file"
  "$(bash -c "source '$SESSION_LIB'; _walter_session_openssl")" \
    pkeyutl -sign -inkey "$(_private_key_path)" -rawin -in "$payload_file" -out "$sig_file" >/dev/null 2>&1
  _base64_file "$sig_file"
  rm -rf "$tmp_dir"
}

_resign_row() {
  local row="$1" payload sig
  payload="$(printf '%s' "$row" | jq -cS 'del(.sig)')"
  sig="$(_sign_payload "$payload")"
  printf '%s' "$payload" | jq -cS --arg sig "$sig" '. + {sig:$sig}'
}

@test "B-1: clean chain verifies through library" {
  _make_chain

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
}

@test "B-2: appended rows include padded base64 Ed25519 signatures" {
  _make_chain

  run jq -r '.sig' "$(_chain_path)"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
  while IFS= read -r sig; do
    [[ "$sig" =~ ^[A-Za-z0-9+/]{86}==$ ]]
  done <<< "$output"
}

@test "B-1: tampered prev_hash fails with row number" {
  _make_chain
  first="$(_rehash_row "$(sed -n '1p' "$(_chain_path)" | jq -cS '.prev_hash = "deadbeef"')")"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 1: prev_hash mismatch"* ]]
}

@test "B-1: tampered first row breaks second-row chain" {
  _make_chain
  first="$(_rehash_row "$(sed -n '1p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered"')")"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 2: prev_hash mismatch"* ]]
}

@test "B-1: tampered final row breaks root hash" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)")"
  second="$(_rehash_row "$(sed -n '2p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered tail"')")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"root hash mismatch"* ]]
}

@test "B-1: tampered final row fails even if root is rewritten" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)")"
  second="$(sed -n '2p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered tail"')"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"
  _sha256 "$second" > "$(_root_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 2: row_hash mismatch"* ]]
}

@test "B-2: tampered signature fails with row number" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)")"
  sig="$(printf '%s' "$first" | jq -r '.sig')"
  replacement="A"
  [[ "${sig:0:1}" == "A" ]] && replacement="B"
  tampered="$(printf '%s' "$first" | jq -cS --arg sig "${replacement}${sig:1}" '.sig = $sig')"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$tampered" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 1: signature verification failed"* ]]
}

@test "B-2: malformed signature reports invalid format" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)" | jq -cS '.sig = "not-base64"')"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 1: invalid sig format"* ]]
}

@test "B-2: unsigned legacy rows report rotation guidance" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)" | jq -cS 'del(.sig)')"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 1: missing sig"* ]]
  [[ "$output" == *"legacy unsigned audit chain"* ]]
  [[ "$output" == *"rotate"* ]]
}

@test "B-2: missing public key fails with row number" {
  _make_chain
  rm -f "$(_public_key_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 2 ]
  [[ "$output" == *"row 1: cannot verify session"* ]]
}

@test "B-2: verifier can use archived public keys" {
  _make_chain
  archive_dir="$(dirname "$(_public_key_path)")/keys-archive"
  mkdir -p "$archive_dir"
  mv "$(_public_key_path)" "$archive_dir/session-${WALTER_SESSION_ID}.pub"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
}

@test "B-2: verifier caches ED25519-capable openssl probe" {
  _make_chain
  openssl_bin="$(bash -c "source '$SESSION_LIB'; _walter_session_openssl")"
  counter="$TMP_HOME/openssl-probe-count"

  run bash -c "
    source '$AUDIT_LIB'
    counter='$counter'
    _walter_session_openssl() {
      current=0
      [[ -f \"\$counter\" ]] && current=\"\$(cat \"\$counter\")\"
      printf '%s' \"\$((current + 1))\" > \"\$counter\"
      printf '%s' '$openssl_bin'
    }
    walter_audit_verify_chain 2026-05-31 >/dev/null
    printf 'resolver_count=%s' \"\$(cat \"\$counter\")\"
  "

  [ "$status" -eq 0 ]
  [ "$output" = "resolver_count=1" ]
}

@test "B-2: verifier reuses one signature temp directory per chain" {
  _make_chain
  real_mktemp="$(command -v mktemp)"
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/mktemp" <<SH
#!/usr/bin/env bash
if [[ "\${1:-}" == "-d" ]]; then
  current=0
  [[ -f "$TMP_HOME/mktemp-d-count" ]] && current="\$(cat "$TMP_HOME/mktemp-d-count")"
  printf '%s' "\$((current + 1))" > "$TMP_HOME/mktemp-d-count"
fi
exec "$real_mktemp" "\$@"
SH
  chmod +x "$TMP_HOME/mock-bin/mktemp"

  run env PATH="$TMP_HOME/mock-bin:$PATH" bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 0 ]
  [ "$(cat "$TMP_HOME/mktemp-d-count")" = "1" ]
}

@test "B-2: verifier fails closed when temp directory creation fails" {
  _make_chain
  mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
  cat > "$BATS_TEST_TMPDIR/mock-bin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/mktemp"

  run bash -c "source '$AUDIT_LIB'; PATH='$BATS_TEST_TMPDIR/mock-bin':\$PATH walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"temporary directory unavailable"* ]]
}

@test "B-2: verifier reports missing python3 runtime clearly" {
  _make_chain
  mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
  cat > "$BATS_TEST_TMPDIR/mock-bin/python3" <<'SH'
#!/usr/bin/env bash
exit 127
SH
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/python3"

  run bash -c "source '$AUDIT_LIB'; PATH='$BATS_TEST_TMPDIR/mock-bin':\$PATH walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 3 ]
  [[ "$output" == *"required tool missing: python3"* ]]
}

@test "B-1: append rejects tampered final row even if root is rewritten" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)")"
  second="$(sed -n '2p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered tail"')"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"
  _sha256 "$second" > "$(_root_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after tail tamper' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 2: row_hash mismatch"* ]]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "2" ]
}

@test "B-1: invalid JSON fails with row number" {
  _make_chain
  printf '{bad-json\n' >> "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 3: invalid JSON object"* ]]
}

@test "B-1: non-canonical JSON fails with row number" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)" | jq -c '{ts:.ts,tool:.tool,event:.event,prev_hash:.prev_hash,decision:.decision,operator:.operator,session_id:.session_id,input_summary:.input_summary,decision_source:.decision_source,decision_reason:.decision_reason}')"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 1: non-canonical JSON"* ]]
}

@test "B-1: append rejects existing tampered chain before adding row" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered"')"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after tamper' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "2" ]
}

@test "B-1: append rejects tampered final row before adding row" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)")"
  second="$(_rehash_row "$(sed -n '2p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered tail"')")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after tail tamper' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [[ "$output" == *"root hash mismatch"* ]]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "2" ]
  [ "$(cat "$(_root_path)")" != "$(_sha256 "$second")" ]
}

@test "B-1: verifier releases lock on failure under set -e" {
  _make_chain
  printf '%s' "deadbeef" > "$(_root_path)"

  run bash -c "set -e; source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"root hash mismatch"* ]]
  [ ! -d "$WALTER_CONFIG/audit/.chain.lock" ]
}

@test "B-1: unterminated final row fails verification" {
  _make_chain
  content="$(cat "$(_chain_path)")"
  printf '%s' "$content" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unterminated final row"* ]]
}

@test "B-1: append rejects unterminated chain before adding row" {
  _make_chain
  content="$(cat "$(_chain_path)")"
  printf '%s' "$content" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after unterminated' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
}

@test "B-1: append rejects unterminated chain without jq" {
  _make_chain
  content="$(cat "$(_chain_path)")"
  printf '%s' "$content" > "$(_chain_path)"
  mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
  cat > "$BATS_TEST_TMPDIR/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/jq"

  run bash -c "source '$AUDIT_LIB'; PATH='$BATS_TEST_TMPDIR/mock-bin:/usr/bin:/bin' walter_audit_append Bash 'after unterminated' block approval-gate 'jq missing'"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unterminated final row"* ]]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
}

@test "B-1: verifier fails closed on non-empty chain when jq cannot run" {
  _make_chain
  mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
  cat > "$BATS_TEST_TMPDIR/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/jq"

  run bash -c "source '$AUDIT_LIB'; PATH='$BATS_TEST_TMPDIR/mock-bin:/usr/bin:/bin' walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 3 ]
  [[ "$output" == *"jq required"* ]]
}

@test "B-1: missing chain returns non-zero" {
  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain not found"* ]]
}

@test "B-1: empty chain returns non-zero" {
  mkdir -p "$(dirname "$(_chain_path)")"
  : > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"empty chain"* ]]
}

@test "B-1: walter-os audit verify-chain dispatches to verifier" {
  _make_chain

  run bash "$WALTER_OS_BIN" audit verify-chain 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
}
