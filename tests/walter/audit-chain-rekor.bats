#!/usr/bin/env bats
# tests/walter/audit-chain-rekor.bats
#
# OSS Trust B-4 optional Rekor anchoring coverage.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  command -v python3 >/dev/null 2>&1 || skip "python3 required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-rekor.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-05-31"
  export WALTER_AUDIT_NOW="2026-05-31T12:00:00Z"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  export WALTER_OS_HOME="$REPO_ROOT"
  export USER="walter-rekor-test-user"
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
    "$REPO_ROOT"/.tmp-audit-rekor.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-05-31.jsonl\n' "$WALTER_CONFIG"
}

_root_path() {
  printf '%s/audit/root-2026-05-31.txt\n' "$WALTER_CONFIG"
}

_rekor_path() {
  printf '%s/audit/root-2026-05-31.rekor.json\n' "$WALTER_CONFIG"
}

_curl_args_path() {
  printf '%s/curl-args.txt\n' "$TMP_HOME"
}

_curl_body_path() {
  printf '%s/curl-body.json\n' "$TMP_HOME"
}

_make_chain() {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  WALTER_AUDIT_NOW="2026-05-31T12:00:01Z" \
    bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'rm -rf /tmp/nope' block bash-denylist destructive >/dev/null"
}

_write_failing_curl() {
  mkdir -p "$TMP_HOME/bin"
  cat > "$TMP_HOME/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl invoked\n' > "${WALTER_TEST_REKOR_CURL_MARKER:?}"
exit 97
SH
  chmod +x "$TMP_HOME/bin/curl"
}

_write_mock_curl() {
  mkdir -p "$TMP_HOME/bin"
  cat > "$TMP_HOME/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" > "${WALTER_TEST_REKOR_CURL_ARGS:?}"

method="GET"
output=""
write_out=""
data_file=""
url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      write_out="$2"
      shift 2
      ;;
    --data-binary)
      data_file="${2#@}"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[[ "$write_out" == "%{http_code}" ]] || exit 98
[[ -n "$output" ]] || exit 96

case "${WALTER_TEST_REKOR_MODE:-success}" in
  success)
    if [[ "$method" == "POST" ]]; then
      cp "$data_file" "${WALTER_TEST_REKOR_CURL_BODY:?}"
      python3 - "$data_file" "$output" <<'PY'
import base64
import json
import pathlib
import sys

body = pathlib.Path(sys.argv[1]).read_bytes()
response = {
    "abc123": {
        "body": base64.b64encode(body).decode("ascii"),
        "integratedTime": 1780272000,
        "logIndex": 7,
        "logID": "test-log",
        "verification": {"signedEntryTimestamp": "set"},
    }
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(response), encoding="utf-8")
PY
      printf '201'
    elif [[ "$method" == "GET" && "$url" == */api/v1/log/entries/abc123 ]]; then
      python3 - "${WALTER_TEST_REKOR_CURL_BODY:?}" "$output" <<'PY'
import base64
import json
import pathlib
import sys

body = pathlib.Path(sys.argv[1]).read_bytes()
response = {
    "abc123": {
        "body": base64.b64encode(body).decode("ascii"),
        "integratedTime": 1780272000,
        "logIndex": 7,
        "logID": "test-log",
        "verification": {"signedEntryTimestamp": "set"},
    }
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(response), encoding="utf-8")
PY
      printf '200'
    else
      printf '{"error":"unexpected method or url"}\n' > "$output"
      printf '404'
    fi
    ;;
  auth)
    printf '{"error":"unauthorized"}\n' > "$output"
    printf '401'
    ;;
  *)
    printf '{"error":"unexpected mock mode"}\n' > "$output"
    printf '500'
    ;;
esac
SH
  chmod +x "$TMP_HOME/bin/curl"
}

@test "close-day does not contact Rekor by default" {
  _make_chain
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    bash "$WALTER_OS_BIN" audit close-day 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: closed audit day 2026-05-31"* ]]
  [ -f "$(_root_path)" ]
  [ ! -f "$(_rekor_path)" ]
  [ ! -f "$TMP_HOME/curl-called" ]
}

@test "close-day uploads one opt-in Rekor entry and stores receipt" {
  _make_chain
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: anchored audit root in Rekor"* ]]
  [ -f "$(_rekor_path)" ]
  jq -e --arg root "$(cat "$(_root_path)")" \
    '.entry_id == "abc123" and .payload.root == $root and .payload.date == "2026-05-31"' \
    "$(_rekor_path)"
  jq -e '.payload.operator | test("^[0-9a-f]{64}$")' "$(_rekor_path)"
  if grep -q 'walter-rekor-test-user' "$(_rekor_path)"; then
    return 1
  fi
  if grep -q 'walter-rekor-test-user' "$(_curl_body_path)"; then
    return 1
  fi
  grep -q 'http://rekor.example/api/v1/log/entries' "$(_curl_args_path)"
  jq -e '.kind == "hashedrekord" and .apiVersion == "0.0.1"' "$(_curl_body_path)"
}

@test "verify-chain --check-rekor confirms the stored root against Rekor" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
  [[ "$output" == *"ok: verified Rekor anchor abc123"* ]]
  grep -q 'http://rekor.example/api/v1/log/entries/abc123' "$(_curl_args_path)"
}

@test "verify-chain --check-rekor fails when the receipt root differs" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq '.payload.root = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  mv "$TMP_HOME/receipt.json" "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor receipt root mismatch"* ]]
}

@test "close-day holds the audit lock while anchoring the Rekor root" {
  _make_chain
  _write_mock_curl
  race_status="$TMP_HOME/race-status"
  probe_script="$TMP_HOME/rekor-race-probe.sh"
  cat > "$probe_script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$AUDIT_LIB"
eval "$(declare -f walter_audit_rekor_upload | sed '1s/walter_audit_rekor_upload/_original_walter_audit_rekor_upload/')"
walter_audit_rekor_upload() {
  set +e
  WALTER_AUDIT_NOW="2026-05-31T12:00:02Z" WALTER_AUDIT_LOCK_WAIT_SECONDS=0 \
    bash -c "source \"$AUDIT_LIB\"; walter_audit_append Bash 'racing append' allow approval-gate ok" >/dev/null 2>&1
  child_status="$?"
  set -e
  printf '%s' "$child_status" > "$RACE_STATUS"
  _original_walter_audit_rekor_upload "$@"
}
walter_audit_close_day --rekor-url "http://rekor.example" 2026-05-31
SH
  chmod +x "$probe_script"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    AUDIT_LIB="$AUDIT_LIB" \
    RACE_STATUS="$race_status" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$probe_script"

  [ "$status" -eq 0 ]
  [ -f "$race_status" ]
  [ "$(cat "$race_status")" != "0" ]

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified Rekor anchor abc123"* ]]
}

@test "close-day rejects invalid Rekor URLs before network access" {
  _make_chain
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "rekor.example" 2026-05-31

  [ "$status" -eq 2 ]
  [[ "$output" == *"Rekor URL"* ]]
  [ ! -f "$TMP_HOME/curl-called" ]
}
