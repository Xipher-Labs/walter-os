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
  export WALTER_CAP_MINT_TEST_ALLOW=1
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
  echo "$output" | jq -e '.[0] | has("file") | not'
  [[ "$output" != *"cap-"*".paseto"* ]]

  run "$CLI" cap revoke "$nonce"

  [ "$status" -eq 0 ]
  [[ "$output" == *"revoked"* ]]

  run "$CLI" cap list

  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "walter-os cap verify rejects copied revoked tokens" {
  cd "$REPO_UNDER_TEST"
  "$CLI" cap mint Write --paths README.md --duration 5m >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  token_file="$(find "$caps_dir" -type f -name 'cap-*.paseto' | head -1)"
  nonce="$("$CLI" cap list | jq -r '.[0].nonce')"
  copied_token="$TMP_HOME/copied-token.paseto"
  cp "$token_file" "$copied_token"

  "$CLI" cap revoke "$nonce" >/dev/null
  run "$CLI" cap verify "$copied_token"

  [ "$status" -ne 0 ]
  [[ "$output" == *"token has been revoked"* ]]
}

@test "walter-os cap revoke rejects mutated capability paths" {
  cd "$REPO_UNDER_TEST"
  "$CLI" cap mint Write --paths README.md --duration 5m >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  nonce="$("$CLI" cap list | jq -r '.[0].nonce')"
  victim_dir="$TMP_HOME/victim-caps"
  mkdir -p "$victim_dir"
  printf 'do not delete\n' > "$victim_dir/cap-${nonce}.paseto"
  tmp_state="${state_file}.tmp"
  jq --arg victim "$victim_dir" '.capability_tokens_dir = $victim' "$state_file" > "$tmp_state"
  mv "$tmp_state" "$state_file"

  run "$CLI" cap revoke "$nonce"

  [ "$status" -ne 0 ]
  [ -f "$victim_dir/cap-${nonce}.paseto" ]
  [[ "$output" == *"capability paths do not match session id"* ]]
}

@test "walter-os cap list rejects mutated capability paths" {
  cd "$REPO_UNDER_TEST"
  "$CLI" cap mint Write --paths README.md --duration 5m >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  victim_dir="$TMP_HOME/victim-caps-list"
  mkdir -p "$victim_dir"
  printf 'do not read\n' > "$victim_dir/cap-victim.paseto"
  tmp_state="${state_file}.tmp"
  jq --arg victim "$victim_dir" '.capability_tokens_dir = $victim' "$state_file" > "$tmp_state"
  mv "$tmp_state" "$state_file"

  run "$CLI" cap list

  [ "$status" -ne 0 ]
  [[ "$output" == *"capability paths do not match session id"* ]]
  [[ "$output" != *"do not read"* ]]
}

@test "walter-os cap list rejects expired sessions and revokes material" {
  cd "$REPO_UNDER_TEST"
  export WALTER_SESSION_MAX_HOURS=8
  export WALTER_SESSION_MAX_IDLE_MIN=60
  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  export WALTER_SESSION_NOW_EPOCH=1767229261
  export WALTER_SESSION_MAX_IDLE_MIN=600

  run "$CLI" cap list

  [ "$status" -ne 0 ]
  [[ "$output" == *"session expired"* ]]
  [ ! -f "$private_key" ]
}

@test "walter-os cap revoke rejects expired sessions and revokes material" {
  cd "$REPO_UNDER_TEST"
  export WALTER_SESSION_MAX_HOURS=8
  export WALTER_SESSION_MAX_IDLE_MIN=60
  "$CLI" cap mint Write --paths README.md --duration 5m >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  nonce="$("$CLI" cap list | jq -r '.[0].nonce')"
  export WALTER_SESSION_NOW_EPOCH=1767229261
  export WALTER_SESSION_MAX_IDLE_MIN=600

  run "$CLI" cap revoke "$nonce"

  [ "$status" -ne 0 ]
  [[ "$output" == *"session expired"* ]]
  [ ! -f "$private_key" ]
}

@test "walter-os cap mint rejects bare duration integers" {
  cd "$REPO_UNDER_TEST"

  run "$CLI" cap mint Bash --patterns '.*' --duration 4

  [ "$status" -eq 2 ]
  [[ "$output" == *"duration must include a unit"* ]]
}

@test "walter-os cap mint rejects noninteractive mint outside test fixture" {
  cd "$REPO_UNDER_TEST"
  unset WALTER_CAP_MINT_TEST_ALLOW

  run "$CLI" cap mint Bash --patterns '.*' --duration 5m

  [ "$status" -eq 4 ]
  [[ "$output" == *"interactive operator terminal required"* ]]
}

@test "walter-os cap mint reports missing option values" {
  cd "$REPO_UNDER_TEST"

  run "$CLI" cap mint Bash --duration

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --duration"* ]]
}

@test "walter-os cap mint rejects exact session-end boundary" {
  cd "$REPO_UNDER_TEST"
  export WALTER_SESSION_MAX_HOURS=8
  export WALTER_SESSION_MAX_IDLE_MIN=600
  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  export WALTER_SESSION_NOW_EPOCH=1767254400

  run "$CLI" cap mint Bash --patterns '.*' --duration 5m

  [ "$status" -ne 0 ]
  [[ "$output" == *"no remaining lifetime"* ]]
}

@test "walter-os cap mint rejects expired existing session before touch" {
  cd "$REPO_UNDER_TEST"
  export WALTER_SESSION_MAX_HOURS=8
  export WALTER_SESSION_MAX_IDLE_MIN=60
  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  export WALTER_SESSION_NOW_EPOCH=1767229261
  export WALTER_SESSION_MAX_IDLE_MIN=600

  run "$CLI" cap mint Bash --patterns '.*' --duration 5m

  [ "$status" -ne 0 ]
  [[ "$output" == *"session expired"* ]]
  [ ! -f "$private_key" ]
}

@test "walter-os cap mint is blocked inside subagent context" {
  cd "$REPO_UNDER_TEST"
  export WALTER_AGENT_CONTEXT=reviewer

  run "$CLI" cap mint Bash --patterns '.*' --duration 5m

  [ "$status" -eq 4 ]
  [[ "$output" == *"cap minting blocked inside agent context"* ]]
}

@test "walter-os cap mint is blocked inside named agent context" {
  cd "$REPO_UNDER_TEST"
  export WALTER_AGENT_NAME=reviewer

  run "$CLI" cap mint Bash --patterns '.*' --duration 5m

  [ "$status" -eq 4 ]
  [[ "$output" == *"cap minting blocked inside agent context"* ]]
}
