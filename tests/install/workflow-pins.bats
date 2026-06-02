#!/usr/bin/env bats
# Verifies that every uses: line in new security-hardening workflow files
# is pinned to a 40-character hexadecimal SHA, not a branch or semver tag.
# Covers AC-10.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

_check_workflow_pins() {
  local workflow="$1"
  local required="${2:-optional}"
  if [ ! -f "$REPO_ROOT/$workflow" ]; then
    if [ "$required" = "required" ]; then
      echo "Required workflow missing: $workflow"
      return 1
    fi
    echo "SKIP: $workflow not found"
    return 0
  fi

  # Select step-level and reusable-workflow uses: lines. Third-party actions
  # must be SHA-pinned. The SLSA generic generator is a reusable workflow
  # exception:
  # upstream requires release tags so slsa-verifier can validate the trusted
  # builder identity embedded in provenance.
  local unpinned
  unpinned=$(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:' "$REPO_ROOT/$workflow" \
    | grep -vE '@[0-9a-f]{40}' \
    | grep -vE 'slsa-framework/slsa-github-generator/\.github/workflows/generator_generic_slsa3\.yml@v2\.1\.0([[:space:]]|$)' \
    || true)
  if [ -n "$unpinned" ]; then
    echo "Unpinned action in $workflow:"
    echo "$unpinned"
    return 1
  fi
  return 0
}

@test "all uses: lines in gitleaks.yml are sha-pinned" {
  _check_workflow_pins ".github/workflows/gitleaks.yml"
}

@test "all uses: lines in scorecard.yml are sha-pinned" {
  _check_workflow_pins ".github/workflows/scorecard.yml"
}

@test "all uses: lines in osv-scanner.yml are sha-pinned" {
  _check_workflow_pins ".github/workflows/osv-scanner.yml"
}

@test "all uses: lines in codeql.yml are sha-pinned" {
  _check_workflow_pins ".github/workflows/codeql.yml"
}

@test "all uses: lines in release.yml are sha-pinned" {
  _check_workflow_pins ".github/workflows/release.yml" required
}

@test "SLSA generator allowlist rejects suffixed release tags" {
  cat > "$BATS_TEST_TMPDIR/slsa-suffix.yml" <<'YAML'
jobs:
  provenance:
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0-rc1
YAML

  REPO_ROOT="$BATS_TEST_TMPDIR"
  run _check_workflow_pins "slsa-suffix.yml" required

  [ "$status" -eq 1 ]
  grep -Fq "Unpinned action" <<<"$output"
}
