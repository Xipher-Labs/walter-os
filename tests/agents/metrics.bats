#!/usr/bin/env bats
# Tests for scripts/agents/lib/metrics.sh
# Covers: T-1 [AC-1, AC-3 of Improvement 1]

setup() {
  LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/metrics.sh"
  [[ -f "$LIB" ]] || skip "metrics.sh not found"

  # Isolated temp dir for metrics file
  WALTER_METRICS_DIR="$(mktemp -d -t walter-metrics-test-XXXXXX)"
  export WALTER_METRICS_DIR
  export WALTER_METRICS_FILE="$WALTER_METRICS_DIR/metrics.prom"
  export WALTER_METRICS_LOCK="$WALTER_METRICS_FILE.lock"
}

teardown() {
  rm -rf "$WALTER_METRICS_DIR"
}

@test "metrics_init creates metrics file with all known metrics set to 0" {
  source "$LIB"
  metrics_init
  [[ -f "$WALTER_METRICS_FILE" ]]
  grep -q "walter_council_tasks_total" "$WALTER_METRICS_FILE"
  grep -q "walter_council_tokens_total" "$WALTER_METRICS_FILE"
  grep -q "walter_council_agent_state" "$WALTER_METRICS_FILE"
  grep -q "walter_council_heartbeat_age_seconds" "$WALTER_METRICS_FILE"
}

@test "metric_inc increments a counter with labels" {
  source "$LIB"
  metrics_init
  metric_inc "walter_council_tasks_total" 'agent="coder",result="success"' 1
  grep -q 'walter_council_tasks_total{agent="coder",result="success"} 1' "$WALTER_METRICS_FILE"
}

@test "metric_inc accumulates across two calls" {
  source "$LIB"
  metrics_init
  metric_inc "walter_council_tasks_total" 'agent="coder",result="success"' 1
  metric_inc "walter_council_tasks_total" 'agent="coder",result="success"' 1
  grep -q 'walter_council_tasks_total{agent="coder",result="success"} 2' "$WALTER_METRICS_FILE"
}

@test "metric_set sets a gauge value" {
  source "$LIB"
  metrics_init
  metric_set "walter_council_agent_state" 'agent="researcher"' 1
  grep -q 'walter_council_agent_state{agent="researcher"} 1' "$WALTER_METRICS_FILE"
}

@test "metric_set overwrites previous value" {
  source "$LIB"
  metrics_init
  metric_set "walter_council_agent_state" 'agent="researcher"' 1
  metric_set "walter_council_agent_state" 'agent="researcher"' 0
  grep -q 'walter_council_agent_state{agent="researcher"} 0' "$WALTER_METRICS_FILE"
  # Should NOT have value 1 anymore for this label
  ! grep -q 'walter_council_agent_state{agent="researcher"} 1' "$WALTER_METRICS_FILE"
}

@test "metrics file persists after sourcing in a new subshell (AC-3)" {
  source "$LIB"
  metrics_init
  metric_inc "walter_council_tasks_total" 'agent="coder",result="success"' 1
  # Verify file exists independently of the current shell
  bash -c "grep -q 'walter_council_tasks_total' '$WALTER_METRICS_FILE'"
}

@test "metrics_init is idempotent — running twice does not corrupt" {
  source "$LIB"
  metrics_init
  metric_inc "walter_council_tasks_total" 'agent="janitor",result="success"' 3
  metrics_init  # second call should not reset existing values
  grep -q 'walter_council_tasks_total{agent="janitor",result="success"} 3' "$WALTER_METRICS_FILE"
}

@test "_metrics_lock propagates flock failure when lock is held (AC-2 Improvement 1)" {
  # macOS ships without flock; only run this test when flock is available.
  command -v flock >/dev/null 2>&1 || skip "flock not available on this system"
  source "$LIB"

  # Hold the lock for 10 seconds in a background process.
  local lock_file="$WALTER_METRICS_FILE.lock"
  _metrics_ensure_dir
  touch "$lock_file"
  (
    exec 200>"$lock_file"
    flock -x 200
    sleep 10
  ) &
  LOCK_PID=$!
  # Give the background process time to acquire the lock.
  sleep 0.5

  # _metrics_lock should now fail (5s timeout, but lock held for 10s)
  run bash -c "
    export WALTER_METRICS_FILE='$WALTER_METRICS_FILE'
    export WALTER_METRICS_LOCK='$lock_file'
    source '$LIB'
    _metrics_lock echo locked
  "
  kill "$LOCK_PID" 2>/dev/null || true

  # Exit code must be non-zero (flock failed to acquire within 5s)
  [[ "$status" -ne 0 ]]
  [[ "$output" =~ "failed to acquire lock within 5s" ]]
}

# ---- F1: metrics file permissions ----

@test "metrics_init creates file with 644 permissions (world-readable for node-exporter)" {
  source "$LIB"
  metrics_init
  [[ -f "$WALTER_METRICS_FILE" ]]
  # stat -f on macOS, stat -c on Linux
  if stat --version 2>/dev/null | grep -q GNU; then
    perms=$(stat -c '%a' "$WALTER_METRICS_FILE")
  else
    perms=$(stat -f '%A' "$WALTER_METRICS_FILE")
  fi
  # Must be 644 or more permissive (e.g. 664, 666)
  [[ "$perms" == "644" || "$perms" == "664" || "$perms" == "666" ]]
}

# ---- F5: WALTER_METRICS_LOCK env override ----

@test "WALTER_METRICS_LOCK env var is respected when set before source" {
  export WALTER_METRICS_LOCK="/tmp/custom-test-$$.lock"
  source "$LIB"
  # After sourcing, WALTER_METRICS_LOCK must still equal our custom value (not overwritten)
  [[ "$WALTER_METRICS_LOCK" == "/tmp/custom-test-$$.lock" ]]
  rm -f "/tmp/custom-test-$$.lock"
}
