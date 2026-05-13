#!/usr/bin/env bats
# Tests for T-5: walter-os status metrics integration
# Covers: AC-4 of Improvement 1

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"

  # Isolated env
  WALTER_METRICS_DIR="$(mktemp -d -t walter-status-test-XXXXXX)"
  export WALTER_METRICS_DIR
  export WALTER_METRICS_FILE="$WALTER_METRICS_DIR/metrics.prom"
  export WALTER_METRICS_LOCK="$WALTER_METRICS_FILE.lock"
  WALTER_CONFIG="$(mktemp -d -t walter-config-XXXXXX)"
  export WALTER_CONFIG
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
}

teardown() {
  rm -rf "$WALTER_METRICS_DIR" "$WALTER_CONFIG"
}

@test "walter-os status omits Council section when metrics file absent" {
  # No metrics.prom file → no Council section
  run "$WALTER_OS" status
  [[ "$status" -eq 0 ]]
  # Should NOT print "Council (today)" when file missing
  ! echo "$output" | grep -q "Council (today)"
}

@test "walter-os status shows Council section when metrics file present" {
  # Create a metrics file with sample data
  mkdir -p "$WALTER_METRICS_DIR"
  cat > "$WALTER_METRICS_FILE" <<'EOF'
# HELP walter_council_tasks_total Tasks completed
# TYPE walter_council_tasks_total counter
walter_council_tasks_total{agent="coder",result="success"} 3
walter_council_tasks_total{agent="researcher",result="failed"} 1
# HELP walter_council_tokens_total Tokens consumed
# TYPE walter_council_tokens_total counter
walter_council_tokens_total{agent="coder",model="sonnet"} 12500
# HELP walter_council_agent_state Current agent state
# TYPE walter_council_agent_state gauge
walter_council_agent_state{agent="coder"} 0
walter_council_agent_state{agent="researcher"} 1
EOF

  run "$WALTER_OS" status
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "Council (today)"
}

@test "walter-os status Council section shows tasks_completed count" {
  mkdir -p "$WALTER_METRICS_DIR"
  cat > "$WALTER_METRICS_FILE" <<'EOF'
walter_council_tasks_total{agent="coder",result="success"} 5
walter_council_tasks_total{agent="janitor",result="success"} 2
walter_council_tasks_total{agent="coder",result="failed"} 1
EOF

  run "$WALTER_OS" status
  echo "$output" | grep -q "tasks_completed"
}

@test "walter-os status Council section shows agents_working count" {
  mkdir -p "$WALTER_METRICS_DIR"
  cat > "$WALTER_METRICS_FILE" <<'EOF'
walter_council_agent_state{agent="coder"} 1
walter_council_agent_state{agent="researcher"} 0
walter_council_agent_state{agent="janitor"} 0
EOF

  run "$WALTER_OS" status
  echo "$output" | grep -q "agents_working"
}

@test "walter-os status shows correct tasks_completed sum" {
  mkdir -p "$WALTER_METRICS_DIR"
  cat > "$WALTER_METRICS_FILE" <<'EOF'
walter_council_tasks_total{agent="coder",result="success"} 3
walter_council_tasks_total{agent="researcher",result="success"} 2
EOF

  run "$WALTER_OS" status
  # Total success = 5
  echo "$output" | grep "tasks_completed" | grep -q "5"
}

# ---------- Budget warn — AC-4 Improvement 2 ----------

@test "walter-os status shows budget warn when spend exceeds threshold" {
  # Create spend-status.json with spend > budget
  cat > "$WALTER_CONFIG/spend-status.json" <<'EOF'
{"today_usd": 2.50, "this_month_usd": 55.00, "monthly_budget_usd": 50.00}
EOF

  run "$WALTER_OS" status
  [[ "$status" -eq 0 ]]
  # Must show a warning about budget
  echo "$output" | grep -qi "budget\|warn\|over\|exceed"
  # The warning should be visually distinct (WARN or ⚠ prefix)
  echo "$output" | grep -qiE "WARN|⚠|budget.*exceed|over.*budget"
}

@test "walter-os status does NOT show budget warn when spend is under threshold" {
  cat > "$WALTER_CONFIG/spend-status.json" <<'EOF'
{"today_usd": 1.00, "this_month_usd": 20.00, "monthly_budget_usd": 50.00}
EOF

  run "$WALTER_OS" status
  [[ "$status" -eq 0 ]]
  # No WARN/exceed message when under budget
  ! echo "$output" | grep -qiE "WARN.*budget|budget.*exceed|over.*budget"
}
