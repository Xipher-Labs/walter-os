#!/usr/bin/env bats
# walter-os cap CLI tests.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
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

@test "walter-os cap mint writes a session-bound token and verify returns claims" {
  cd "$REPO_UNDER_TEST"

  run "$CLI" cap mint Bash --paths 'src/*' --network api.github.com --patterns '^make test$' --duration 30m

  [ "$status" -eq 0 ]
  [[ "$output" == v4.public.* ]]
  token="$output"

  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  [ "$(find "$caps_dir" -type f -name 'cap-*.paseto' | wc -l | tr -d ' ')" = "1" ]

  token_file="$(find "$caps_dir" -type f -name 'cap-*.paseto' | head -1)"
  [ "$(cat "$token_file")" = "$token" ]

  run "$CLI" cap verify "$token_file"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tool == "Bash" and .scope.paths == ["src/*"] and .scope.network == ["api.github.com"]'
}

@test "walter-os cap list and revoke operate on active session tokens" {
  cd "$REPO_UNDER_TEST"
  "$CLI" cap mint Write --paths README.md --duration 5m >/dev/null

  run "$CLI" cap list

  [ "$status" -eq 0 ]
  nonce="$(echo "$output" | jq -r '.[0].nonce')"
  [ "$nonce" != "null" ]
  echo "$output" | jq -e '.[0].tool == "Write"'

  run "$CLI" cap revoke "$nonce"

  [ "$status" -eq 0 ]
  [[ "$output" == *"revoked"* ]]

  run "$CLI" cap list

  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "walter-os cap mint rejects bare duration integers" {
  cd "$REPO_UNDER_TEST"

  run "$CLI" cap mint Bash --patterns '.*' --duration 4

  [ "$status" -eq 2 ]
  [[ "$output" == *"duration must include a unit"* ]]
}

@test "walter-os cap mint is blocked inside subagent context" {
  cd "$REPO_UNDER_TEST"
  export WALTER_AGENT_CONTEXT=reviewer

  run "$CLI" cap mint Bash --patterns '.*' --duration 5m

  [ "$status" -eq 4 ]
  [[ "$output" == *"cap minting blocked inside subagent context"* ]]
}
