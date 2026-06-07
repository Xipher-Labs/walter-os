#!/usr/bin/env bats
# tests/github-actions/workflow-permissions.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

workflow_permissions_block() {
  awk '
    /^permissions:/ { in_block=1; print; next }
    /^jobs:/ { in_block=0 }
    in_block { print }
  ' "$1"
}

assert_permission_line() {
  local file="$1"
  local key="$2"
  local value="$3"
  local block
  block="$(workflow_permissions_block "$file")"
  grep -Eq "^[[:space:]]*${key}:[[:space:]]*${value}([[:space:]]*#.*)?$" <<<"$block"
}

@test "read-only workflows declare explicit read or empty token permissions" {
  assert_permission_line "$REPO_ROOT/.github/workflows/ci.yml" "contents" "read"

  assert_permission_line "$REPO_ROOT/.github/workflows/control-tower.yml" "contents" "read"

  assert_permission_line "$REPO_ROOT/.github/workflows/readme-lint.yml" "contents" "read"

  grep -Eq '^permissions:[[:space:]]*\{\}[[:space:]]*$' "$REPO_ROOT/.github/workflows/issue-title-lint.yml"
  grep -Eq '^permissions:[[:space:]]*\{\}[[:space:]]*$' "$REPO_ROOT/.github/workflows/pr-title-lint.yml"
}

@test "CLA gate does not request broad actions or contents write scopes" {
  top_permissions="$(workflow_permissions_block "$REPO_ROOT/.github/workflows/cla.yml")"
  [[ "$top_permissions" == *"contents: read"* ]]
  [[ "$top_permissions" != *"issues: write"* ]]
  [[ "$top_permissions" != *"pull-requests: write"* ]]
  [[ "$top_permissions" != *"statuses: write"* ]]
  ! grep -q '^  actions: write' "$REPO_ROOT/.github/workflows/cla.yml"
  ! grep -q '^  contents: write' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -Eq '^[[:space:]]*issues:[[:space:]]*write[[:space:]]*#.*comments on CLA signatures' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -Eq '^[[:space:]]*pull-requests:[[:space:]]*write[[:space:]]*#.*labels / updates PR state' "$REPO_ROOT/.github/workflows/cla.yml"
  grep -Eq '^[[:space:]]*statuses:[[:space:]]*write[[:space:]]*#.*publishes CLA commit status' "$REPO_ROOT/.github/workflows/cla.yml"
}

@test "CodeQL scopes SARIF upload permission to analysis job" {
  top_permissions="$(workflow_permissions_block "$REPO_ROOT/.github/workflows/codeql.yml")"

  [[ "$top_permissions" == *"actions: read"* ]]
  [[ "$top_permissions" == *"contents: read"* ]]
  [[ "$top_permissions" != *"security-events: write"* ]]

  grep -Eq '^[[:space:]]*security-events:[[:space:]]*write[[:space:]]*#.*upload SARIF results' "$REPO_ROOT/.github/workflows/codeql.yml"
}

@test "OSV scanner keeps SARIF upload permission scoped to reusable job" {
  assert_permission_line "$REPO_ROOT/.github/workflows/osv-scanner.yml" "contents" "read"

  top_permissions="$(workflow_permissions_block "$REPO_ROOT/.github/workflows/osv-scanner.yml")"
  [[ "$top_permissions" != *"security-events: write"* ]]

  grep -Eq '^[[:space:]]*security-events:[[:space:]]*write([[:space:]]*#.*)?$' "$REPO_ROOT/.github/workflows/osv-scanner.yml"
  grep -Eq '^[[:space:]]*actions:[[:space:]]*read([[:space:]]*#.*)?$' "$REPO_ROOT/.github/workflows/osv-scanner.yml"
}

@test "release workflow scopes write permissions to release jobs" {
  top_permissions="$(workflow_permissions_block "$REPO_ROOT/.github/workflows/release.yml")"

  [[ "$top_permissions" == *"contents: read"* ]]
  [[ "$top_permissions" == *"packages: read"* ]]
  [[ "$top_permissions" != *"contents: write"* ]]
  [[ "$top_permissions" != *"id-token: write"* ]]

  grep -Eq '^[[:space:]]*contents:[[:space:]]*write[[:space:]]*#.*gh release create' "$REPO_ROOT/.github/workflows/release.yml"
  grep -Eq '^[[:space:]]*contents:[[:space:]]*write[[:space:]]*#.*gh release download/upload/delete-asset' "$REPO_ROOT/.github/workflows/release.yml"
  grep -Eq '^[[:space:]]*id-token:[[:space:]]*write[[:space:]]*#.*cosign OIDC keyless signing' "$REPO_ROOT/.github/workflows/release.yml"
  grep -Eq '^[[:space:]]*id-token:[[:space:]]*write[[:space:]]*#.*SLSA reusable workflow signs provenance with OIDC' "$REPO_ROOT/.github/workflows/release.yml"
  grep -Eq '^[[:space:]]*contents:[[:space:]]*write[[:space:]]*#.*SLSA reusable workflow uploads provenance to release' "$REPO_ROOT/.github/workflows/release.yml"
}
