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
  grep -q "security@xipherlabs.xyz" "$REPO_ROOT/SECURITY.md"
  grep -q "GitHub Security Advisories" "$REPO_ROOT/SECURITY.md"
  grep -q "acknowledge reports within 48 hours" "$REPO_ROOT/SECURITY.md"
  grep -q "90-day responsible disclosure window" "$REPO_ROOT/SECURITY.md"
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
    grep -q "$rule" "$f" || {
      echo "missing Scorecard rule: $rule"
      return 1
    }
  done

  grep -q "Issue #396" "$f"
  grep -qi "manual GitHub setting" "$f"
  grep -qi "fuzzing is deferred" "$f"
}
