#!/usr/bin/env bats
# Tests for T-35: plane.sh state machine extension — awaiting-consensus + awaiting-human
# Covers: AC-2, AC-3 of Improvement 9

setup() {
  LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/plane.sh"
  [[ -f "$LIB" ]] || skip "plane.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

@test "plane.sh declares plane_issue_set_state_consensus" {
  source "$LIB"
  declare -f plane_issue_set_state_consensus >/dev/null
}

@test "plane.sh declares plane_issue_set_state_awaiting_human" {
  source "$LIB"
  declare -f plane_issue_set_state_awaiting_human >/dev/null
}

@test "plane_issue_set_state_consensus fails if Plane env missing" {
  source "$LIB"
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT
  run plane_issue_set_state_consensus "test-id" '{"quorum_met":true,"yes":2,"no":1}'
  [[ "$status" -ne 0 ]]
}

@test "plane_issue_set_state_awaiting_human fails if Plane env missing" {
  source "$LIB"
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT
  run plane_issue_set_state_awaiting_human "test-id" '{"quorum_met":false}'
  [[ "$status" -ne 0 ]]
}

@test "states.md documents awaiting-consensus and awaiting-human states" {
  STATES_DOC="$BATS_TEST_DIRNAME/../../setup/plane/states.md"
  [[ -f "$STATES_DOC" ]]
  grep -q "awaiting-consensus" "$STATES_DOC"
  grep -q "awaiting-human" "$STATES_DOC"
}

@test "T1: voter_summary uses printf not literal backslash-n in string concat" {
  # Bug: voter_summary="\${voter_summary}\n- ..." in double-quotes produces literal \n.
  # Fix: use printf -v or $'\\n' so the Plane comment contains real newlines.
  # Static check: the literal-\n form must not appear in the voter_summary line.
  if grep -qF '"${voter_summary}\n-' "$LIB" || grep -qF '"$voter_summary\n-' "$LIB"; then
    echo "FAIL: literal \\n found in voter_summary concatenation" >&2
    return 1
  fi
  return 0
}
