#!/usr/bin/env bats
# tests/walter/session-cli.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CLI="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  REPO_UNDER_TEST="$TMP_HOME/work/repo"
  mkdir -p "$WALTER_CONFIG" "$REPO_UNDER_TEST"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

@test "walter-os session status reports no-session when absent" {
  run "$CLI" session status "$REPO_UNDER_TEST"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "no-session"'
}

@test "walter-os session restart clears state" {
  bash -c "source '$REPO_ROOT/scripts/walter/lib/session-state.sh'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  state_file="$(bash -c "source '$REPO_ROOT/scripts/walter/lib/session-state.sh'; walter_session_state_file '$REPO_UNDER_TEST'")"
  [ -f "$state_file" ]

  run "$CLI" session restart "$REPO_UNDER_TEST"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ended"'
  [ ! -f "$state_file" ]
}

@test "/session command has frontmatter and forwards arguments" {
  command_file="$REPO_ROOT/commands/session.md"

  [ -f "$command_file" ]
  [ "$(sed -n '1p' "$command_file")" = "---" ]
  grep -q '^description:' "$command_file"
  grep -q '^argument-hint: status|restart$' "$command_file"
  grep -q 'walter-os session \$ARGUMENTS' "$command_file"
}
