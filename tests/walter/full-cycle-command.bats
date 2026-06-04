#!/usr/bin/env bats
# tests/walter/full-cycle-command.bats
#
# Covers issue #228 / AD-3 - the /full-cycle orchestrator entry.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
COMMAND_FILE="${REPO_ROOT}/commands/full-cycle.md"

@test "full-cycle command has valid slash-command frontmatter" {
  [[ -f "$COMMAND_FILE" ]]
  grep -q '^description:' "$COMMAND_FILE"
  grep -q '^argument-hint: <idea>$' "$COMMAND_FILE"
}

@test "full-cycle command accepts the operator idea as ARGUMENTS" {
  grep -q '\$ARGUMENTS' "$COMMAND_FILE"
  grep -q 'full-cycle <idea>' "$COMMAND_FILE"
}

@test "full-cycle command drives the governed delivery sequence" {
  grep -q '/brainstorm' "$COMMAND_FILE"
  grep -q '/write-plan' "$COMMAND_FILE"
  grep -q '/execute-plan' "$COMMAND_FILE"
  grep -q '/pr' "$COMMAND_FILE"
}

@test "full-cycle command uses the feature-state ledger" {
  grep -q 'walter-os feature-state init' "$COMMAND_FILE"
  grep -q 'walter-os feature-state validate' "$COMMAND_FILE"
  grep -q 'docs/specs/feature-state-ledger.md' "$COMMAND_FILE"
}

@test "full-cycle command preserves human gates and hard-limit floor" {
  grep -qi 'intent' "$COMMAND_FILE"
  grep -qi 'architecture' "$COMMAND_FILE"
  grep -qi 'merge' "$COMMAND_FILE"
  grep -qi 'production deploy' "$COMMAND_FILE"
  grep -qi 'hard-limit floor' "$COMMAND_FILE"
  grep -qi 'non-overridable' "$COMMAND_FILE"
}

@test "full-cycle command references the roadmap and orchestrator decision" {
  grep -q 'docs/specs/autonomous-delivery-roadmap.md' "$COMMAND_FILE"
  grep -q 'docs/decisions/0025-delivery-orchestrator-agent.md' "$COMMAND_FILE"
}

@test "full-cycle command does not authorize protected-branch merge commands" {
  [[ -f "$COMMAND_FILE" ]]
  ! grep -Eq 'gh pr merge|git push origin (main|master|staging|production)' "$COMMAND_FILE"
}
