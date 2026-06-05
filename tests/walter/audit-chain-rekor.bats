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

_chain_path_for() {
  printf '%s/audit/chain-%s.jsonl\n' "$WALTER_CONFIG" "$1"
}

_root_path_for() {
  printf '%s/audit/root-%s.txt\n' "$WALTER_CONFIG" "$1"
}

_rekor_path_for() {
  printf '%s/audit/root-%s.rekor.json\n' "$WALTER_CONFIG" "$1"
}

_curl_args_path() {
  printf '%s/curl-args.txt\n' "$TMP_HOME"
}

_curl_body_path() {
  printf '%s/curl-body.json\n' "$TMP_HOME"
}

_decode_base64_to_file() {
  python3 - "$1" "$2" <<'PY'
import base64
import pathlib
import sys

pathlib.Path(sys.argv[2]).write_bytes(base64.b64decode(sys.argv[1], validate=True))
PY
}

_hex_to_file() {
  python3 - "$1" "$2" <<'PY'
import pathlib
import sys

pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(sys.argv[1]))
PY
}

_base64_file() {
  python3 - "$1" <<'PY'
import base64
import pathlib
import sys

print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"), end="")
PY
}

_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

_openssl_bin() {
  bash -c "source '$SESSION_LIB'; _walter_session_openssl"
}

_path_without_jq() {
  local bin="$TMP_HOME/no-jq-bin" tool tool_path
  mkdir -p "$bin"
  for tool in awk cat chmod cp curl date grep mktemp mv python3 rm sed shasum tail tr; do
    tool_path="$(command -v "$tool" 2>/dev/null || true)"
    [[ -n "$tool_path" ]] || continue
    ln -sf "$tool_path" "$bin/$tool"
  done
  printf '%s' "$bin"
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
headers=""
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
    -D)
      headers="$2"
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
      [[ -z "$headers" ]] || printf 'HTTP/1.1 201 Created\r\n\r\n' > "$headers"
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
      [[ -z "$headers" ]] || printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
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
  wrong-payload)
    if [[ "$method" == "POST" ]]; then
      cp "$data_file" "${WALTER_TEST_REKOR_CURL_BODY:?}"
      [[ -z "$headers" ]] || printf 'HTTP/1.1 201 Created\r\n\r\n' > "$headers"
      python3 - "$data_file" "$output" <<'PY'
import base64
import json
import pathlib
import sys

body = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
body["spec"]["data"]["hash"]["value"] = "0" * 64
encoded = json.dumps(body).encode("utf-8")
response = {
    "abc123": {
        "body": base64.b64encode(encoded).decode("ascii"),
        "integratedTime": 1780272000,
        "logIndex": 7,
        "logID": "test-log",
        "verification": {"signedEntryTimestamp": "set"},
    }
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(response), encoding="utf-8")
PY
      printf '201'
    else
      printf '{"error":"unexpected wrong-payload method or url"}\n' > "$output"
      printf '404'
    fi
    ;;
  duplicate)
    if [[ "$method" == "POST" ]]; then
      cp "$data_file" "${WALTER_TEST_REKOR_CURL_BODY:?}"
      [[ -z "$headers" ]] || printf 'HTTP/1.1 409 Conflict\r\nLocation: http://rekor.example/api/v1/log/entries/abc123\r\n\r\n' > "$headers"
      printf '{"code":409,"message":"entry already exists"}\n' > "$output"
      printf '409'
    elif [[ "$method" == "GET" && "$url" == */api/v1/log/entries/abc123 ]]; then
      [[ -z "$headers" ]] || printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
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
      printf '{"error":"unexpected duplicate method or url"}\n' > "$output"
      printf '404'
    fi
    ;;
  duplicate-message)
    if [[ "$method" == "POST" ]]; then
      cp "$data_file" "${WALTER_TEST_REKOR_CURL_BODY:?}"
      [[ -z "$headers" ]] || printf 'HTTP/1.1 409 Conflict\r\n\r\n' > "$headers"
      printf '{"code":409,"message":"entry already exists: abc123"}\n' > "$output"
      printf '409'
    elif [[ "$method" == "GET" && "$url" == */api/v1/log/entries/abc123 ]]; then
      [[ -z "$headers" ]] || printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
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
      printf '{"error":"unexpected duplicate-message method or url"}\n' > "$output"
      printf '404'
    fi
    ;;
  duplicate-wrong-payload)
    if [[ "$method" == "POST" ]]; then
      cp "$data_file" "${WALTER_TEST_REKOR_CURL_BODY:?}"
      [[ -z "$headers" ]] || printf 'HTTP/1.1 409 Conflict\r\nLocation: http://rekor.example/api/v1/log/entries/abc123\r\n\r\n' > "$headers"
      printf '{"code":409,"message":"entry already exists"}\n' > "$output"
      printf '409'
    elif [[ "$method" == "GET" && "$url" == */api/v1/log/entries/abc123 ]]; then
      [[ -z "$headers" ]] || printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
      python3 - "${WALTER_TEST_REKOR_CURL_BODY:?}" "$output" <<'PY'
import base64
import json
import pathlib
import sys

body = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
body["spec"]["data"]["hash"]["value"] = "0" * 64
encoded = json.dumps(body).encode("utf-8")
response = {
    "abc123": {
        "body": base64.b64encode(encoded).decode("ascii"),
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
      printf '{"error":"unexpected duplicate wrong-payload method or url"}\n' > "$output"
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

@test "close-day rejects --rekor-url when Rekor upload is disabled" {
  _make_chain
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 2 ]
  [[ "$output" == *"--rekor-url requires WALTER_AUDIT_REKOR_UPLOAD=1"* ]]
  [ ! -f "$TMP_HOME/curl-called" ]
}

@test "close-day rejects Rekor anchoring for the current UTC audit date" {
  today="$(date -u +%Y-%m-%d)"
  WALTER_AUDIT_DATE="$today" \
    WALTER_AUDIT_NOW="${today}T12:00:00Z" \
    bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" "$today"

  [ "$status" -eq 2 ]
  [[ "$output" == *"Rekor anchoring requires a past UTC audit date"* ]]
  [ ! -f "$(_rekor_path_for "$today")" ]
  [ ! -f "$TMP_HOME/curl-called" ]
}

@test "direct Rekor upload reports missing jq explicitly" {
  _make_chain
  bash "$WALTER_OS_BIN" audit close-day 2026-05-31 >/dev/null
  root_hash="$(cat "$(_root_path)")"

  run env PATH="$(_path_without_jq)" /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_rekor_upload '2026-05-31' '$root_hash' '$(_chain_path)' 'http://rekor.example'"

  [ "$status" -eq 3 ]
  [[ "$output" == *"jq required"* ]]
}

@test "direct Rekor verification reports missing jq explicitly" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  root_hash="$(cat "$(_root_path)")"

  run env PATH="$(_path_without_jq)" /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_verify_rekor_anchor '2026-05-31' '$root_hash' 'http://rekor.example'"

  [ "$status" -eq 3 ]
  [[ "$output" == *"jq required"* ]]
}

@test "direct Rekor upload rejects invalid date and root arguments" {
  run /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_rekor_upload '2026/05/31' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' '$(_chain_path)' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid date"* ]]

  run /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_rekor_upload '2026-05-31' 'not-a-root' '$(_chain_path)' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid root hash"* ]]

  run /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_rekor_upload '2026-05-31' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' '$TMP_HOME/missing-chain.jsonl' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"chain not found"* ]]
}

@test "direct Rekor upload rejects the current UTC audit date before network access" {
  today="$(date -u +%Y-%m-%d)"
  WALTER_AUDIT_DATE="$today" \
    WALTER_AUDIT_NOW="${today}T12:00:00Z" \
    bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  root_hash="$(cat "$(_root_path_for "$today")")"
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    /bin/bash -c "source '$AUDIT_LIB'; walter_audit_rekor_upload '$today' '$root_hash' '$(_chain_path_for "$today")' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"Rekor anchoring requires a past UTC audit date"* ]]
  [ ! -f "$TMP_HOME/curl-called" ]
}

@test "direct Rekor upload rejects a root not matching the chain before network access" {
  _make_chain
  bash "$WALTER_OS_BIN" audit close-day 2026-05-31 >/dev/null
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    /bin/bash -c "source '$AUDIT_LIB'; walter_audit_rekor_upload '2026-05-31' '0000000000000000000000000000000000000000000000000000000000000000' '$(_chain_path)' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"Rekor root does not match final chain row"* ]]
  [ ! -f "$TMP_HOME/curl-called" ]
}

@test "direct Rekor verification rejects invalid date and root arguments" {
  run /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_verify_rekor_anchor '2026/05/31' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid date"* ]]

  run /bin/bash -c \
    "source '$AUDIT_LIB'; walter_audit_verify_rekor_anchor '2026-05-31' 'not-a-root' 'http://rekor.example'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid root hash"* ]]
}

@test "direct Rekor upload creates the audit directory before writing receipt" {
  _make_chain
  bash "$WALTER_OS_BIN" audit close-day 2026-05-31 >/dev/null
  root_hash="$(cat "$(_root_path)")"
  external_chain="$TMP_HOME/external-chain.jsonl"
  cp "$(_chain_path)" "$external_chain"
  rm -rf "$WALTER_CONFIG/audit"
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    /bin/bash -c "source '$AUDIT_LIB'; walter_audit_rekor_upload '2026-05-31' '$root_hash' '$external_chain' 'http://rekor.example'"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: anchored audit root in Rekor"* ]]
  [ -f "$(_rekor_path)" ]
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

@test "close-day recovers an existing Rekor entry after duplicate upload" {
  _make_chain
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_MODE=duplicate \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: anchored audit root in Rekor abc123"* ]]
  [ -f "$(_rekor_path)" ]
  jq -e '.entry_id == "abc123"' "$(_rekor_path)"
  grep -q 'http://rekor.example/api/v1/log/entries/abc123' "$(_curl_args_path)"
}

@test "close-day recovers duplicate Rekor entry id from response message" {
  _make_chain
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_MODE=duplicate-message \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: anchored audit root in Rekor abc123"* ]]
  [ -f "$(_rekor_path)" ]
  jq -e '.entry_id == "abc123"' "$(_rekor_path)"
  grep -q 'http://rekor.example/api/v1/log/entries/abc123' "$(_curl_args_path)"
}

@test "close-day rejects a Rekor POST response not bound to the payload" {
  _make_chain
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_MODE=wrong-payload \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor entry payload hash mismatch"* ]]
  [[ "$output" != *"ok: anchored audit root in Rekor"* ]]
  [ ! -f "$(_rekor_path)" ]
}

@test "close-day rejects a duplicate Rekor response not bound to the payload" {
  _make_chain
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_MODE=duplicate-wrong-payload \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor entry payload hash mismatch"* ]]
  [[ "$output" != *"ok: anchored audit root in Rekor"* ]]
  [ ! -f "$(_rekor_path)" ]
}

@test "Rekor request signature verifies against submitted hash digest" {
  _make_chain
  _write_mock_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 0 ]
  hash_value="$(jq -r '.spec.data.hash.value' "$(_curl_body_path)")"
  sig_value="$(jq -r '.spec.signature.content' "$(_curl_body_path)")"
  public_key_value="$(jq -r '.spec.signature.publicKey.content' "$(_curl_body_path)")"
  _hex_to_file "$hash_value" "$TMP_HOME/rekor-digest.bin"
  _decode_base64_to_file "$sig_value" "$TMP_HOME/rekor-sig.bin"
  _decode_base64_to_file "$public_key_value" "$TMP_HOME/rekor-pub.pem"

  run "$(_openssl_bin)" pkeyutl -verify -pubin \
    -inkey "$TMP_HOME/rekor-pub.pem" \
    -rawin \
    -in "$TMP_HOME/rekor-digest.bin" \
    -sigfile "$TMP_HOME/rekor-sig.bin"

  [ "$status" -eq 0 ]
}

@test "Rekor material verifier succeeds when cleanup fails after valid checks" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq '.response' "$(_rekor_path)" > "$TMP_HOME/rekor-response.json"
  entry_id="$(jq -r '.entry_id' "$(_rekor_path)")"
  payload_hash="$(jq -r '.payload_sha256' "$(_rekor_path)")"
  sig="$(jq -r '.sig' "$(_rekor_path)")"
  public_key="$(jq -r '.public_key' "$(_rekor_path)")"

  run /bin/bash -c "
    source '$AUDIT_LIB'
    rm() {
      if [[ \"\${1:-}\" == '-rf' && \"\${2:-}\" == *audit-rekor-binding* ]]; then
        return 1
      fi
      command rm \"\$@\"
    }
    _walter_audit_rekor_verify_response_material \
      '$TMP_HOME/rekor-response.json' '$entry_id' '$payload_hash' '$sig' '$public_key' '$public_key'
  "

  [ "$status" -eq 0 ]
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

@test "verify-chain --check-rekor honors WALTER_AUDIT_REKOR_URL over stored receipt URL" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://stored-rekor.example" 2026-05-31

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_URL="http://env-rekor.example" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor 2026-05-31

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified Rekor anchor abc123"* ]]
  grep -q 'http://env-rekor.example/api/v1/log/entries/abc123' "$(_curl_args_path)"
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

@test "verify-chain --check-rekor fails when the remote signature differs" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  python3 - "$(_curl_body_path)" <<'PY'
import base64
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
body = json.loads(path.read_text(encoding="utf-8"))
body["spec"]["signature"]["content"] = base64.b64encode(b"\0" * 64).decode("ascii")
path.write_text(json.dumps(body), encoding="utf-8")
PY

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor entry signature mismatch"* ]]
  [[ "$output" != *"ok: verified 2 row(s)"* ]]
}

@test "verify-chain --check-rekor reports malformed remote signature cleanly" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq '.spec.signature.content = "not-base64"' \
    "$(_curl_body_path)" > "$TMP_HOME/remote-body.json"
  mv "$TMP_HOME/remote-body.json" "$(_curl_body_path)"
  jq '.sig = "not-base64"' "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  mv "$TMP_HOME/receipt.json" "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor entry signature is invalid"* ]]
  [[ "$output" != *"invalid signature base64"* ]]
}

@test "verify-chain --check-rekor fails when Rekor key differs from final session key" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  openssl_bin="$(_openssl_bin)"
  hash_value="$(jq -r '.spec.data.hash.value' "$(_curl_body_path)")"
  _hex_to_file "$hash_value" "$TMP_HOME/attacker-digest.bin"
  "$openssl_bin" genpkey -algorithm ED25519 -out "$TMP_HOME/attacker.key" >/dev/null 2>&1
  "$openssl_bin" pkey -in "$TMP_HOME/attacker.key" -pubout -out "$TMP_HOME/attacker.pub" >/dev/null 2>&1
  "$openssl_bin" pkeyutl -sign -inkey "$TMP_HOME/attacker.key" \
    -rawin \
    -in "$TMP_HOME/attacker-digest.bin" \
    -out "$TMP_HOME/attacker.sig" >/dev/null 2>&1
  attacker_sig="$(_base64_file "$TMP_HOME/attacker.sig")"
  attacker_public_key="$(_base64_file "$TMP_HOME/attacker.pub")"
  jq --arg sig "$attacker_sig" --arg public_key "$attacker_public_key" \
    '.spec.signature.content = $sig | .spec.signature.publicKey.content = $public_key' \
    "$(_curl_body_path)" > "$TMP_HOME/remote-body.json"
  mv "$TMP_HOME/remote-body.json" "$(_curl_body_path)"
  jq --arg sig "$attacker_sig" --arg public_key "$attacker_public_key" \
    '.sig = $sig | .public_key = $public_key' \
    "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  mv "$TMP_HOME/receipt.json" "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"final audit session key"* ]]
}

@test "close-day rejects an existing Rekor receipt with the wrong date" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq '.payload.date = "2026-06-01"' "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  receipt_payload="$(jq -cS '.payload' "$TMP_HOME/receipt.json")"
  receipt_hash="$(_sha256 "$receipt_payload")"
  jq --arg hash "$receipt_hash" '.payload_sha256 = $hash' \
    "$TMP_HOME/receipt.json" > "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor receipt date mismatch"* ]]
}

@test "close-day rejects an existing Rekor receipt from a different URL" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://first-rekor.example" 2026-05-31

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://second-rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor receipt URL mismatch"* ]]
  [[ "$output" != *"ok: closed audit day"* ]]
}

@test "close-day rejects an existing Rekor receipt without URL" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq 'del(.rekor_url)' "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  mv "$TMP_HOME/receipt.json" "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor receipt URL missing"* ]]
}

@test "close-day rejects an existing Rekor receipt missing required fields" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  cp "$(_rekor_path)" "$TMP_HOME/original-receipt.json"

  for field in entry_id sig public_key; do
    jq --arg field "$field" 'del(.[$field])' \
      "$TMP_HOME/original-receipt.json" > "$(_rekor_path)"

    run env \
      PATH="$TMP_HOME/bin:$PATH" \
      WALTER_AUDIT_REKOR_UPLOAD=1 \
      WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
      WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
      bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

    [ "$status" -eq 1 ]
    [[ "$output" == *"Rekor receipt missing ${field}"* ]]
    [[ "$output" != *"ok: Rekor receipt already exists"* ]]
  done
}

@test "close-day verifies an existing Rekor receipt against the remote entry" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq '.spec.data.hash.value = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$(_curl_body_path)" > "$TMP_HOME/remote-body.json"
  mv "$TMP_HOME/remote-body.json" "$(_curl_body_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor entry payload hash mismatch"* ]]
  [[ "$output" != *"ok: Rekor receipt already exists"* ]]
}

@test "close-day rejects an existing Rekor receipt with a non-final public key" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq '.public_key = "not-the-final-public-key" | .sig = "not-the-final-signature"' \
    "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  mv "$TMP_HOME/receipt.json" "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor receipt public key does not match final audit session key"* ]]
  [[ "$output" != *"ok: Rekor receipt already exists"* ]]
}

@test "verify-chain --check-rekor rejects a receipt without URL" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  jq 'del(.rekor_url)' "$(_rekor_path)" > "$TMP_HOME/receipt.json"
  mv "$TMP_HOME/receipt.json" "$(_rekor_path)"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$WALTER_OS_BIN" audit verify-chain --check-rekor --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"Rekor receipt URL missing"* ]]
}

@test "close-day does not print success when Rekor upload fails" {
  _make_chain
  _write_failing_curl

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_MARKER="$TMP_HOME/curl-called" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31

  [ "$status" -eq 1 ]
  [[ "$output" == *"unable to contact Rekor"* ]]
  [[ "$output" != *"ok: closed audit day"* ]]
  [ -f "$TMP_HOME/curl-called" ]
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

@test "verify-chain --check-rekor holds the audit lock through Rekor verification" {
  _make_chain
  _write_mock_curl
  WALTER_AUDIT_REKOR_UPLOAD=1 \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    PATH="$TMP_HOME/bin:$PATH" \
    bash "$WALTER_OS_BIN" audit close-day --rekor-url "http://rekor.example" 2026-05-31
  race_status="$TMP_HOME/verify-race-status"
  probe_script="$TMP_HOME/rekor-verify-race-probe.sh"
  cat > "$probe_script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$AUDIT_LIB"
eval "$(declare -f walter_audit_verify_rekor_anchor | sed '1s/walter_audit_verify_rekor_anchor/_original_walter_audit_verify_rekor_anchor/')"
walter_audit_verify_rekor_anchor() {
  set +e
  WALTER_AUDIT_NOW="2026-05-31T12:00:02Z" WALTER_AUDIT_LOCK_WAIT_SECONDS=0 \
    bash -c "source \"$AUDIT_LIB\"; walter_audit_append Bash 'racing verify append' allow approval-gate ok" >/dev/null 2>&1
  child_status="$?"
  set -e
  printf '%s' "$child_status" > "$RACE_STATUS"
  _original_walter_audit_verify_rekor_anchor "$@"
}
walter_audit_verify_chain_with_rekor 2026-05-31 "http://rekor.example"
SH
  chmod +x "$probe_script"

  run env \
    PATH="$TMP_HOME/bin:$PATH" \
    AUDIT_LIB="$AUDIT_LIB" \
    RACE_STATUS="$race_status" \
    WALTER_TEST_REKOR_CURL_ARGS="$(_curl_args_path)" \
    WALTER_TEST_REKOR_CURL_BODY="$(_curl_body_path)" \
    bash "$probe_script"

  [ "$status" -eq 0 ]
  [ -f "$race_status" ]
  [ "$(cat "$race_status")" != "0" ]
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
