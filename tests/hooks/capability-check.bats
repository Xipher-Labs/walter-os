#!/usr/bin/env bats
# tests/hooks/capability-check.bats
#
# OSS Trust #122 / capability-tokens AC-3.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/capability-check.sh"
  CLI="$REPO_ROOT/bin/walter-os"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  REPO_UNDER_TEST="$TMP_HOME/work/repo"
  mkdir -p "$WALTER_CONFIG" "$REPO_UNDER_TEST"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

_hook_json() {
  local tool="$1" key="$2" value="$3"
  printf '{"tool_name":"%s","tool_input":{"%s":%s}}' \
    "$tool" "$key" "$(printf '%s' "$value" | jq -Rs .)" \
    | WALTER_SESSION_REPO="$REPO_UNDER_TEST" bash "$HOOK"
}

_mint() {
  (cd "$REPO_UNDER_TEST" && "$CLI" cap mint "$@")
}

@test "high-tier Bash egress without capability is blocked" {
  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'no valid token'
}

@test "Bash egress with matching network capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "git ssh URL with matching network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "git clone ssh://git@github.com/org/repo")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress requires capability coverage for every destination" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y && curl https://uploads.github.com/upload")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash egress with all network destinations covered is allowed" {
  _mint Bash --network api.github.com --network uploads.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y && curl https://uploads.github.com/upload")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress with matching pattern capability is allowed" {
  _mint Bash --patterns '^curl[[:space:]].*api[.]github[.]com' --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "argument-less git fetch is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "git fetch")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "argument-less git fetch with matching pattern capability is allowed" {
  _mint Bash --patterns '^git[[:space:]]+fetch$' --duration 30m >/dev/null

  output="$(_hook_json Bash command "git fetch")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash command with matching pattern capability is allowed" {
  _mint Bash --patterns '^gh[[:space:]]+pr[[:space:]]+review.*--approve' --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh pr review 243 --approve")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "expired capability is ignored and high-tier Bash blocks" {
  _mint Bash --network api.github.com --duration 5m >/dev/null
  export WALTER_SESSION_NOW_EPOCH=1767225961

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "low-tier Bash with no capability passes through" {
  output="$(_hook_json Bash command "echo hello")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write with matching path capability is allowed" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "docs/specs/example.md")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "medium-tier Write without capability passes through" {
  output="$(_hook_json Write file_path "docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write absolute repo path matches relative path capability" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "$REPO_UNDER_TEST/docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write without matching path capability is blocked" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "hooks/approval-gate.sh")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "two-factor Bash bypass allows high-tier no-cap command with warning" {
  export WALTER_CAP_BYPASS=1

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y --allow-no-cap")"
  echo "$output" | jq -e '.decision == "allow" and (.systemMessage | test("capability-check"))'
}
