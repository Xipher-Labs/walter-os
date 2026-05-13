#!/usr/bin/env bats
# Tests for T-32: mode.json + walter-os mode consensus on|off|status
# Covers: AC-1 of Improvement 9

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-mode-test-XXXXXX)"
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "mode consensus on creates mode.json with consensus:true" {
  run "$WALTER_OS" mode consensus on
  [[ "$status" -eq 0 ]]
  [[ -f "$WALTER_CONFIG/mode.json" ]]
  val=$(jq -r '.consensus' "$WALTER_CONFIG/mode.json")
  [[ "$val" == "true" ]]
}

@test "mode consensus on sets since timestamp" {
  run "$WALTER_OS" mode consensus on
  [[ "$status" -eq 0 ]]
  since=$(jq -r '.since' "$WALTER_CONFIG/mode.json")
  [[ -n "$since" && "$since" != "null" ]]
}

@test "mode consensus on sets default voting_threshold 3" {
  run "$WALTER_OS" mode consensus on
  [[ "$status" -eq 0 ]]
  threshold=$(jq -r '.voting_threshold' "$WALTER_CONFIG/mode.json")
  [[ "$threshold" == "3" ]]
}

@test "mode consensus off sets consensus:false in mode.json" {
  run "$WALTER_OS" mode consensus on
  run "$WALTER_OS" mode consensus off
  [[ "$status" -eq 0 ]]
  val=$(jq -r '.consensus' "$WALTER_CONFIG/mode.json")
  [[ "$val" == "false" ]]
}

@test "mode consensus status shows ON when mode.json has consensus:true" {
  run "$WALTER_OS" mode consensus on
  run "$WALTER_OS" mode consensus status
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "ON" || "$output" =~ "on" ]]
}

@test "mode consensus status shows OFF when consensus:false" {
  run "$WALTER_OS" mode consensus on
  run "$WALTER_OS" mode consensus off
  run "$WALTER_OS" mode consensus status
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "OFF" || "$output" =~ "off" ]]
}

@test "mode consensus status shows OFF when mode.json missing" {
  run "$WALTER_OS" mode consensus status
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "OFF" || "$output" =~ "off" ]]
}

@test "mode consensus on --threshold sets custom threshold" {
  run "$WALTER_OS" mode consensus on --threshold 2
  [[ "$status" -eq 0 ]]
  threshold=$(jq -r '.voting_threshold' "$WALTER_CONFIG/mode.json")
  [[ "$threshold" == "2" ]]
}

@test "mode lib exists at scripts/agents/lib/mode.sh" {
  [[ -f "$BATS_TEST_DIRNAME/../../scripts/agents/lib/mode.sh" ]]
}

# --- Fix 3: Atomic write for consensus ON ---

@test "Fix3: mode consensus on uses atomic write (tmpfile + mv in on branch)" {
  # Verify that the 'on' branch in mode.sh uses mktemp + mv, not direct redirect.
  # Extract only the 'on)' section and confirm it contains mktemp.
  MODE_SH="$BATS_TEST_DIRNAME/../../scripts/agents/lib/mode.sh"
  [[ -f "$MODE_SH" ]] || skip "mode.sh not found"

  # The 'on)' branch must NOT use '> "$MODE_FILE"' directly (truncate-then-write).
  # It must use mktemp + mv (atomic rename).
  # We extract lines between 'on)' and the next ')' close of the case branch.
  on_branch=$(awk '/^[[:space:]]*on\)/{found=1} found{print} /^[[:space:]]*;;/{if(found)exit}' "$MODE_SH")
  # Must contain mktemp in the on branch
  echo "$on_branch" | grep -q "mktemp"
  # Must contain mv (atomic rename)
  echo "$on_branch" | grep -q "mv "
  # Must NOT contain direct write '> "$MODE_FILE"' in the on branch
  ! echo "$on_branch" | grep -q '> "\$MODE_FILE"'
}

@test "Fix3: mode.json is valid JSON after consensus on" {
  run "$WALTER_OS" mode consensus on
  [[ "$status" -eq 0 ]]
  # File must exist and be valid JSON (not empty/partial)
  [[ -f "$WALTER_CONFIG/mode.json" ]]
  jq . "$WALTER_CONFIG/mode.json" >/dev/null 2>&1
}

@test "T2: mode consensus off uses atomic write even when mode.json does not exist" {
  # When mode.json is absent, 'consensus off' must still use mktemp+mv, not direct >.
  # Static check: the off-branch 'else' (no-file case) must use mktemp, not '> "$MODE_FILE"'.
  MODE_SH="$BATS_TEST_DIRNAME/../../scripts/agents/lib/mode.sh"
  [[ -f "$MODE_SH" ]] || skip "mode.sh not found"

  # Extract the 'off)' case block
  off_branch=$(awk '/^[[:space:]]*off\)/{found=1} found{print} /^[[:space:]]*;;/{if(found)exit}' "$MODE_SH")
  # Must NOT have a direct redirect '> "$MODE_FILE"' in the off branch
  ! echo "$off_branch" | grep -qF '> "$MODE_FILE"'
}

@test "Fix3: concurrent consensus on does not produce empty mode.json" {
  # Kick off 10 rapid 'consensus on' calls in parallel; none should leave empty file.
  # This is a probabilistic race test — the atomic write eliminates the empty-file window.
  for i in $(seq 1 10); do
    "$WALTER_OS" mode consensus on &
  done
  wait
  # After all parallel writes, mode.json must exist and be valid JSON
  [[ -f "$WALTER_CONFIG/mode.json" ]]
  jq . "$WALTER_CONFIG/mode.json" >/dev/null 2>&1
  val=$(jq -r '.consensus' "$WALTER_CONFIG/mode.json")
  [[ "$val" == "true" ]]
}
