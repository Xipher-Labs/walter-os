#!/usr/bin/env bats
# tests/github-actions/workflow-permissions.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "read-only workflows declare explicit read or empty token permissions" {
  grep -q '^permissions:$' "$REPO_ROOT/.github/workflows/ci.yml"
  grep -q '^  contents: read$' "$REPO_ROOT/.github/workflows/ci.yml"

  grep -q '^permissions:$' "$REPO_ROOT/.github/workflows/control-tower.yml"
  grep -q '^  contents: read$' "$REPO_ROOT/.github/workflows/control-tower.yml"

  grep -q '^permissions:$' "$REPO_ROOT/.github/workflows/readme-lint.yml"
  grep -q '^  contents: read$' "$REPO_ROOT/.github/workflows/readme-lint.yml"

  grep -q '^permissions: {}$' "$REPO_ROOT/.github/workflows/issue-title-lint.yml"
  grep -q '^permissions: {}$' "$REPO_ROOT/.github/workflows/pr-title-lint.yml"
}

@test "CLA gate does not request broad actions or contents write scopes" {
  ! grep -q '^  actions: write' "$REPO_ROOT/.github/workflows/cla.yml"
  ! grep -q '^  contents: write' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -q '^  contents: read$' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -q '^  issues: write' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -q '^  pull-requests: write' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -q '^  statuses: write' "$REPO_ROOT/.github/workflows/cla.yml"
}

@test "OSV scanner keeps SARIF upload permission scoped to reusable job" {
  grep -q '^permissions:$' "$REPO_ROOT/.github/workflows/osv-scanner.yml"
  grep -q '^  contents: read$' "$REPO_ROOT/.github/workflows/osv-scanner.yml"

  top_permissions="$(awk '
    /^permissions:$/ { in_block=1; next }
    /^jobs:$/ { in_block=0 }
    in_block { print }
  ' "$REPO_ROOT/.github/workflows/osv-scanner.yml")"
  [[ "$top_permissions" != *"security-events: write"* ]]

  grep -q '^      security-events: write$' "$REPO_ROOT/.github/workflows/osv-scanner.yml"
  grep -q '^      actions: read$' "$REPO_ROOT/.github/workflows/osv-scanner.yml"
}

@test "release workflow scopes write permissions to release jobs" {
  top_permissions="$(awk '
    /^permissions:$/ { in_block=1; next }
    /^jobs:$/ { in_block=0 }
    in_block { print }
  ' "$REPO_ROOT/.github/workflows/release.yml")"

  [[ "$top_permissions" == *"contents: read"* ]]
  [[ "$top_permissions" == *"packages: read"* ]]
  [[ "$top_permissions" != *"contents: write"* ]]
  [[ "$top_permissions" != *"id-token: write"* ]]

  grep -q '^      contents: write   # gh release create reads repo metadata and writes releases$' "$REPO_ROOT/.github/workflows/release.yml"
  grep -q '^      contents: write   # gh release download/upload/delete-asset$' "$REPO_ROOT/.github/workflows/release.yml"
  grep -q '^      id-token: write   # cosign OIDC keyless signing$' "$REPO_ROOT/.github/workflows/release.yml"
  grep -q '^      id-token: write  # SLSA reusable workflow signs provenance with OIDC$' "$REPO_ROOT/.github/workflows/release.yml"
  grep -q '^      contents: write  # SLSA reusable workflow uploads provenance to release$' "$REPO_ROOT/.github/workflows/release.yml"
}
