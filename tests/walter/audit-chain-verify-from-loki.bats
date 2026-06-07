#!/usr/bin/env bats
# tests/walter/audit-chain-verify-from-loki.bats
#
# OSS Trust B-3 audit telemetry verifier coverage.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-loki.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-06-04"
  export WALTER_AUDIT_NOW="2026-06-04T12:00:00Z"
  export WALTER_SESSION_ID="session-loki"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-audit-loki.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-06-04.jsonl\n' "$WALTER_CONFIG"
}

_fixture_path() {
  printf '%s/loki-response.json\n' "$TMP_HOME"
}

_make_chain() {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  WALTER_AUDIT_NOW="2026-06-04T12:00:01Z" \
    bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'rm -rf /tmp/nope' block bash-denylist destructive >/dev/null"
}

_make_loki_fixture() {
  jq -Rs 'split("\n") | map(select(length > 0)) | to_entries | {
    status: "success",
    data: {
      resultType: "streams",
      result: [
        {
          stream: {app: "walter-os", kind: "audit-chain"},
          values: (map([((1000000000 + .key) | tostring), .value]))
        }
      ]
    }
  }' "$(_chain_path)" > "$(_fixture_path)"
}

@test "verify-chain --from-loki verifies a Loki query_range fixture" {
  _make_chain
  _make_loki_fixture

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" 2026-06-04

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
  [[ "$output" == *"from Loki fixture"* ]]
}

@test "verify-chain --from-loki detects tampered fixture rows" {
  _make_chain
  _make_loki_fixture
  jq '.data.result[0].values[1][1] |= sub("destructive"; "tampered")' \
    "$(_fixture_path)" > "$TMP_HOME/tampered.json" && mv "$TMP_HOME/tampered.json" "$(_fixture_path)"

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 2: row_hash mismatch"* ]]
}

@test "verify-chain --from-loki rejects malformed Loki fixtures" {
  printf '{"status":"success","data":{"result":[]}}\n' > "$(_fixture_path)"

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"no audit-chain rows found"* ]]
}

@test "verify-chain --from-loki requires mock fixture until live Loki is implemented" {
  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 2 ]
  [[ "$output" == *"--mock-loki <fixture>"* ]]
}
