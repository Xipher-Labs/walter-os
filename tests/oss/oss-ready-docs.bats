#!/usr/bin/env bats
# tests/oss/oss-ready-docs.bats
# Regression guard — OSS-ready community health files.
# Spec: docs/specs/walter-oss-ready-docs.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# --- File existence ---
@test "README.md exists" { [[ -f "$REPO_ROOT/README.md" ]]; }
@test "CONTRIBUTING.md exists" { [[ -f "$REPO_ROOT/CONTRIBUTING.md" ]]; }
@test "SECURITY.md exists" { [[ -f "$REPO_ROOT/SECURITY.md" ]]; }
@test "CODE_OF_CONDUCT.md exists" { [[ -f "$REPO_ROOT/CODE_OF_CONDUCT.md" ]]; }
@test "CHANGELOG.md exists" { [[ -f "$REPO_ROOT/CHANGELOG.md" ]]; }
@test ".github/ISSUE_TEMPLATE/bug.md exists" {
  [[ -f "$REPO_ROOT/.github/ISSUE_TEMPLATE/bug.md" ]]
}
@test ".github/ISSUE_TEMPLATE/feature.md exists" {
  [[ -f "$REPO_ROOT/.github/ISSUE_TEMPLATE/feature.md" ]]
}
@test ".github/PULL_REQUEST_TEMPLATE.md exists" {
  [[ -f "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md" ]]
}

# --- README content ---
@test "README.md mentions Xipher Labs" {
  grep -q "Xipher Labs" "$REPO_ROOT/README.md"
}
@test "README.md mentions AGPL" {
  grep -q "AGPL" "$REPO_ROOT/README.md"
}
@test "README.md has Quick Start section" {
  grep -qi "quick.start\|quickstart" "$REPO_ROOT/README.md"
}
@test "README.md has persona section" {
  grep -q "Builder" "$REPO_ROOT/README.md"
  grep -q "Founder" "$REPO_ROOT/README.md"
  grep -q "Operator" "$REPO_ROOT/README.md"
}

# --- CONTRIBUTING.md content ---
@test "CONTRIBUTING.md mentions superpowers" {
  grep -q "superpowers" "$REPO_ROOT/CONTRIBUTING.md"
}
@test "CONTRIBUTING.md mentions the host-stack license (AGPL)" {
  # Post-ADR-0018: AGPL applies only to setup/walter-host/; default tree is
  # Apache-2.0. CONTRIBUTING.md must still document the AGPL boundary so
  # contributors know which license governs their change. Accept any of the
  # canonical spellings: "AGPLv3", "AGPL v3", "AGPL-3.0", "AGPL-3.0-or-later".
  # Regex matches "AGPL" followed by zero-or-one separator (space or dash),
  # then optional "v", then "3", then optional ".0".
  grep -qE "AGPL[ -]?v?3(\.0)?" "$REPO_ROOT/CONTRIBUTING.md"
}

# --- SECURITY.md content ---
@test "SECURITY.md has security@xipherlabs.xyz" {
  grep -q "security@xipherlabs.xyz" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md has no TODO(pre-launch) HTML comment (stripped at pre-OSS audit)" {
  run grep -q "TODO(pre-launch)" "$REPO_ROOT/SECURITY.md"
  [ "$status" -ne 0 ]
}
@test "SECURITY.md states no bug bounty" {
  grep -q "do not currently run a bug bounty" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md supported versions match current release line" {
  version="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
  major_minor="${version%.*}"
  previous_minor="$(awk -F. -v major="${version%%.*}" -v minor="${major_minor#*.}" 'BEGIN { print major "." (minor - 1) }')"

  grep -q "currently ${major_minor}\\.x" "$REPO_ROOT/SECURITY.md"
  grep -q "currently ${previous_minor}\\.x" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md links private GitHub advisory reporting" {
  grep -q "https://github.com/Xipher-Labs/walter-os/security/advisories/new" "$REPO_ROOT/SECURITY.md"
}

# --- CODE_OF_CONDUCT.md content ---
@test "CODE_OF_CONDUCT.md is Contributor Covenant 2.1" {
  grep -q "Contributor Covenant" "$REPO_ROOT/CODE_OF_CONDUCT.md"
  grep -q "2\.1" "$REPO_ROOT/CODE_OF_CONDUCT.md"
}

# --- CHANGELOG.md content ---
@test "CHANGELOG.md has Keep a Changelog 1.1 header" {
  grep -q "Keep a Changelog 1.1" "$REPO_ROOT/CHANGELOG.md"
}
@test "CHANGELOG.md has [Unreleased] section" {
  grep -q "\[Unreleased\]" "$REPO_ROOT/CHANGELOG.md"
}
@test "CHANGELOG.md has [0.2.0] section" {
  grep -q "\[0\.2\.0\]" "$REPO_ROOT/CHANGELOG.md"
}
@test "CHANGELOG.md has footer link references" {
  # The [Unreleased] compare link tracks the most-recent tagged version.
  # Each release bumps this; we assert the link shape rather than a specific
  # version so the test doesn't have to be updated on every release.
  grep -qE "compare/v[0-9]+\.[0-9]+\.[0-9]+\.\.\.HEAD" "$REPO_ROOT/CHANGELOG.md"
}

# --- Issue templates ---
@test "bug.md has YAML frontmatter name and labels" {
  grep -q "^name:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/bug.md"
  grep -q "^labels:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/bug.md"
}
@test "feature.md has YAML frontmatter name and labels" {
  grep -q "^name:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/feature.md"
  grep -q "^labels:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/feature.md"
}

# --- PR template ---
@test "PULL_REQUEST_TEMPLATE.md mentions Copilot" {
  grep -q "Copilot" "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
}

# --- Pre-launch mailbox TODO pattern (all stripped at pre-OSS audit) ---
@test "no TODO(pre-launch) HTML comments remain across md files" {
  count=$(grep -rn "TODO(pre-launch)" "$REPO_ROOT" --include="*.md" \
    | grep -v 'docs/specs/' \
    | grep -v 'tests/oss/' \
    | grep -v 'PULL_REQUEST_TEMPLATE' \
    | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}

# --- B-8: Stale references ---
@test "ADR index lists 0010-oss-license" {
  grep -q "0010-oss-license" "$REPO_ROOT/docs/decisions/README.md"
}
@test "ADR index lists 0011-depersonalization-strategy" {
  grep -q "0011-depersonalization-strategy" "$REPO_ROOT/docs/decisions/README.md"
}
@test "ADR index lists 0012-oss-security-hardening-primitives" {
  grep -q "0012-oss-security-hardening-primitives" "$REPO_ROOT/docs/decisions/README.md"
}
@test "control-tower.yml has no dead feature/council-v2-ui branch trigger" {
  run grep -q "feature/council-v2-ui" "$REPO_ROOT/.github/workflows/control-tower.yml"
  [ "$status" -ne 0 ]
}
@test "CHANGELOG.md has no TODO: stale inline comment" {
  run grep -q "TODO: stale" "$REPO_ROOT/CHANGELOG.md"
  [ "$status" -ne 0 ]
}
