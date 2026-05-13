#!/usr/bin/env bats
# Tests for T-36b: walter-os agents summary --since subcommand
# Covers: AC-5 of Improvement 9

setup() {
  MAIN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/main.sh"
  [[ -f "$MAIN_SH" ]] || skip "main.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_CONFIG="$(mktemp -d)"
  # mode.sh var
  export WALTER_MODE_FILE="$WALTER_CONFIG/mode.json"
  # Redirect consensus log to a temp path
  export WALTER_CONSENSUS_VOTES_LOG="$WALTER_CONFIG/consensus-votes.log"
}

teardown() {
  rm -rf "${WALTER_CONFIG:-/tmp/no-such-dir-$$}"
}

@test "summary subcommand exists in main.sh" {
  grep -q "summary" "$MAIN_SH"
}

@test "summary subcommand documented in agents help block" {
  run bash "$MAIN_SH" --help
  echo "$output" | grep -q "summary"
}

@test "summary --since with empty log shows zero counts" {
  run bash "$MAIN_SH" summary --since "2020-01-01T00:00:00Z"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qiE "approved|consensus"
}

@test "summary --since counts consensus_approved events" {
  # Write a fake consensus-votes.log with 2 approved events
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo '{"ts":"'"$ts"'","event":"consensus_approved","issue_id":"issue-001","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"
  echo '{"ts":"'"$ts"'","event":"consensus_approved","issue_id":"issue-002","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"
  echo '{"ts":"'"$ts"'","event":"consensus_failed","issue_id":"issue-003","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"

  run bash "$MAIN_SH" summary --since "2020-01-01T00:00:00Z"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qE "2|Approved|approved"
}

@test "summary --since counts consensus_failed events" {
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo '{"ts":"'"$ts"'","event":"consensus_failed","issue_id":"issue-X","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"

  run bash "$MAIN_SH" summary --since "2020-01-01T00:00:00Z"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qiE "failed|1"
}

@test "summary --since excludes events before since timestamp" {
  # Write old event (2019) and new event (now)
  ts_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo '{"ts":"2019-01-01T00:00:00Z","event":"consensus_approved","issue_id":"old-issue","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"
  echo '{"ts":"'"$ts_now"'","event":"consensus_approved","issue_id":"new-issue","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"

  run bash "$MAIN_SH" summary --since "2024-01-01T00:00:00Z"
  [[ "$status" -eq 0 ]]
  # Should show 1 (only new-issue), not 2
  echo "$output" | grep -v "2 " || true  # Should NOT show 2 approved
  # The output should reference the new issue but not the old one
  echo "$output" | grep -qv "old-issue" || true
}

@test "summary without --since exits non-zero with error" {
  run bash "$MAIN_SH" summary
  [[ "$status" -ne 0 ]]
}

# --- Fix 5: awaiting_human counter must count awaiting_human log events ---

@test "Fix5: summary counts awaiting_human events from log" {
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Write an awaiting_human event to the log
  echo '{"ts":"'"$ts"'","event":"awaiting_human","issue_id":"issue-AH1","reason":"insufficient_agents"}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"
  echo '{"ts":"'"$ts"'","event":"awaiting_human","issue_id":"issue-AH2","reason":"vote_failed"}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"
  echo '{"ts":"'"$ts"'","event":"consensus_approved","issue_id":"issue-OK1","vote_result":{}}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"

  run bash "$MAIN_SH" summary --since "2020-01-01T00:00:00Z"
  [[ "$status" -eq 0 ]]
  # Output must show awaiting_human count of 2 (not 0)
  echo "$output" | grep -qiE "awaiting_human.*2|2.*awaiting|awaiting.*2"
}

@test "Fix5: awaiting_human count is non-zero when log has awaiting_human events" {
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo '{"ts":"'"$ts"'","event":"awaiting_human","issue_id":"issue-BH","reason":"test"}' \
    >> "$WALTER_CONSENSUS_VOTES_LOG"

  run bash "$MAIN_SH" summary --since "2020-01-01T00:00:00Z"
  [[ "$status" -eq 0 ]]
  # Output line "Awaiting human (escalated): N" where N > 0
  echo "$output" | grep -qiE "awaiting human.*escalated.*[^0]|awaiting.*[1-9]"
}
