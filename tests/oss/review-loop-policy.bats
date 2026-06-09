#!/usr/bin/env bats
# tests/oss/review-loop-policy.bats
# AC-11: AGENTS.md contains the 3-round review-loop policy structure.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    AGENTS="$REPO_ROOT/AGENTS.md"
    PR_TEMPLATE="$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"

    [[ -f "$AGENTS" ]]
    [[ -f "$PR_TEMPLATE" ]]
}

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
    grep -q "CODEX_MINIMAL_HOME" "$AGENTS"
    grep -q "mktemp -d" "$AGENTS"
    grep -q "chmod 700" "$AGENTS"
    grep -q "chmod 600" "$AGENTS"
    grep -q "model = \"gpt-5.5\"" "$AGENTS"
    grep -q "CODEX_REVIEW_OUTPUT" "$AGENTS"
    ! grep -q "/tmp/codex-review.txt" "$AGENTS"
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

@test "PR template makes Round 2 cross-review capability-aware" {
    grep -q "Round 2 cross-review" "$PR_TEMPLATE"
    grep -q "declared AI capability routes and effective model routing" "$PR_TEMPLATE"
    grep -q "walter ai status" "$PR_TEMPLATE"
    grep -q "walter-os status --models" "$PR_TEMPLATE"
    grep -q "provider_codex" "$PR_TEMPLATE"
    grep -q "code_review" "$PR_TEMPLATE"
    grep -q "infra_security_backend" "$PR_TEMPLATE"
    grep -q "codex-minimal" "$PR_TEMPLATE"
    grep -q "CODEX_MINIMAL_HOME" "$PR_TEMPLATE"
    grep -q "mktemp -d" "$PR_TEMPLATE"
    grep -q "chmod 700" "$PR_TEMPLATE"
    grep -q "chmod 600" "$PR_TEMPLATE"
    grep -q "model = \"gpt-5.5\"" "$PR_TEMPLATE"
    grep -q 'CODEX_HOME="$CODEX_MINIMAL_HOME"' "$PR_TEMPLATE"
    grep -q "CODEX_REVIEW_OUTPUT" "$PR_TEMPLATE"
    grep -q "codex review --base <target-branch>" "$PR_TEMPLATE"
    ! grep -q "codex review --base main" "$PR_TEMPLATE"
    ! grep -q "/tmp/codex-review.txt" "$PR_TEMPLATE"
    grep -q "If Codex is unavailable" "$PR_TEMPLATE"
    grep -q "Round 2 cross-review completed or explicitly escalated" "$PR_TEMPLATE"
}

@test "AGENTS.md has merge criteria section" {
    grep -q "Merge criteria" "$AGENTS"
}
