#!/usr/bin/env bats
# Tests for T-17: heartbeat loop integration in scripts/agents/run.sh
# Covers: AC-1 of Improvement 5

setup() {
  RUN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/run.sh"
  HEARTBEAT_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/heartbeat.sh"
  [[ -f "$RUN_SH" ]]         || skip "run.sh not found"
  [[ -f "$HEARTBEAT_LIB" ]]  || skip "heartbeat.sh not found"
}

# Structural tests: verify run.sh sources heartbeat.sh and uses the protocol.

@test "run.sh sources heartbeat.sh library" {
  grep -q "heartbeat\.sh" "$RUN_SH"
}

@test "run.sh calls heartbeat_write on start with working state" {
  grep -q "heartbeat_write" "$RUN_SH"
}

@test "run.sh starts a background heartbeat loop" {
  # The background loop pattern: while sleep ...; do heartbeat_write ...; done &
  grep -qE "while sleep|heartbeat.*&" "$RUN_SH"
}

@test "run.sh kills the heartbeat background process on task end" {
  # Should see a kill of the heartbeat PID variable on exit/completion
  grep -qE "kill.*HEARTBEAT_PID|HEARTBEAT_PID.*kill|kill.*heartbeat" "$RUN_SH"
}

@test "run.sh writes final heartbeat with status=done on success" {
  # On the success path the runner must write a heartbeat with done status.
  grep -qE 'heartbeat_write.*done|heartbeat.*status.*done' "$RUN_SH"
}

@test "run.sh writes final heartbeat with status=failed on failure" {
  grep -qE 'heartbeat_write.*failed|heartbeat.*status.*failed' "$RUN_SH"
}

@test "run.sh sets WALTER_HEARTBEAT_DIR env variable or sources from heartbeat.sh" {
  # Either the runner exports the dir or relies on heartbeat.sh default
  grep -qE "WALTER_HEARTBEAT_DIR|heartbeat\.sh" "$RUN_SH"
}

# ---- Fix 2: checkpoint resume on claim (Phase R AC-4) ----

@test "run.sh calls heartbeat_read_checkpoint after successful claim" {
  # Structural: the code must reference heartbeat_read_checkpoint
  grep -q "heartbeat_read_checkpoint" "$RUN_SH"
}

@test "run.sh posts checkpoint resume comment when completed_steps exist" {
  # Structural: when checkpoint_steps is non-empty, a Plane comment mentioning
  # "Resuming from checkpoint" must be posted.
  grep -q "Resuming from checkpoint" "$RUN_SH"
}

# ---- Fix 8: kill heartbeat on unexpected exit ----

@test "run.sh EXIT trap includes HEARTBEAT_PID kill" {
  # The EXIT trap itself must include the HEARTBEAT_PID kill — not just elsewhere in the file
  grep -qE "trap '.*HEARTBEAT_PID.*kill|trap '.*kill.*HEARTBEAT_PID" "$RUN_SH"
}

@test "R2: heartbeat EXIT trap is set before the claim block (no orphan on claim fail)" {
  # R2: if heartbeat starts before claim, and claim fails with exit, the heartbeat
  # loop must still be killed by an EXIT trap set BEFORE the claim exit path.
  # Verify that the HEARTBEAT_PID kill trap is set BEFORE the claim block.
  local heartbeat_start_line claim_line trap_kill_line
  heartbeat_start_line="$(grep -n 'HEARTBEAT_PID=\$!' "$RUN_SH" | head -1 | cut -d: -f1)"
  claim_line="$(grep -n 'plane_issue_claim' "$RUN_SH" | head -1 | cut -d: -f1)"
  trap_kill_line="$(grep -n 'HEARTBEAT_PID.*kill\|kill.*HEARTBEAT_PID' "$RUN_SH" | \
    grep 'trap' | head -1 | cut -d: -f1)"

  [ -n "$heartbeat_start_line" ]
  [ -n "$claim_line" ]
  [ -n "$trap_kill_line" ]

  # The trap that kills the heartbeat must be set AFTER heartbeat starts but BEFORE claim
  echo "heartbeat_start=$heartbeat_start_line claim=$claim_line trap_kill=$trap_kill_line" >&3
  [ "$trap_kill_line" -gt "$heartbeat_start_line" ]
  [ "$trap_kill_line" -lt "$claim_line" ]
}
