#!/usr/bin/env bats
# Tests for T-34: Consensus eligibility check in approval-gate.sh
# Covers: AC-4 of Improvement 9

setup() {
  HOOK="$BATS_TEST_DIRNAME/../../hooks/approval-gate.sh"
  [[ -x "$HOOK" ]] || skip "approval-gate.sh not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-consensus-elig-XXXXXX)"
  export WALTER_AGENT_PLANE_ISSUE="test-issue-123"
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT
  export WALTER_AGENT_NAME=coder

  # Enable consensus mode
  cat > "$WALTER_CONFIG/mode.json" <<'MODE'
{"consensus": true, "since": "2026-05-11T00:00:00Z", "voting_threshold": 3}
MODE
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "approval-gate returns exit 8 for lint-fix category in consensus mode" {
  # Use a command that is always blocked (git reset --hard) with --category lint-fix
  # so it goes through the blocked path and then consensus-eligible check.
  # consensus ON + eligible category + blocked command → exit 8 (not 0, not 7).
  run "$HOOK" check "git reset --hard HEAD~1" --tool Bash --category lint-fix
  # Exit 8 means awaiting-consensus
  [[ "$status" -eq 8 ]]
}

@test "approval-gate consensus-eligible categories are not blocked for always-block ops" {
  # prod-db-migration is consensus-INELIGIBLE: a blocked command with this category
  # must exit 7 (human required), never exit 8 (awaiting-consensus).
  # Use git reset --hard which is always blocked, with --category prod-db-migration.
  run "$HOOK" check "git reset --hard HEAD~1" --tool Bash --category prod-db-migration
  # Must be exactly exit 7 — DB migrations always require human, never council.
  [[ "$status" -eq 7 ]]
}

@test "approval-gate has consensus_eligible function" {
  grep -q "consensus_eligible\|consensus-eligible\|eligible.*lint\|CONSENSUS_ELIGIBLE" "$HOOK"
}

@test "approval-gate exit code 8 is defined in documentation header" {
  grep -q "exit.*8\|8.*consensus\|awaiting.consensus" "$HOOK"
}

@test "consensus mode off: eligible categories return normal block (7)" {
  # Turn off consensus mode
  cat > "$WALTER_CONFIG/mode.json" <<'MODE'
{"consensus": false, "since": "2026-05-11T00:00:00Z", "voting_threshold": 3}
MODE
  # A command that would be blocked by pattern in normal mode
  # With consensus OFF, must NOT return 8
  run "$HOOK" check "git push origin feature/test" --tool Bash
  [[ "$status" -ne 8 ]]
}

# --- Fix 2: Panic lock beats consensus invariant tests ---

@test "Fix2: panic lock beats consensus mode ON — exit 7 not 8 for eligible category" {
  # Setup: panic lock active + consensus ON
  printf '%s\npanic test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  cat > "$WALTER_CONFIG/mode.json" <<'EOF'
{"consensus": true, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
EOF
  export WALTER_AGENT_NAME=reviewer  # high tier (trust doesn't bypass panic)

  # lint-fix is consensus-eligible but panic lock must win
  run "$HOOK" check "git push origin feature/x" --tool Bash --category lint-fix
  # Must be exit 7 (panic block), NOT exit 8 (consensus)
  [ "$status" -eq 7 ]
  [[ "$output" =~ panic ]] || [[ "$output" =~ lock ]] || [[ "$output" =~ BLOCK ]]
}

@test "Fix2: panic lock + high-tier reviewer still blocked — panic is terminal" {
  printf '%s\npanic\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  export WALTER_AGENT_NAME=reviewer

  run "$HOOK" check "git push origin feature/x" --tool Bash
  [ "$status" -eq 7 ]
}

@test "Fix2: no panic + consensus ON + eligible category — exit 8 not 0 or 7" {
  # No lock file
  rm -f "$WALTER_CONFIG/gate.lock"
  cat > "$WALTER_CONFIG/mode.json" <<'EOF'
{"consensus": true, "since": "2026-01-01T00:00:00Z", "voting_threshold": 3}
EOF
  # Use a command that always blocks (git reset --hard matches BLOCK_BASH_PATTERNS),
  # but override the category to lint-fix which IS consensus-eligible.
  # Result: blocked command + consensus ON + eligible category → exit 8.
  export WALTER_AGENT_NAME=coder

  run "$HOOK" check "git reset --hard HEAD~1" --tool Bash --category lint-fix
  [ "$status" -eq 8 ]
}
