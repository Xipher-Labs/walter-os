#!/usr/bin/env bats
# tests/oss/scorecard-hygiene.bats
# Regression guard for Scorecard project-hygiene follow-up (#396).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "security policy is discoverable from root and .github" {
  [[ -f "$REPO_ROOT/SECURITY.md" ]]
  [[ -f "$REPO_ROOT/.github/SECURITY.md" ]]
  diff -q "$REPO_ROOT/SECURITY.md" "$REPO_ROOT/.github/SECURITY.md"
}

@test "security policy includes private disclosure and response expectations" {
  grep -Fq "security@xipherlabs.xyz" "$REPO_ROOT/SECURITY.md"
  grep -Fq "GitHub Security Advisories" "$REPO_ROOT/SECURITY.md"
  grep -Fq "acknowledge reports within 48 hours" "$REPO_ROOT/SECURITY.md"
  grep -Fq "90-day responsible disclosure window" "$REPO_ROOT/SECURITY.md"
  grep -qi "acknowledge contributors" "$REPO_ROOT/SECURITY.md"
}

@test "OpenSSF checklist no longer claims SECURITY.md is missing" {
  local f="$REPO_ROOT/docs/security/openssf-silver-checklist.md"
  ! grep -qi 'Missing top-level `SECURITY.md`' "$f"
  ! grep -qi 'TODO: `SECURITY.md`' "$f"
  ! grep -qi 'Repo hygiene files missing:.*SECURITY.md' "$f"
}

@test "Scorecard hygiene runbook records each current alert disposition" {
  local f="$REPO_ROOT/docs/operational/scorecard-hygiene.md"
  [[ -f "$f" ]]

  for rule in CodeReviewID MaintainedID SecurityPolicyID CIIBestPracticesID FuzzingID; do
    grep -Fq "$rule" "$f" || {
      echo "missing Scorecard rule: $rule"
      return 1
    }
  done

  grep -Fq "Issue #396" "$f"
  grep -qi "manual GitHub setting" "$f"
  grep -Fq "Found 0/30 approved changesets" "$f"
  grep -Fq "history/operator-policy signal" "$f"
  grep -Fq "required_signatures.enabled: false" "$f"
  grep -Fq 'fast-check' "$f"
  grep -Fq 'sanitize.fuzz.test.ts' "$f"
}

@test "OpenSSF Best Practices filing runbook documents operator action" {
  local f="$REPO_ROOT/docs/operational/openssf-badge-filing-runbook.md"
  [[ -f "$f" ]]

  grep -Fq "CIIBestPracticesID" "$f"
  grep -Fiq "issue #423" "$f"
  grep -Fq "https://www.bestpractices.dev/en/projects/new" "$f"
  grep -Fq "https://www.bestpractices.dev/en/criteria/0" "$f"
  grep -Fq "Do not add an OpenSSF" "$f"
  grep -Fq "approved" "$f"
  grep -Fq "project URL" "$f"
  grep -Fq "README.md" "$f"
  grep -Fq "Scorecard" "$f"
}

@test "Scorecard hygiene links the OpenSSF filing runbook" {
  local f="$REPO_ROOT/docs/operational/scorecard-hygiene.md"
  local index="$REPO_ROOT/docs/operational/README.md"

  grep -Fq "docs/operational/openssf-badge-filing-runbook.md" "$f"
  grep -Fq "openssf-badge-filing-runbook.md" "$index"
}

@test "Scorecard hygiene runbook documents MaintainedID repo-age disposition" {
  local f="$REPO_ROOT/docs/operational/scorecard-hygiene.md"
  [[ -f "$f" ]]

  grep -Fq "Issue #424" "$f"
  grep -Fq "Alert #46" "$f"
  grep -Fq "project was created" "$f"
  grep -Fq "within the last 90 days" "$f"
  grep -Fq "not actionable by repository patch" "$f"
  grep -Fq "2026-08-11" "$f"
}
