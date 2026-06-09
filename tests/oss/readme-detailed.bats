#!/usr/bin/env bats
# tests/oss/readme-detailed.bats
#
# Structural + depersonalization + cross-link tests for README.md.
#
# v0.5.1 refactor: the README was reshaped per the `readme-craft` skill's
# OSS-publication template — compressed from ~1900 lines to ~300, with
# the deep-dive content extracted to docs/operational/* runbooks. The
# section list below pins the NEW canonical shape going forward.
#
# Refs: docs/specs/walter-readme-detailed.md (updated for v0.5.1 rewrite)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  cd "$REPO_ROOT"
}

@test "README.md exists at repo root" {
  [ -f "README.md" ]
}

# ── Length: scannable on a phone, not a wall of text ────────────────────────
#
# Per the readme-craft skill: "Walls of text" is an anti-pattern. We pin a
# generous upper bound (600 lines) to stop the doc growing back to a 2000-
# line install runbook; the floor (150 lines) keeps the rewrite from being
# trimmed below an OSS-publication-ready surface.

@test "README.md has at least 150 lines" {
  lines_count=$(wc -l < README.md)
  [ "$lines_count" -ge 150 ]
}

@test "README.md has at most 600 lines (scannable)" {
  lines_count=$(wc -l < README.md)
  [ "$lines_count" -le 600 ]
}

# ── Section headings — pins the OSS-publication template shape ─────────────

@test "README.md contains section: What is this" {
  grep -qF "## What is this" README.md
}

@test "README.md contains section: Install" {
  grep -qF "## Install" README.md
}

@test "README.md install section names three modes" {
  # Mode 1 (Lite), Mode 2 (client install), Mode 3 (self-hosted stack)
  grep -qE "Walter-OS Lite" README.md
  grep -qE "Client install" README.md
  grep -qE "Self-hosted stack" README.md
}

@test "README.md contains section: Quickstart" {
  grep -qF "## Quickstart" README.md
}

@test "README.md contains section: Security floor" {
  grep -qF "## Security floor" README.md
}

@test "README.md contains section: Disciplines" {
  grep -qF "## Disciplines" README.md
}

@test "README.md contains section: Catalogs" {
  grep -qF "## Catalogs" README.md
}

@test "README.md contains section: Configuration" {
  grep -qF "## Configuration" README.md
}

@test "README.md contains section: Uninstall" {
  # Operator explicitly asked for a highlighted uninstall section in
  # the v0.5.1 rewrite. Pin it.
  grep -qF "## Uninstall" README.md
}

@test "README.md uninstall section documents --restore-backups" {
  grep -qF -- "--restore-backups" README.md
  grep -qF -- "--no-restore-backups" README.md
}

@test "README.md uninstall section documents both install.sh + walter-os CLI" {
  grep -qF "install.sh --uninstall" README.md
  grep -qF "walter-os uninstall" README.md
}

@test "README.md contains section: Updates" {
  grep -qF "## Updates" README.md
}

@test "README.md contains section: Repo structure" {
  grep -qF "## Repo structure" README.md
}

@test "README.md contains section: Contributing" {
  grep -qF "## Contributing" README.md
}

@test "README.md contains section: License" {
  grep -qF "## License" README.md
}

# ── Security floor pins all five PreToolUse hooks ───────────────────────────

@test "README.md security floor lists all 5 PreToolUse hooks" {
  grep -qF "bash-denylist.sh" README.md
  grep -qF "approval-gate.sh" README.md
  grep -qF "network-gate.sh" README.md
  grep -qF "branch-flow-guard.sh" README.md
  grep -qF "pre-commit-tests.sh" README.md
}

@test "README.md security floor links to the network-egress operator guide" {
  grep -qF "docs/operational/network-egress.md" README.md
}

# ── Cursor + Antigravity AGENTS.md cascade is called out ────────────────────

@test "README.md mentions all 4 supported tools (Claude / Codex / Cursor / Antigravity)" {
  grep -qE "Claude Code" README.md
  grep -qE "Codex CLI" README.md
  grep -qE "Cursor" README.md
  grep -qE "Antigravity" README.md
}

@test "README.md mentions adapter generators for Cursor + Antigravity" {
  grep -qF -- "--cursor-rules" README.md
  grep -qF -- "--antigravity-rules" README.md
}

# ── Depersonalization (AC-4) ────────────────────────────────────────────────

@test "README.md does not contain 'nicofernandez'" {
  count=$(grep -ic "nicofernandez" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md does not contain 'nico.fran'" {
  count=$(grep -ic "nico\.fran" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md does not contain 'Nico Fernandez'" {
  count=$(grep -ic "nico fernandez" README.md || true)
  [ "$count" -eq 0 ]
}

# ── License / brand ─────────────────────────────────────────────────────────

@test "README.md license section mentions AGPL" {
  grep -q "AGPL" README.md
}

@test "README.md license section mentions Apache-2.0" {
  grep -q "Apache" README.md
}

@test "README.md license section mentions Xipher Labs" {
  grep -q "Xipher Labs" README.md
}

@test "README.md license section names the dual-license map" {
  grep -qE "setup/walter-host" README.md
  grep -qE "Apache" README.md
}

# ── v0.6.2 release-relevant content ────────────────────────────────────────

@test "README.md version badge reflects v0.6.2-alpha" {
  grep -qF "v0.6.2--alpha" README.md
}

@test "README.md status line names v0.6.2" {
  grep -qE "v0\.6\.2" README.md
}

@test "README.md explains configurable LLM providers" {
  grep -qF "walter providers configure --category llm" README.md
  grep -qF "gemini" README.md
}

# ── README cross-links + pinned doc invariants ─────────────────────────────
#
# The tight README links to selected specs/runbooks instead of embedding
# them, and it also relies on a few adjacent docs that are intentionally not
# linked inline. Pin both groups here so future doc cleanups do not silently
# break the README contract.

@test "cross-link: docs/operational/network-egress.md exists" {
  [ -f "docs/operational/network-egress.md" ]
}

@test "cross-link: docs/operational/operator-setup-runbook.md exists" {
  [ -f "docs/operational/operator-setup-runbook.md" ]
}

@test "cross-link: docs/operational/requirements.md exists" {
  [ -f "docs/operational/requirements.md" ]
}

@test "cross-link: docs/operational/operator-contexts.md exists" {
  [ -f "docs/operational/operator-contexts.md" ]
}

@test "cross-link: docs/operational/walter-os-vs-walter-host.md exists" {
  [ -f "docs/operational/walter-os-vs-walter-host.md" ]
}

@test "cross-link: docs/operational/v0.6.0-release-readiness.md exists" {
  [ -f "docs/operational/v0.6.0-release-readiness.md" ]
}

@test "cross-link: docs/operational/v0.6.2-release-notes.md exists" {
  [ -f "docs/operational/v0.6.2-release-notes.md" ]
}

@test "cross-link: docs/decisions/0013-solo-operator-merge-policy.md exists" {
  [ -f "docs/decisions/0013-solo-operator-merge-policy.md" ]
}

@test "cross-link: docs/decisions/0018-licensing-strategy.md exists" {
  [ -f "docs/decisions/0018-licensing-strategy.md" ]
}

@test "cross-link: docs/specs/walter-os-v1-0-stability-charter.md exists" {
  [ -f "docs/specs/walter-os-v1-0-stability-charter.md" ]
}

@test "cross-link: skills/daily-supply-chain-audit/SKILL.md exists" {
  [ -f "skills/daily-supply-chain-audit/SKILL.md" ]
}

@test "cross-link: skills/INDEX.md exists" {
  [ -f "skills/INDEX.md" ]
}

@test "cross-link: setup/agent-install/{lite,lite-persist,tier-1,tier-2,tier-3,tier-4}.md exist" {
  [ -f "setup/agent-install/lite.md" ]
  [ -f "setup/agent-install/lite-persist.md" ]
  [ -f "setup/agent-install/tier-1.md" ]
  [ -f "setup/agent-install/tier-2.md" ]
  [ -f "setup/agent-install/tier-3.md" ]
  [ -f "setup/agent-install/tier-4.md" ]
}

@test "cross-link: contexts/{work,projects-personal,personal,hackathons} dirs exist" {
  [ -d "contexts/work" ]
  [ -d "contexts/projects-personal" ]
  [ -d "contexts/personal" ]
  [ -d "contexts/hackathons" ]
}

@test "cross-link: mcp/servers.json exists" {
  [ -f "mcp/servers.json" ]
}

@test "cross-link: NOTICE / COMMERCIAL / CLA / LICENSE / LICENSE-APACHE exist" {
  [ -f "NOTICE" ]
  [ -f "COMMERCIAL.md" ]
  [ -f "CLA.md" ]
  [ -f "LICENSE" ]
  [ -f "LICENSE-APACHE" ]
  [ -f "setup/walter-host/LICENSE" ]
}

@test "cross-link: hooks/{bash-denylist,approval-gate,network-gate,branch-flow-guard,pre-commit-tests}.sh exist" {
  [ -f "hooks/bash-denylist.sh" ]
  [ -f "hooks/approval-gate.sh" ]
  [ -f "hooks/network-gate.sh" ]
  [ -f "hooks/branch-flow-guard.sh" ]
  [ -f "hooks/pre-commit-tests.sh" ]
}

@test "cross-link: contexts/_examples/egress-allowlist.example.txt exists" {
  [ -f "contexts/_examples/egress-allowlist.example.txt" ]
}

@test "cross-link: apps/control-tower/ exists" {
  [ -d "apps/control-tower" ]
}

# ── New deep-dive docs extracted from the v0.5.1 rewrite ───────────────────

@test "cross-link: docs/operational/personas.md exists (extracted from old README)" {
  [ -f "docs/operational/personas.md" ]
}

@test "cross-link: docs/operational/stack-overview.md exists (extracted from old README)" {
  [ -f "docs/operational/stack-overview.md" ]
}

@test "cross-link: docs/operational/walter-bridge.md exists (extracted from old README)" {
  [ -f "docs/operational/walter-bridge.md" ]
}

@test "cross-link: docs/operational/troubleshooting.md exists (extracted from old README)" {
  [ -f "docs/operational/troubleshooting.md" ]
}

@test "cross-link: docs/operational/customization-patterns.md exists (extracted from old README)" {
  [ -f "docs/operational/customization-patterns.md" ]
}

@test "cross-link: docs/operational/resource-budget.md exists (extracted from old README)" {
  [ -f "docs/operational/resource-budget.md" ]
}

@test "cross-link: docs/operational/n8n-workflows.md exists (extracted from old README)" {
  [ -f "docs/operational/n8n-workflows.md" ]
}

@test "cross-link: SUPPORT.md exists at repo root" {
  [ -f "SUPPORT.md" ]
}

@test "README.md Further reading section exists" {
  grep -qF "## Further reading" README.md
}

@test "README.md Further reading links all 7 extracted deep-dive docs" {
  grep -qF "docs/operational/personas.md" README.md
  grep -qF "docs/operational/stack-overview.md" README.md
  grep -qF "docs/operational/walter-bridge.md" README.md
  grep -qF "docs/operational/troubleshooting.md" README.md
  grep -qF "docs/operational/customization-patterns.md" README.md
  grep -qF "docs/operational/resource-budget.md" README.md
  grep -qF "docs/operational/n8n-workflows.md" README.md
}

@test "README.md points to SUPPORT.md for help" {
  grep -qF "SUPPORT.md" README.md
}

# ── Mermaid diagrams + visual polish (readme-craft skill tool #8) ──────────

@test "README.md contains Mermaid architecture diagram" {
  # Top-level "How it fits together" diagram. The skill explicitly
  # endorses Mermaid as the lowest-supply-chain-risk visual tool —
  # native to GitHub Markdown, no external image hosting.
  grep -qF '```mermaid' README.md
  # At least 2 mermaid blocks (architecture + disciplines flow).
  count=$(grep -cF '```mermaid' README.md)
  [ "$count" -ge 2 ]
}

@test "README.md contains discipline-flow diagram with SDD + TDD steps" {
  # The Disciplines section has a flowchart showing SDD → TDD → review
  # → merge gates. Pinned because SDD was missing in the prior cut.
  grep -qE 'SDD|Spec-Driven' README.md
}

# ── Disciplines: SDD + TDD (not just TDD) ──────────────────────────────────

@test "README.md disciplines table includes SDD (Spec-Driven Development)" {
  # Operator-flagged regression: previous version only mentioned TDD.
  # The methodology is SDD + TDD. Pin both.
  grep -qE 'SDD.*Spec-Driven Development|Spec-Driven Development.*SDD' README.md
  grep -qE 'TDD.*Test-Driven Development|Test-Driven Development.*TDD' README.md
}

# ── Per-repo merge policy config ───────────────────────────────────────────

@test "README.md documents walter-repo-config.yaml merge policy" {
  grep -qF "walter-repo-config.yaml" README.md
  grep -qF "auto_merge.enabled" README.md
  grep -qF "docs/operational/repo-config.md" README.md
}

@test "README.md no longer advertises the retired auto-merge touchfile" {
  ! grep -qF ".walter-os/auto-merge-authorized" README.md
}

# ── Per-section deep-dive callouts ─────────────────────────────────────────

@test "README.md has per-section deep-dive callouts (at least 4 📖 markers)" {
  # Each major section ends with a "📖 Deep dive" callout linking to
  # the relevant docs/operational/* file. At least 4 sections should
  # have one (Mode 3 install, Security floor, Catalogs, Configuration,
  # Disciplines, Personas).
  count=$(grep -c '📖' README.md)
  [ "$count" -ge 4 ]
}

# ── ADR-0018 link removed per operator request ─────────────────────────────

@test "README.md does NOT link to ADR-0018 (operator-removed)" {
  ! grep -qF "ADR-0018" README.md
  ! grep -qF "0018-licensing-strategy.md" README.md
}
