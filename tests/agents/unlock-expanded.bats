#!/usr/bin/env bats
# Tests for T-31: agents unlock expanded (removes pause flag too)
# Covers: AC-5 of Improvement 8

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-unlock-expanded-XXXXXX)"
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_ALERT_LOG="$WALTER_CONFIG/events.log"
  export PAUSE_FLAG="$WALTER_CONFIG/agents.paused"
  export GATE_LOCK="$WALTER_CONFIG/gate.lock"
  export TOWER_CRITICAL_FLAG="$WALTER_CONFIG/tower-critical.flag"
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "unlock removes both gate.lock AND pause flag" {
  # Simulate panic state: both files exist
  printf '%s\npanic\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GATE_LOCK"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$PAUSE_FLAG"

  run "$WALTER_OS" agents unlock --reason "test recovery"
  [[ "$status" -eq 0 ]]
  [[ ! -f "$GATE_LOCK" ]]
  [[ ! -f "$PAUSE_FLAG" ]]
}

@test "unlock logs alert_unlock event to events.log" {
  touch "$GATE_LOCK"
  run "$WALTER_OS" agents unlock --reason "drill test"
  [[ "$status" -eq 0 ]]
  [[ -f "$WALTER_ALERT_LOG" ]]
  grep -q "alert_unlock\|panic lock cleared" "$WALTER_ALERT_LOG"
}

@test "unlock prints confirmation with reason" {
  touch "$GATE_LOCK"
  run "$WALTER_OS" agents unlock --reason "all clear"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "all clear" || "$output" =~ "removed" ]]
}

@test "unlock requires --reason to be non-empty string" {
  run "$WALTER_OS" agents unlock --reason ""
  [[ "$status" -eq 2 ]]
}
