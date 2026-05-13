#!/usr/bin/env bats
# tests/oss/readme-detailed.bats
# AC-11: Structural, length, depersonalization, and cross-link tests for README.md
# Refs: docs/specs/walter-readme-detailed.md

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  cd "$REPO_ROOT"
}

# ── Existence ────────────────────────────────────────────────────────────────

@test "README.md exists at repo root" {
  [ -f "README.md" ]
}

# ── Length ───────────────────────────────────────────────────────────────────

@test "README.md has at least 1500 lines [AC-3]" {
  lines_count=$(wc -l < README.md)
  [ "$lines_count" -ge 1500 ]
}

@test "README.md has at most 2500 lines [AC-3]" {
  lines_count=$(wc -l < README.md)
  [ "$lines_count" -le 2500 ]
}

# ── Section headings [AC-2] ──────────────────────────────────────────────────

@test "README.md contains section: Personas" {
  grep -qF "## Personas" README.md
}

@test "README.md contains section: Stack at a glance" {
  grep -qF "## Stack at a glance" README.md
}

@test "README.md contains section: Networking and access" {
  grep -qF "## Networking and access" README.md
}

@test "README.md contains section: Secrets flow" {
  grep -qF "## Secrets flow" README.md
}

@test "README.md contains section: Multi-device strategy" {
  grep -qF "## Multi-device strategy" README.md
}

@test "README.md contains section: Resource budget" {
  grep -qF "## Resource budget" README.md
}

@test "README.md contains section: Step-by-step installation" {
  grep -qF "## Step-by-step installation" README.md
}

@test "README.md contains section: Customization patterns" {
  grep -qF "## Customization patterns" README.md
}

@test "README.md contains section: Walter-Bridge and CLI clients" {
  grep -qF "## Walter-Bridge and CLI clients" README.md
}

@test "README.md contains section: Operator contexts at a glance" {
  grep -qF "## Operator contexts at a glance" README.md
}

@test "README.md contains section: n8n workflows" {
  grep -qF "## n8n workflows" README.md
}

@test "README.md contains section: Updating" {
  grep -qF "## Updating" README.md
}

@test "README.md contains section: Troubleshooting" {
  grep -qF "## Troubleshooting" README.md
}

@test "README.md contains section: Contribution" {
  grep -qF "## Contribution" README.md
}

@test "README.md contains section: Security" {
  grep -qF "## Security" README.md
}

@test "README.md contains section: License" {
  grep -qF "## License" README.md
}

# ── Depersonalization [AC-4] ─────────────────────────────────────────────────

@test "README.md does not contain 'nicofernandez'" {
  count=$(grep -ic "nicofernandez" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md contains a single founder handle in the origin note" {
  count=$(grep -ic "f0x1777" README.md || true)
  [ "$count" -eq 1 ]
}

@test "README.md does not contain 'nico.fran'" {
  count=$(grep -ic "nico\.fran" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md does not contain 'Nico Fernandez'" {
  count=$(grep -ic "nico fernandez" README.md || true)
  [ "$count" -eq 0 ]
}

# ── Troubleshooting entry count [AC-9] ───────────────────────────────────────

@test "README.md troubleshooting section has at least 15 entries" {
  # Count table rows (lines starting with | that are not the header or separator)
  # between ## Troubleshooting and the next ## heading
  count=$(awk '/^## Troubleshooting/{found=1; next} found && /^## /{exit} found && /^\|[^-]/{count++} END{print count+0}' README.md)
  [ "$count" -ge 15 ]
}

# ── CX53 recommended [AC-7] ──────────────────────────────────────────────────

@test "README.md resource budget mentions CX53 as Recommended" {
  grep -q "CX53" README.md
  grep -q "Recommended" README.md
}

# ── Multi-device approaches [AC-8] ───────────────────────────────────────────

@test "README.md multi-device section mentions Syncthing" {
  grep -q "Syncthing" README.md
}

@test "README.md multi-device section mentions private git overlay" {
  grep -q "private git" README.md
}

@test "README.md multi-device section mentions Ansible" {
  grep -q "Ansible" README.md
}

# ── License/brand [AC-10] ────────────────────────────────────────────────────

@test "README.md license section mentions AGPLv3" {
  grep -q "AGPL" README.md
}

@test "README.md license section mentions Xipher Labs" {
  grep -q "Xipher Labs" README.md
}

# ── Cross-link resolution [AC-5] ─────────────────────────────────────────────
# Only check files that are expected to exist on this branch.
# Files from dependent PRs (CONTRIBUTING.md, SECURITY.md, COMMERCIAL.md,
# LICENSE, NOTICE, n8n/workflows/, setup/walter-host/services/*/SUGGESTIONS.md,
# contexts/hackathons/, docs/operational/operator-contexts.md) are NOT checked
# here — they will exist post-merge. The bats file documents them as pending.

@test "cross-link: docs/decisions/0008-control-tower-stack.md exists" {
  [ -f "docs/decisions/0008-control-tower-stack.md" ]
}

@test "cross-link: docs/decisions/0009-agent-trust-tiers.md exists" {
  [ -f "docs/decisions/0009-agent-trust-tiers.md" ]
}

@test "cross-link: docs/operational/onboarding-checklist.md exists" {
  [ -f "docs/operational/onboarding-checklist.md" ]
}

@test "cross-link: setup/walter-host/cloudflare/ directory exists" {
  [ -d "setup/walter-host/cloudflare" ]
}

@test "cross-link: setup/walter-host/services/litellm/config.yaml exists" {
  [ -f "setup/walter-host/services/litellm/config.yaml" ]
}

@test "cross-link: skills/daily-supply-chain-audit/SKILL.md exists" {
  [ -f "skills/daily-supply-chain-audit/SKILL.md" ]
}

@test "cross-link: docs/specs/walter-council-v2.md exists" {
  [ -f "docs/specs/walter-council-v2.md" ]
}

@test "cross-link: contexts/work/ directory exists" {
  [ -d "contexts/work" ]
}

@test "cross-link: contexts/projects-personal/ directory exists" {
  [ -d "contexts/projects-personal" ]
}

@test "cross-link: contexts/personal/ directory exists" {
  [ -d "contexts/personal" ]
}

@test "cross-link: apps/control-tower/ directory exists" {
  [ -d "apps/control-tower" ]
}
