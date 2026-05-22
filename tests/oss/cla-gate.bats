#!/usr/bin/env bats
# tests/oss/cla-gate.bats
# Regression guard for the CLA gate (ADR-0019).
#
# The CLA is gated by the WALTER_CLA_ACTIVE repo variable. These tests
# verify the scaffold exists and the activation gate is wired correctly.
# When the operator flips WALTER_CLA_ACTIVE=true, the workflow starts
# enforcing signatures without further code changes.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ---------------------------------------------------------------------------
# CLA.md — the agreement text
# ---------------------------------------------------------------------------

@test "CLA.md exists at repo root" {
  [[ -f "$REPO_ROOT/CLA.md" ]]
}

@test "CLA.md grants commercial sublicense right" {
  # The sublicense-under-commercial-license clause is the critical grant
  # that makes IdeaOS legally possible. Per ADR-0019 Decision §2(b).
  grep -q "[Cc]ommercial" "$REPO_ROOT/CLA.md"
  grep -qi "sublicense" "$REPO_ROOT/CLA.md"
}

@test "CLA.md grants patent license" {
  # Per ADR-0019 Decision §3.
  grep -qi "patent license" "$REPO_ROOT/CLA.md"
}

@test "CLA.md is marked DRAFT pending lawyer review" {
  # Per ADR-0019 migration step 1, the CLA must be lawyer-reviewed before
  # activation. Until then the file must clearly flag itself as draft.
  grep -qi "DRAFT" "$REPO_ROOT/CLA.md"
  grep -qi "lawyer" "$REPO_ROOT/CLA.md"
}

@test "CLA.md references ADR-0019" {
  grep -q "0019" "$REPO_ROOT/CLA.md"
}

# ---------------------------------------------------------------------------
# .github/workflows/cla.yml — enforcement workflow
# ---------------------------------------------------------------------------

@test "CLA workflow exists" {
  [[ -f "$REPO_ROOT/.github/workflows/cla.yml" ]]
}

@test "CLA workflow is gated by WALTER_CLA_ACTIVE" {
  # Critical: the workflow must NOT block PRs until the operator opts in.
  # The gate is an `if:` on the job referencing vars.WALTER_CLA_ACTIVE.
  grep -q "WALTER_CLA_ACTIVE" "$REPO_ROOT/.github/workflows/cla.yml"
}

@test "CLA workflow uses contributor-assistant/github-action pinned by SHA" {
  # ADR-0019 specifies this action.
  # #187 (Codex sweep, 2026-05-22): when WALTER_CLA_ACTIVE is enabled
  # this workflow runs under pull_request_target with access to
  # GITHUB_TOKEN AND the CLA signatures PAT. A mutable tag (`@v2.6.1`)
  # lets the upstream owner of the action repository swap in arbitrary
  # code on the next CI run. Pin to a 40-char commit SHA. The
  # human-readable tag may follow in a comment for traceability.
  grep -qE "contributor-assistant/github-action@[0-9a-f]{40}" "$REPO_ROOT/.github/workflows/cla.yml"
  # Belt-and-braces: forbid mutable refs explicitly.
  ! grep -qE "contributor-assistant/github-action@(main|master|v[0-9])" "$REPO_ROOT/.github/workflows/cla.yml"
}

@test "CLA workflow uses the canonical sign-comment phrase" {
  # Per ADR-0019: "I have read the CLA Document and I hereby sign the CLA"
  grep -q "I have read the CLA Document and I hereby sign the CLA" \
    "$REPO_ROOT/.github/workflows/cla.yml"
}

@test "CLA workflow allowlists known bots" {
  # dependabot, renovate, copilot do not sign CLAs.
  grep -q "dependabot" "$REPO_ROOT/.github/workflows/cla.yml"
  grep -q "renovate" "$REPO_ROOT/.github/workflows/cla.yml"
  grep -q "copilot-pull-request-reviewer" "$REPO_ROOT/.github/workflows/cla.yml"
}

# ---------------------------------------------------------------------------
# PR template + CONTRIBUTING.md — contributor-facing surface
# ---------------------------------------------------------------------------

@test "PR template mentions the CLA" {
  grep -qi "CLA" "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
}

@test "CONTRIBUTING.md documents the CLA flow" {
  grep -qi "Contributor License Agreement" "$REPO_ROOT/CONTRIBUTING.md"
  grep -q "I have read the CLA Document and I hereby sign the CLA" \
    "$REPO_ROOT/CONTRIBUTING.md"
}

@test "CONTRIBUTING.md documents the dual-license posture" {
  # CONTRIBUTING.md must reflect ADR-0018 (dual-license) not the historical
  # AGPL-only posture, otherwise contributors get conflicting signals.
  grep -qi "Apache" "$REPO_ROOT/CONTRIBUTING.md"
  grep -qi "AGPL" "$REPO_ROOT/CONTRIBUTING.md"
  grep -qi "SPDX" "$REPO_ROOT/CONTRIBUTING.md"
}
