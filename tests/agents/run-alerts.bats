#!/usr/bin/env bats
# Tests for T-29: alert_emit wired into agent runner
# Covers: AC-1 through AC-4 of Improvement 8 (alerts integration)

setup() {
  RUN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/run.sh"
  [[ -f "$RUN_SH" ]] || skip "run.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

@test "run.sh sources alerts.sh" {
  grep -q "source.*alerts.sh\|source.*lib/alerts\|\. .*alerts" "$RUN_SH"
}

@test "run.sh has no direct curl api.telegram.org calls" {
  # Direct Telegram calls should be replaced by alert_emit
  ! grep -q 'curl.*api\.telegram\.org' "$RUN_SH"
}

@test "run.sh emits warn alert on task failure" {
  grep -q "alert_emit.*warn\|alert_emit warn" "$RUN_SH"
}

@test "watchdog.sh has no direct curl api.telegram.org calls" {
  WATCHDOG="$BATS_TEST_DIRNAME/../../scripts/agents/watchdog.sh"
  [[ -f "$WATCHDOG" ]] || skip "watchdog.sh not found"
  ! grep -q 'curl.*api\.telegram\.org' "$WATCHDOG"
}

@test "main.sh has no direct curl api.telegram.org calls" {
  MAIN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/main.sh"
  [[ -f "$MAIN_SH" ]] || skip "main.sh not found"
  ! grep -q 'curl.*api\.telegram\.org' "$MAIN_SH"
}
