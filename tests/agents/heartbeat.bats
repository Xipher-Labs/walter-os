#!/usr/bin/env bats
# Tests for scripts/agents/lib/heartbeat.sh
# Covers: T-18 [AC-1, AC-4 of Improvement 5]

setup() {
  LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/heartbeat.sh"
  [[ -f "$LIB" ]] || skip "heartbeat.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  HEARTBEAT_DIR="$(mktemp -d -t walter-heartbeat-test-XXXXXX)"
  export WALTER_HEARTBEAT_DIR="$HEARTBEAT_DIR"
}

teardown() {
  rm -rf "$HEARTBEAT_DIR"
}

# ---- heartbeat_write ----

@test "heartbeat_write creates the heartbeat file" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "fetch_issue"
  [[ -f "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat" ]]
}

@test "heartbeat_write appends JSONL line with ts + agent + issue_id + step" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "analyze"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat")
  echo "$line" | jq -e '.ts' >/dev/null
  echo "$line" | jq -e '.agent == "coder"' >/dev/null
  echo "$line" | jq -e '.issue_id == "issue-123"' >/dev/null
  echo "$line" | jq -e '.step == "analyze"' >/dev/null
}

@test "heartbeat_write second call appends a second line" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "step_a"
  heartbeat_write "coder" "issue-123" "step_b"
  local count
  count=$(wc -l < "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat")
  [[ "$count" -eq 2 ]]
}

@test "heartbeat_write with status=done includes status field" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "final" "done"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat")
  echo "$line" | jq -e '.status == "done"' >/dev/null
}

@test "heartbeat_write with status=failed includes status field" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "final" "failed"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat")
  echo "$line" | jq -e '.status == "failed"' >/dev/null
}

# ---- heartbeat_read_last ----

@test "heartbeat_read_last returns last JSONL line" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "step_a"
  heartbeat_write "coder" "issue-123" "step_b"
  local last
  last=$(heartbeat_read_last "coder" "issue-123")
  echo "$last" | jq -e '.step == "step_b"' >/dev/null
}

@test "heartbeat_read_last returns empty when no file" {
  source "$LIB"
  local last
  last=$(heartbeat_read_last "coder" "no-such-issue")
  [[ -z "$last" ]]
}

# ---- heartbeat_checkpoint_steps ----

@test "heartbeat_checkpoint_steps appends completed_steps array" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "running"
  heartbeat_checkpoint_steps "coder" "issue-123" "fetch_issue"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat")
  echo "$line" | jq -e '.completed_steps | index("fetch_issue") != null' >/dev/null
}

@test "heartbeat_checkpoint_steps accumulates multiple steps" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "running"
  heartbeat_checkpoint_steps "coder" "issue-123" "fetch_issue"
  heartbeat_checkpoint_steps "coder" "issue-123" "analyze"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-123.heartbeat")
  echo "$line" | jq -e '.completed_steps | index("fetch_issue") != null' >/dev/null
  echo "$line" | jq -e '.completed_steps | index("analyze") != null' >/dev/null
}

# ---- heartbeat_read_checkpoint ----

@test "heartbeat_read_checkpoint returns completed_steps from last heartbeat" {
  source "$LIB"
  heartbeat_write "coder" "issue-123" "running"
  heartbeat_checkpoint_steps "coder" "issue-123" "fetch_issue"
  heartbeat_checkpoint_steps "coder" "issue-123" "analyze"
  local steps
  steps=$(heartbeat_read_checkpoint "coder" "issue-123")
  echo "$steps" | jq -e '. | index("fetch_issue") != null' >/dev/null
  echo "$steps" | jq -e '. | index("analyze") != null' >/dev/null
}

@test "heartbeat_read_checkpoint returns empty array when no heartbeat file" {
  source "$LIB"
  local steps
  steps=$(heartbeat_read_checkpoint "coder" "no-such-issue")
  [[ "$steps" == "[]" || -z "$steps" ]]
}

# ---- heartbeat_dead_threshold ----

@test "heartbeat_dead_threshold returns 1800 by default" {
  source "$LIB"
  local threshold
  threshold=$(heartbeat_dead_threshold)
  [[ "$threshold" -eq 1800 ]]
}

@test "heartbeat_dead_threshold respects WALTER_HEARTBEAT_DEAD_THRESHOLD env var" {
  source "$LIB"
  export WALTER_HEARTBEAT_DEAD_THRESHOLD=900
  local threshold
  threshold=$(heartbeat_dead_threshold)
  [[ "$threshold" -eq 900 ]]
  unset WALTER_HEARTBEAT_DEAD_THRESHOLD
}

# ---- Fix 3: stub fields files_touched + tests_run (M-AC4 partial) ----

@test "heartbeat_write includes files_touched stub field (always empty array)" {
  source "$LIB"
  heartbeat_write "coder" "issue-stub" "working"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-stub.heartbeat")
  echo "$line" | jq -e '.files_touched == []' >/dev/null
}

@test "heartbeat_write includes tests_run stub field (always 0)" {
  source "$LIB"
  heartbeat_write "coder" "issue-stub" "working"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-stub.heartbeat")
  echo "$line" | jq -e '.tests_run == 0' >/dev/null
}

# ---- R4: heartbeat_checkpoint_steps must include step field ----

@test "R4: heartbeat_checkpoint_steps includes step field in entry" {
  source "$LIB"
  heartbeat_write "coder" "issue-r4" "running"
  heartbeat_checkpoint_steps "coder" "issue-r4" "analyze_issue"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-r4.heartbeat")
  # step field must be present so watchdog doesn't read "unknown"
  echo "$line" | jq -e '.step' >/dev/null
  echo "$line" | jq -e '.step == "analyze_issue"' >/dev/null
}

@test "R4: heartbeat_checkpoint_steps entry has schema-consistent stub fields" {
  source "$LIB"
  heartbeat_write "coder" "issue-r4b" "running"
  heartbeat_checkpoint_steps "coder" "issue-r4b" "fetch"
  local line
  line=$(tail -1 "$WALTER_HEARTBEAT_DIR/coder/issue-r4b.heartbeat")
  # Must include files_touched and tests_run for schema consistency with heartbeat_write
  echo "$line" | jq -e '.files_touched == []' >/dev/null
  echo "$line" | jq -e '.tests_run == 0' >/dev/null
}
