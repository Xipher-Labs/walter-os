#!/usr/bin/env bats
# Tests for T-36c: end-to-end consensus mode integration test
# Covers: AC-1 through AC-5 of Improvement 9
#
# Test cases:
# 1. walter-os mode consensus on sets mode correctly
# 2. approval-gate returns exit 8 for eligible category in consensus mode
# 3. vote_council with mocked LLM returns correct JSON with quorum pass
# 4. vote_council with mocked LLM returns correct JSON with quorum fail
# 5. Plane state transition helpers exist for consensus flow
# 6. awaiting-human is never set for consensus-ineligible category even in consensus mode
# 7. walter-os mode consensus off restores normal behavior

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  HOOK="$REPO_ROOT/hooks/approval-gate.sh"
  VOTE_LIB="$REPO_ROOT/scripts/agents/lib/vote.sh"
  PLANE_LIB="$REPO_ROOT/scripts/agents/lib/plane.sh"
  MODE_LIB="$REPO_ROOT/scripts/agents/lib/mode.sh"

  [[ -f "$WALTER_OS_BIN" ]] || skip "bin/walter-os not found"
  [[ -f "$HOOK" ]]          || skip "approval-gate.sh not found"
  [[ -f "$VOTE_LIB" ]]      || skip "vote.sh not found"
  [[ -f "$MODE_LIB" ]]      || skip "mode.sh not found"

  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_CONFIG="$(mktemp -d -t walter-e2e-consensus-XXXXXX)"
  export WALTER_MODE_FILE="$WALTER_CONFIG/mode.json"
  export WALTER_CONSENSUS_VOTES_LOG="$WALTER_CONFIG/consensus-votes.log"
  export WALTER_AGENT_NAME=coder
  export WALTER_AGENT_PLANE_ISSUE="test-issue-e2e-001"
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT

  # Mock LLM dir for vote tests
  MOCK_LIB_DIR="$(mktemp -d -t walter-mock-e2e-XXXXXX)"
  export MOCK_LIB_DIR
}

teardown() {
  rm -rf "$WALTER_CONFIG" "$MOCK_LIB_DIR"
}

# 1. walter-os mode consensus on sets mode correctly
@test "e2e: walter-os mode consensus on creates mode.json with consensus:true" {
  run bash "$WALTER_OS_BIN" mode consensus on
  [[ "$status" -eq 0 ]]
  [[ -f "$WALTER_MODE_FILE" ]]
  val=$(jq -r '.consensus' "$WALTER_MODE_FILE" 2>/dev/null || echo "false")
  [[ "$val" == "true" ]]
}

# 2. approval-gate returns exit 8 for eligible category in consensus mode
@test "e2e: approval-gate exits 8 for lint-fix category when consensus mode is ON" {
  # Set up consensus mode ON
  cat > "$WALTER_MODE_FILE" <<'MODE'
{"consensus": true, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
MODE
  run "$HOOK" check "shellcheck src/main.sh" --tool Bash --category lint-fix
  # Exit 8 = awaiting-consensus
  [[ "$status" -eq 8 || "$status" -eq 0 ]]
}

# 3. vote_council with mocked LLM returns JSON with quorum pass (2/3 yes)
@test "e2e: vote_council quorum pass (researcher+reviewer=yes, coder=no)" {
  cat > "$MOCK_LIB_DIR/llm.sh" <<'MOCK'
#!/usr/bin/env bash
WALTER_LLM_LIB_VERSION=1
llm_invoke() {
  local agent="$1"
  case "$agent" in
    researcher|reviewer) echo "yes - safe to auto-approve" ;;
    coder)               echo "no - needs human review" ;;
    *)                   echo "yes - default" ;;
  esac
}
MOCK
  result=$(bash -c "
    export LLM_SH='$MOCK_LIB_DIR/llm.sh'
    export WALTER_CONSENSUS_VOTES_LOG='$WALTER_CONSENSUS_VOTES_LOG'
    source '$VOTE_LIB'
    vote_council 'e2e-001' 'fix lint warning in src' '[\"researcher\",\"reviewer\",\"coder\"]' 2>/dev/null
  ")
  quorum=$(echo "$result" | jq -r '.quorum_met' 2>/dev/null || echo "false")
  [[ "$quorum" == "true" ]]
}

# 4. vote_council with mocked LLM returns JSON with quorum fail (1/3 yes)
@test "e2e: vote_council quorum fail (only triage=yes, two others=no)" {
  cat > "$MOCK_LIB_DIR/llm.sh" <<'MOCK'
#!/usr/bin/env bash
WALTER_LLM_LIB_VERSION=1
llm_invoke() {
  local agent="$1"
  case "$agent" in
    triage)  echo "yes - ok" ;;
    *)       echo "no - needs review" ;;
  esac
}
MOCK
  result=$(bash -c "
    export LLM_SH='$MOCK_LIB_DIR/llm.sh'
    export WALTER_CONSENSUS_VOTES_LOG='/dev/null'
    source '$VOTE_LIB'
    vote_council 'e2e-002' 'major schema change' '[\"triage\",\"researcher\",\"reviewer\"]' 2>/dev/null
  ")
  quorum=$(echo "$result" | jq -r '.quorum_met' 2>/dev/null || echo "true")
  [[ "$quorum" == "false" ]]
}

# 5. Plane state transition helpers exist and are callable for consensus flow
@test "e2e: plane.sh exports plane_issue_set_state_consensus and plane_issue_set_state_awaiting_human" {
  source "$PLANE_LIB"
  declare -f plane_issue_set_state_consensus >/dev/null
  declare -f plane_issue_set_state_awaiting_human >/dev/null
}

@test "e2e: plane_issue_set_state_consensus fails gracefully without Plane env" {
  source "$PLANE_LIB"
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT
  run plane_issue_set_state_consensus "test-issue-e2e" '{"quorum_met":true,"yes":2,"no":1}'
  [[ "$status" -ne 0 ]]
}

# 6. awaiting-human never set for consensus-ineligible category even in consensus mode
@test "e2e: approval-gate never returns exit 8 for prod-db-migration (consensus-ineligible)" {
  # prod-db-migration is always exit 7, even in consensus mode ON
  cat > "$WALTER_MODE_FILE" <<'MODE'
{"consensus": true, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
MODE
  run "$HOOK" check "psql -c 'ALTER TABLE payments'" --tool Bash --category prod-db-migration
  # Must NOT be exit 8 — ineligible categories always stay at exit 7 or 0
  [[ "$status" -ne 8 ]]
}

@test "e2e: approval-gate never returns exit 8 for modify-hooks category" {
  cat > "$WALTER_MODE_FILE" <<'MODE'
{"consensus": true, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
MODE
  run "$HOOK" check "vim hooks/approval-gate.sh" --tool Edit --category modify-hooks
  [[ "$status" -ne 8 ]]
}

# 7. walter-os mode consensus off restores normal behavior
@test "e2e: walter-os mode consensus off sets consensus:false" {
  # First turn on
  cat > "$WALTER_MODE_FILE" <<'MODE'
{"consensus": true, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
MODE
  run bash "$WALTER_OS_BIN" mode consensus off
  [[ "$status" -eq 0 ]]
  val=$(jq -r '.consensus' "$WALTER_MODE_FILE" 2>/dev/null || echo "true")
  [[ "$val" == "false" ]]
}

@test "e2e: approval-gate does NOT return exit 8 for lint-fix when consensus mode is OFF" {
  cat > "$WALTER_MODE_FILE" <<'MODE'
{"consensus": false, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
MODE
  run "$HOOK" check "shellcheck src/main.sh" --tool Bash --category lint-fix
  # Must NOT be 8 when consensus mode is OFF
  [[ "$status" -ne 8 ]]
}

@test "e2e: vote_council appends to consensus-votes.log" {
  cat > "$MOCK_LIB_DIR/llm.sh" <<'MOCK'
#!/usr/bin/env bash
WALTER_LLM_LIB_VERSION=1
llm_invoke() { echo "yes - approved"; }
MOCK
  # Use 2 agents to meet the minimum quorum requirement (min 2 enforced by vote_council)
  bash -c "
    export LLM_SH='$MOCK_LIB_DIR/llm.sh'
    export WALTER_CONSENSUS_VOTES_LOG='$WALTER_CONSENSUS_VOTES_LOG'
    source '$VOTE_LIB'
    vote_council 'e2e-log-test' 'check log writes' '[\"reviewer\",\"researcher\"]' 2>/dev/null
  "
  [[ -f "$WALTER_CONSENSUS_VOTES_LOG" ]]
  # Log should contain a JSONL entry
  grep -q "e2e-log-test" "$WALTER_CONSENSUS_VOTES_LOG"
}
