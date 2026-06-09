#!/usr/bin/env bats
# tests/oss/review-loop-policy.bats
# AC-11: AGENTS.md contains the 3-round review-loop policy structure.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
AGENTS="$REPO_ROOT/AGENTS.md"

@test "AGENTS.md has Round 1 label" {
    grep -q "Round 1" "$AGENTS"
}

@test "AGENTS.md has Round 2 label" {
    grep -q "Round 2" "$AGENTS"
}

@test "AGENTS.md has Round 3 label" {
    grep -q "Round 3" "$AGENTS"
}

@test "AGENTS.md references Codex CLI" {
    grep -q "Codex CLI" "$AGENTS"
}

@test "AGENTS.md has Copilot REST snippet" {
    grep -q "copilot-pull-request-reviewer" "$AGENTS"
}

@test "AGENTS.md has codex-minimal bypass pattern" {
    grep -q "codex-minimal" "$AGENTS"
}

@test "AGENTS.md makes Codex review capability-aware" {
    grep -q "walter ai status" "$AGENTS"
    grep -q "walter-os status --models" "$AGENTS"
    grep -q "provider_codex" "$AGENTS"
    grep -q "Codex unavailable" "$AGENTS"
    grep -q "code_review" "$AGENTS"
    grep -q "infra_security_backend" "$AGENTS"
    grep -q "WALTER_MODEL_BACKEND_REVIEW" "$AGENTS"
}

@test "AGENTS.md uses reviewer-agnostic Round 2 footer" {
    grep -q "cross-review-round-2" "$AGENTS"
    ! grep -q "Refs: codex-review-round-2" "$AGENTS"
}

@test "AGENTS.md has merge criteria section" {
    grep -q "Merge criteria" "$AGENTS"
}
