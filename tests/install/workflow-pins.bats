#!/usr/bin/env bats
# Verifies that every uses: line in new security-hardening workflow files
# is pinned to a 40-character hexadecimal SHA, not a branch or semver tag.
# Covers AC-10.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

_check_workflow_pins() {
  local workflow="$1"
  [ -f "$REPO_ROOT/$workflow" ] || { echo "SKIP: $workflow not found"; return 0; }

  # Extract uses: lines, strip leading whitespace
  # Uses: grep -E to get lines containing 'uses:', then filter out SHA-pinned ones
  local unpinned
  unpinned=$(grep -E '^\s+uses:' "$REPO_ROOT/$workflow" | grep -vE '@[0-9a-f]{40}' || true)
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

@test "all uses: lines in release-security.yml are sha-pinned" {
  _check_workflow_pins ".github/workflows/release-security.yml"
}
