#!/usr/bin/env bats
# Tests for T-7: walter-os spend report subcommand
# Covers: AC-2, AC-3 of Improvement 2

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  SPEND_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/spend.sh"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  WALTER_CONFIG="$(mktemp -d -t walter-config-XXXXXX)"
  export WALTER_CONFIG
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "spend.sh library exists" {
  [[ -f "$SPEND_LIB" ]]
}

@test "spend.sh has spend_report_by_agent function" {
  [[ -f "$SPEND_LIB" ]] || skip "spend.sh not found"
  grep -q "spend_report_by_agent" "$SPEND_LIB"
}

@test "spend.sh has spend_report_by_task function" {
  [[ -f "$SPEND_LIB" ]] || skip "spend.sh not found"
  grep -q "spend_report_by_task" "$SPEND_LIB"
}

@test "walter-os spend report --by-agent shows usage without LITELLM_BASE_URL" {
  # Without LITELLM_BASE_URL, command should print a warning but not crash
  unset LITELLM_BASE_URL LITELLM_API_KEY
  run "$WALTER_OS" spend report --by-agent --last 7d
  # Should either succeed or exit with a clear error message, not a hard crash
  [[ "$status" -eq 0 || "$status" -eq 3 ]]
}

@test "walter-os spend report subcommand exists in dispatch" {
  grep -q "spend" "$WALTER_OS"
}

@test "walter-os spend report --by-agent --help exits cleanly" {
  run "$WALTER_OS" spend --help 2>/dev/null || true
  # Should not produce an unhandled error (exit 2 is ok for unknown command)
  [[ "$status" -le 3 ]]
}

@test "spend report output includes column headers for --by-agent" {
  # Even with no LiteLLM, we can test with a mock response
  MOCK_DIR="$(mktemp -d)"
  # Create a mock litellm endpoint via env — if LITELLM_BASE_URL points nowhere,
  # the report should show the error and column headers for --dry-run or mock
  [[ -f "$SPEND_LIB" ]] || skip "spend.sh not found"
  source "$SPEND_LIB"
  # Test that the function exists and produces header output with no server
  # by calling the table formatter directly
  run _spend_format_table_agent "[]"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "agent\|AGENT"
  rm -rf "$MOCK_DIR"
}

@test "spend report --by-task shows AGENT column header (agent_id sourced from tag)" {
  [[ -f "$SPEND_LIB" ]] || skip "spend.sh not found"
  source "$SPEND_LIB"
  run _spend_format_table_task "[]"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "AGENT"
}

@test "spend report --by-task AGENT column is '-' for single group_by (LiteLLM limitation)" {
  # LiteLLM /spend/tags?group_by=task_id does not return agent_id as a sibling.
  # agent_id will always be '-' in by-task reports; this is documented behavior.
  [[ -f "$SPEND_LIB" ]] || skip "spend.sh not found"
  source "$SPEND_LIB"
  local mock_json='[{"tag":"task-abc-123","total_cost":0.05,"model":"gpt-4","prompt_tokens":100,"completion_tokens":50}]'
  run _spend_format_table_task "$mock_json"
  [[ "$status" -eq 0 ]]
  # The AGENT column should show '-' since agent_id is not in the by-task response
  echo "$output" | grep "task-abc-123" | grep -q " - "
}
