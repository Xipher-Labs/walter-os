#!/usr/bin/env bats
# tests/walter/audit-chain-verify.bats
#
# OSS Trust B-1 audit-chain verifier coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-verify.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-05-31"
  export WALTER_AUDIT_NOW="2026-05-31T12:00:00Z"
  export WALTER_SESSION_ID="session-test"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
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

@test "B-1: clean chain verifies through library" {
  _make_chain

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
}

@test "B-1: tampered prev_hash fails with row number" {
  _make_chain
  jq -cS '.prev_hash = "deadbeef"' "$(_chain_path)" > "$(_chain_path).tmp"
  mv "$(_chain_path).tmp" "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 1: prev_hash mismatch"* ]]
}

@test "B-1: tampered first row breaks second-row chain" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered"')"
  second="$(sed -n '2p' "$(_chain_path)")"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 2: prev_hash mismatch"* ]]
}

@test "B-1: tampered final row breaks root hash" {
  _make_chain
  first="$(sed -n '1p' "$(_chain_path)")"
  second="$(sed -n '2p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered tail"')"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31"

  [ "$status" -eq 1 ]
  [[ "$output" == *"root hash mismatch"* ]]
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
  second="$(sed -n '2p' "$(_chain_path)" | jq -cS '.decision_reason = "tampered tail"')"
  printf '%s\n%s\n' "$first" "$second" > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after tail tamper' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [[ "$output" == *"root hash mismatch"* ]]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "2" ]
  [ "$(cat "$(_root_path)")" != "$(_sha256 "$second")" ]
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
