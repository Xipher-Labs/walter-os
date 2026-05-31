#!/usr/bin/env bats
# tests/hooks/session-timeout.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/session-timeout.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_MAX_HOURS=8
  export WALTER_SESSION_MAX_IDLE_MIN=60
  REPO_UNDER_TEST="$TMP_HOME/work/repo"
  mkdir -p "$WALTER_CONFIG" "$REPO_UNDER_TEST"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

_event() {
  jq -nc --arg cwd "$REPO_UNDER_TEST" '{cwd:$cwd, prompt:"hello"}'
}

_call_hook() {
  _event | bash "$HOOK"
}

@test "UserPromptSubmit hook starts and allows a fresh session" {
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "allow"'
}

@test "UserPromptSubmit hook allows active session within limits" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  _call_hook >/dev/null

  export WALTER_SESSION_NOW_EPOCH=1767227400
  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "allow"'
}

@test "UserPromptSubmit hook blocks after max hours" {
  export WALTER_SESSION_MAX_IDLE_MIN=600
  export WALTER_SESSION_NOW_EPOCH=1767225600
  _call_hook >/dev/null

  export WALTER_SESSION_NOW_EPOCH=1767254401
  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "block"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q 'max-hours=8h'
}

@test "UserPromptSubmit hook blocks after idle timeout" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  _call_hook >/dev/null

  export WALTER_SESSION_NOW_EPOCH=1767231001
  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "block"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q 'max-idle=60m'
}

@test "UserPromptSubmit hook applies PHI max-hours cap" {
  export WALTER_PHI_MODE=1
  export WALTER_SESSION_MAX_HOURS=12
  export WALTER_SESSION_MAX_IDLE_MIN=600
  state_file="$(bash -c "source '$REPO_ROOT/scripts/walter/lib/session-state.sh'; walter_session_state_file '$REPO_UNDER_TEST'")"
  mkdir -p "$(dirname "$state_file")"
  jq -n \
    --arg started_at "2026-01-01T00:00:00Z" \
    --arg last_activity_at "2026-01-01T03:50:00Z" \
    --arg repo_path "$REPO_UNDER_TEST" \
    '{session_id:"phi", started_at:$started_at, last_activity_at:$last_activity_at, repo_path:$repo_path, extensions:[]}' > "$state_file"

  export WALTER_SESSION_NOW_EPOCH=1767240001
  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "block"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q 'max-hours=4h'
}

@test "UserPromptSubmit hook fails closed on malformed state" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  state_file="$(bash -c "source '$REPO_ROOT/scripts/walter/lib/session-state.sh'; walter_session_state_file '$REPO_UNDER_TEST'")"
  mkdir -p "$(dirname "$state_file")"
  printf '{}\n' > "$state_file"

  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "block"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q 'malformed-state'
}

@test "UserPromptSubmit hook fails closed on non-object JSON input" {
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "printf '[]' | '$HOOK'"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "block"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q 'non-object hook input'
}

@test "UserPromptSubmit hook maps status 12 without JSON to state-write" {
  fake_home="$TMP_HOME/fake-walter"
  mkdir -p "$fake_home/scripts/walter/lib"
  cat > "$fake_home/scripts/walter/lib/session-state.sh" <<'EOF'
walter_session_touch() {
  return 12
}
EOF

  export WALTER_OS_HOME="$fake_home"
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run _call_hook

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "block"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q 'state-write'
}
