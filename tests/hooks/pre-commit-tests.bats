#!/usr/bin/env bats
# Tests for hooks/pre-commit-tests.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/pre-commit-tests.sh"

  TMPDIR_TEST="$(mktemp -d)"
  export HOME="$TMPDIR_TEST/home"
  export WALTER_CONFIG="$HOME/.config/walter-os"
  export WALTER_AUDIT_DIR="$WALTER_CONFIG/audit"
  mkdir -p "$WALTER_CONFIG"
  cd "$TMPDIR_TEST"
  git init -q -b feature/test
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
}

teardown() {
  unset WALTER_CONFIG WALTER_AUDIT_DIR
  rm -rf "$TMPDIR_TEST"
}

input_json() {
  printf '{"tool":"Bash","tool_input":{"command":%s}}' "$(jq -Rs '.' <<<"$1")"
}

@test "allows non-commit commands" {
  result="$(input_json "ls" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "blocks malformed hook JSON" {
  result="$(printf '{"tool_input":' | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
  jq -e '.reason | contains("invalid hook JSON")' <<<"$result" >/dev/null
}

@test "blocks missing command in hook JSON" {
  result="$(printf '{"tool_name":"Bash","tool_input":{}}' | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
  jq -e '.reason | contains("missing tool_input.command")' <<<"$result" >/dev/null
}

@test "allows commit with --no-verify" {
  result="$(input_json "git commit -m foo --no-verify" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "allows commit on feature branch when no project files exist" {
  result="$(input_json 'git commit -m "test"' | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "does not match git commit-tree" {
  result="$(input_json "git commit-tree HEAD" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "block reasons are emitted as valid JSON strings" {
  git checkout -q -b 'feature/json"branch'
  cat > package.json <<'JSON'
{"scripts":{"lint":"printf 'lint failed\\n'; exit 1"}}
JSON
  result="$(input_json 'git commit -m "test"' | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
  jq -e '.reason | contains("Pre-commit")' <<<"$result" >/dev/null
}

# --------------- Fix 5: wiki-validator wired as PreToolUse hook ---------------

@test "install.sh includes wiki-validator in PreToolUse hook template" {
  INSTALL="$BATS_TEST_DIRNAME/../../install.sh"
  grep -q "wiki-validator" "$INSTALL"
}
