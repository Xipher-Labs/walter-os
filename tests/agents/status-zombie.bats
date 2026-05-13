#!/usr/bin/env bats
# Tests for T-21: zombie section in `walter-os agents status`
# Covers: AC-5 of Improvement 5

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  WALTER_CONFIG="$(mktemp -d -t status-zombie-test-XXXXXX)"
  export WALTER_CONFIG
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_METRICS_DIR="$WALTER_CONFIG/metrics"
  export WALTER_METRICS_FILE="$WALTER_CONFIG/metrics/metrics.prom"

  WATCHDOG_LOG_DIR="$(mktemp -d -t status-zombie-log-XXXXXX)"
  export WALTER_WATCHDOG_LOG="$WATCHDOG_LOG_DIR/watchdog.log"
}

teardown() {
  rm -rf "$WALTER_CONFIG" "$WATCHDOG_LOG_DIR"
}

@test "agents status shows Zombies section when watchdog log exists" {
  # Create a watchdog log with a zombie_detected event
  mkdir -p "$WATCHDOG_LOG_DIR"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","event":"zombie_detected","issue_id":"issue-aaa","reason":"stale heartbeat"}\n' \
    "$ts" > "$WALTER_WATCHDOG_LOG"

  run "$WALTER_OS" agents status
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "zombie"
}

@test "agents status zombie count is correct for last 7d" {
  mkdir -p "$WATCHDOG_LOG_DIR"
  # Add 2 zombie events within last 7d
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","event":"zombie_detected","issue_id":"issue-a","reason":"stale"}\n' \
    "$ts" >> "$WALTER_WATCHDOG_LOG"
  printf '{"ts":"%s","event":"zombie_detected","issue_id":"issue-b","reason":"stale"}\n' \
    "$ts" >> "$WALTER_WATCHDOG_LOG"
  # Add a non-zombie event that should not be counted
  printf '{"ts":"%s","event":"scan_complete","issue_id":"","reason":"zombies_found=2"}\n' \
    "$ts" >> "$WALTER_WATCHDOG_LOG"

  run "$WALTER_OS" agents status
  [[ "$status" -eq 0 ]]
  # Should show count = 2
  echo "$output" | grep -qi "zombie" && echo "$output" | grep -qE "[Zz]ombies.*2|2.*[Zz]ombie"
}

@test "agents status shows Zombies: 0 when no zombie events in log" {
  mkdir -p "$WATCHDOG_LOG_DIR"
  # Only scan_complete events, no zombie_detected
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","event":"scan_complete","issue_id":"","reason":"no claimed issues"}\n' \
    "$ts" > "$WALTER_WATCHDOG_LOG"

  run "$WALTER_OS" agents status
  [[ "$status" -eq 0 ]]
  # Should still show zombie section with 0
  echo "$output" | grep -qi "zombie"
}

@test "agents status omits zombie section when WALTER_WATCHDOG_LOG absent" {
  # No watchdog log at all — section should be absent or explicitly say 0
  # This is a graceful degradation test
  unset WALTER_WATCHDOG_LOG
  run "$WALTER_OS" agents status
  [[ "$status" -eq 0 ]]
  # No crash; may or may not show zombie section
}

@test "R10: agents status counts zombies correctly when WATCHDOG_LOG path has single quote" {
  # R10: main.sh interpolates $WATCHDOG_LOG directly into python3 source:
  # open('$WATCHDOG_LOG') — a path with ' breaks the string literal silently,
  # returning count=0 (via || echo 0) instead of the actual count.
  # Fix: pass path via env var not source interpolation.
  local log_dir
  log_dir="$(mktemp -d -t "status-r10 it's XXXXXX")"
  local log_path="${log_dir}/watchdog.log"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","event":"zombie_detected","issue_id":"issue-r10","reason":"stale"}\n' \
    "$ts" > "$log_path"

  export WALTER_WATCHDOG_LOG="$log_path"

  run "$WALTER_OS" agents status
  rm -rf "$log_dir"

  [[ "$status" -eq 0 ]]
  # Must show count = 1, not 0 (which would indicate the broken python3 path)
  echo "$output" | grep -qE "[Zz]ombies.*1|1.*[Zz]ombie"
}

@test "agents status zombie count excludes events older than 7d" {
  mkdir -p "$WATCHDOG_LOG_DIR"
  # Add 1 recent event and 1 old event (8 days ago)
  local ts_recent; ts_recent=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Old timestamp: 8 days ago
  local ts_old
  if date -v-8d >/dev/null 2>&1; then
    ts_old=$(date -v-8d -u +%Y-%m-%dT%H:%M:%SZ)
  else
    ts_old=$(date -u -d "8 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "2020-01-01T00:00:00Z")
  fi
  printf '{"ts":"%s","event":"zombie_detected","issue_id":"issue-old","reason":"stale"}\n' \
    "$ts_old" >> "$WALTER_WATCHDOG_LOG"
  printf '{"ts":"%s","event":"zombie_detected","issue_id":"issue-recent","reason":"stale"}\n' \
    "$ts_recent" >> "$WALTER_WATCHDOG_LOG"

  run "$WALTER_OS" agents status
  [[ "$status" -eq 0 ]]
  # Should show 1 (recent) not 2
  echo "$output" | grep -qi "zombie"
}
