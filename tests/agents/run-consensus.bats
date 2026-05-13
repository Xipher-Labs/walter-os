#!/usr/bin/env bats
# Tests for T-36: consensus vote trigger in agent runner (run.sh)
# Covers: AC-2, AC-3 of Improvement 9

setup() {
  RUN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/run.sh"
  [[ -f "$RUN_SH" ]] || skip "run.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

@test "run.sh sources vote.sh" {
  grep -q "source.*vote.sh\|source.*lib/vote\|\. .*vote" "$RUN_SH"
}

@test "run.sh handles approval-gate exit 8 (awaiting-consensus)" {
  grep -q "exit.*8\|\"8\"\|rc.*8\|\[\[ .*8 " "$RUN_SH" || \
  grep -q "awaiting.consensus\|AWAITING_CONSENSUS\|exit_8\|8.*consensus" "$RUN_SH"
}

@test "run.sh calls vote_council when gate returns 8" {
  grep -q "vote_council" "$RUN_SH"
}

@test "run.sh logs consensus vote to consensus-votes.log" {
  grep -q "consensus.votes.log\|CONSENSUS_VOTES_LOG\|consensus_votes" "$RUN_SH"
}
