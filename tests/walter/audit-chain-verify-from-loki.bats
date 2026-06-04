#!/usr/bin/env bats
# tests/walter/audit-chain-verify-from-loki.bats
#
# OSS Trust B-3 audit telemetry verifier coverage.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-loki.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-06-04"
  export WALTER_AUDIT_NOW="2026-06-04T12:00:00Z"
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
    "$REPO_ROOT"/.tmp-audit-loki.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-06-04.jsonl\n' "$WALTER_CONFIG"
}

_fixture_path() {
  printf '%s/loki-response.json\n' "$TMP_HOME"
}

_curl_args_path() {
  printf '%s/curl-args.txt\n' "$TMP_HOME"
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

_write_mock_curl() {
  mkdir -p "$TMP_HOME/bin"
  cat > "$TMP_HOME/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" > "${WALTER_TEST_CURL_ARGS:?}"

output=""
write_out=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      write_out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "${WALTER_TEST_CURL_MODE:-success}" in
  success)
    cp "${WALTER_TEST_LOKI_FIXTURE:?}" "$output"
    printf '200'
    ;;
  auth)
    printf '{"status":"error","error":"unauthorized"}\n' > "$output"
    printf '401'
    ;;
  malformed)
    printf '{bad-json\n' > "$output"
    printf '200'
    ;;
  unreachable)
    printf 'curl: (7) Failed to connect to loki.example port 3100\n' >&2
    exit 7
    ;;
  *)
    printf 'unexpected mock mode\n' >&2
    exit 99
    ;;
esac

[[ "$write_out" == "%{http_code}" ]] || exit 98
SH
  chmod +x "$TMP_HOME/bin/curl"
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

@test "verify-chain --from-loki rejects path-traversal dates" {
  _make_chain
  _make_loki_fixture

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" "../../bad"

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid Loki date"* ]]
}

@test "verify-chain --from-loki requires a live Loki URL when no fixture is provided" {
  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 2 ]
  [[ "$output" == *"WALTER_AUDIT_LOKI_URL"* ]]
  [[ "$output" == *"--loki-url"* ]]
}

@test "verify-chain --from-loki queries live Loki without leaking the token" {
  _make_chain
  _make_loki_fixture
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_LOKI_FIXTURE="$(_fixture_path)" \
    WALTER_AUDIT_LOKI_URL="http://loki.example:3100" \
    WALTER_AUDIT_LOKI_TOKEN="super-secret-token" \
    bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
  [[ "$output" == *"from live Loki"* ]]
  [[ "$output" != *"super-secret-token"* ]]
  grep -q '/loki/api/v1/query_range' "$(_curl_args_path)"
  grep -q '{app="walter-os", kind="audit-chain"}' "$(_curl_args_path)"
  grep -q 'start=1780531200000000000' "$(_curl_args_path)"
  grep -q 'end=1780617599999999999' "$(_curl_args_path)"
  grep -q 'Authorization: Bearer super-secret-token' "$(_curl_args_path)"
}

@test "verify-chain --from-loki computes live range bounds without python3" {
  mkdir -p "$TMP_HOME/bin"
  cat > "$TMP_HOME/bin/python3" <<'SH'
#!/usr/bin/env bash
exit 127
SH
  chmod +x "$TMP_HOME/bin/python3"

  run env PATH="$TMP_HOME/bin:$PATH" "$BASH" -c "source '$AUDIT_LIB'; _walter_audit_loki_range_ns 2026-06-04"

  [ "$status" -eq 0 ]
  [ "$output" = $'1780531200000000000\n1780617599999999999' ]
}

@test "verify-chain --from-loki accepts an explicit Loki URL" {
  _make_chain
  _make_loki_fixture
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_LOKI_FIXTURE="$(_fixture_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --from-loki --loki-url "http://loki.example:3100" 2026-06-04

  [ "$status" -eq 0 ]
  [[ "$output" == *"from live Loki"* ]]
  grep -q 'http://loki.example:3100/loki/api/v1/query_range' "$(_curl_args_path)"
}

@test "verify-chain --from-loki rejects invalid explicit Loki URLs" {
  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --loki-url "loki.example:3100" 2026-06-04

  [ "$status" -eq 2 ]
  [[ "$output" == *"WALTER_AUDIT_LOKI_URL"* ]]
  [[ "$output" == *"--loki-url"* ]]
  [[ "$output" == *"must start with http:// or https://"* ]]
}

@test "verify-chain --from-loki rejects fixture and live URL together" {
  _make_chain
  _make_loki_fixture

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" --loki-url "http://loki.example:3100" 2026-06-04

  [ "$status" -eq 2 ]
  [[ "$output" == *"choose either --mock-loki or --loki-url"* ]]
}

@test "live Loki verification reports missing curl explicitly" {
  mkdir -p "$TMP_HOME/no-curl-bin"

  run env \
    PATH="$TMP_HOME/no-curl-bin" \
    WALTER_AUDIT_LOKI_URL="http://loki.example:3100" \
    "$BASH" -c "source '$AUDIT_LIB'; walter_audit_verify_chain_from_loki_live 2026-06-04"

  [ "$status" -eq 3 ]
  [[ "$output" == *"curl required for live Loki verification"* ]]
}

@test "verify-chain --from-loki reports live Loki authentication failures" {
  _make_chain
  _make_loki_fixture
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_CURL_MODE="auth" \
    WALTER_TEST_LOKI_FIXTURE="$(_fixture_path)" \
    WALTER_AUDIT_LOKI_URL="http://loki.example:3100" \
    WALTER_AUDIT_LOKI_TOKEN="super-secret-token" \
    bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"Loki authentication failed"* ]]
  [[ "$output" == *"HTTP 401"* ]]
  [[ "$output" != *"super-secret-token"* ]]
}

@test "verify-chain --from-loki reports unreachable live Loki endpoints" {
  _make_chain
  _make_loki_fixture
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_CURL_MODE="unreachable" \
    WALTER_TEST_LOKI_FIXTURE="$(_fixture_path)" \
    WALTER_AUDIT_LOKI_URL="http://loki.example:3100" \
    bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"unable to query Loki"* ]]
  [[ "$output" == *"curl exit 7"* ]]
  [[ "$output" == *"curl stderr: curl: (7) Failed to connect to loki.example port 3100"* ]]
}

@test "verify-chain --from-loki rejects malformed live Loki responses" {
  _make_chain
  _make_loki_fixture
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_CURL_MODE="malformed" \
    WALTER_TEST_LOKI_FIXTURE="$(_fixture_path)" \
    WALTER_AUDIT_LOKI_URL="http://loki.example:3100" \
    bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid Loki response JSON"* ]]
}
