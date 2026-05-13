#!/usr/bin/env bats
# Tests for `walter-os agents unlock --reason` subcommand
# Covers: AC-5 of Improvement 8 (T-8)

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  ALERTS_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/alerts.sh"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"
  [[ -f "$ALERTS_LIB" ]] || skip "alerts.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  WALTER_CONFIG="$(mktemp -d -t walter-unlock-test-XXXXXX)"
  export WALTER_CONFIG
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."

  # Redirect alert log to temp dir to avoid polluting real log
  export WALTER_ALERT_LOG="$WALTER_CONFIG/events.log"

  # Set required PAUSE_FLAG and GATE_LOCK to temp paths
  export PAUSE_FLAG="$WALTER_CONFIG/agents.paused"
  export GATE_LOCK="$WALTER_CONFIG/gate.lock"
  export TOWER_CRITICAL_FLAG="$WALTER_CONFIG/tower-critical.flag"
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "agents unlock removes gate.lock and exits 0" {
  # Precondition: gate.lock exists
  touch "$WALTER_CONFIG/gate.lock"
  [[ -f "$WALTER_CONFIG/gate.lock" ]]

  run "$WALTER_OS" agents unlock --reason "test recovery"
  [[ "$status" -eq 0 ]]
  # gate.lock must be gone
  [[ ! -f "$WALTER_CONFIG/gate.lock" ]]
}

@test "agents unlock logs to events.log with reason" {
  touch "$WALTER_CONFIG/gate.lock"

  run "$WALTER_OS" agents unlock --reason "test recovery"
  [[ "$status" -eq 0 ]]
  # events.log must exist and contain the unlock event
  [[ -f "$WALTER_ALERT_LOG" ]]
  grep -q "alert_unlock" "$WALTER_ALERT_LOG"
}

@test "agents unlock is idempotent when gate.lock absent" {
  # Precondition: no gate.lock
  [[ ! -f "$WALTER_CONFIG/gate.lock" ]]

  run "$WALTER_OS" agents unlock --reason "idempotent check"
  [[ "$status" -eq 0 ]]
}

@test "agents unlock without --reason exits 2 with error message" {
  run "$WALTER_OS" agents unlock
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "reason" || "$stderr" =~ "reason" ]] || \
    [[ "$(echo "$output$stderr" | grep -c reason)" -gt 0 ]] || \
    { echo "Expected 'reason' in output; got: $output"; false; }
}

@test "agents unlock --reason without value exits 2 with stderr message" {
  # F8: --reason flag present but no value → must not crash with unbound var
  run "$WALTER_OS" agents unlock --reason
  [[ "$status" -eq 2 ]]
  # Must emit a useful error message, not a shell crash
  [[ "$output" =~ [Ee]rror || "$output" =~ [Rr]eason || \
     "$stderr" =~ [Ee]rror || "$stderr" =~ [Rr]eason ]] || \
    { echo "Expected error/reason in output; got: output='$output' stderr='$stderr'"; false; }
}
