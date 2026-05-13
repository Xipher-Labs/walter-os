#!/usr/bin/env bats
# tests/cli/status.bats
#
# Covers: cmd_status output correctness.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"

export WALTER_OS_HOME="${REPO_ROOT}"

# -----------------------------------------------------------------------
# WARN 2: Council metrics block must appear exactly once in status output.
# Pre-existing bug had the 25-line block duplicated 5×.
# -----------------------------------------------------------------------
@test "cmd_status prints 'Council (today):' exactly once [AC-3]" {
  # Point to a real metrics file so the block fires.
  local tmp_metrics
  tmp_metrics="$(mktemp)"
  # Minimal valid Prometheus textfile content that satisfies the grep patterns.
  cat > "$tmp_metrics" <<'PROM'
walter_council_tasks_total{agent="reviewer",result="success"} 3
walter_council_tasks_total{agent="reviewer",result="failed"} 1
walter_council_tokens_total{agent="reviewer"} 42000
walter_council_agent_state{agent="reviewer"} 0
PROM

  run env \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_METRICS_FILE="${tmp_metrics}" \
    "${WALTER_OS_BIN}" status

  rm -f "$tmp_metrics"

  [ "$status" -eq 0 ]
  # Count occurrences — must be exactly 1
  local count
  count="$(echo "$output" | grep -c "Council (today):")"
  [ "$count" -eq 1 ]
}
