# Implementation Plan: walter-oss-ready-docs

**Spec**: `docs/specs/walter-oss-ready-docs.md`
**PR**: #51 (v0.2.0 OSS launch chain)
**Branch**: `feature/oss-ready-docs` (target: `docs/business-pack-eval` or `main` per merge order)

---

## Preflight: read before starting

Before Task 1, verify:
1. `COMMERCIAL.md` exists at repo root (PR #48 deliverable). If it does not,
   confirm that PR #48 has been merged or this branch is based on it.
2. `.github/ISSUE_TEMPLATE/` directory does or does not exist — Task 5 will create it.
3. `tests/oss/` directory exists (confirmed: `depersonalization.bats` and
   `license-files.bats` are already there).

---

## Task 1: Seed CHANGELOG.md [AC-5]

**Time estimate**: 8 minutes

**Files**:
- `CHANGELOG.md` (new)

**Change**: Create CHANGELOG.md following Keep a Changelog 1.1 schema.

Exact structure to produce:

```markdown
<!-- Keep a Changelog 1.1 | SemVer -->
# Changelog

All notable changes to Walter-OS are documented in this file.

Format: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/)

---

## [Unreleased]

---

## [0.2.0] — 2026-05-11

### Added

- Multi-provider Walter-Bridge: LiteLLM expansion with subscription-based
  provider passthrough for Claude Pro, Gemini Advanced, and ChatGPT Plus
  (PR #47, `docs/specs/walter-bridge-litellm-expansion.md`)
- CLI client modules for major LLM providers: `walter-bridge ask`,
  `walter-bridge chat`, provider-specific entrypoints (PR #47)
- AGPLv3 license — Walter-OS is now licensed under the GNU Affero General
  Public License v3, copyright Xipher Labs (PR #48)
- `COMMERCIAL.md` — dual-licensing hook for future commercial licensing from
  Xipher Labs; `licensing@xipherlabs.xyz` placeholder
  (PR #48, `docs/specs/walter-oss-license-switch.md`)
- Personal overlay layer (`~/.config/walter-os/overlay/`) — operator-specific
  config lives outside the repo; OSS core ships generic templates
  (PR #47, `docs/specs/phase-w-5-depersonalization.md`)
- `contexts/_examples/` — labeled real-world examples for work, personal
  projects, and personal life contexts (PR #47)
- `walter-personal` skeleton pattern — `contexts/_examples/walter-personal-skeleton/`
  template for an operator's private git overlay repo; `--from-skeleton` and
  `--git-clone` flags on `setup/personal-overlay-init.sh`
  (PR #49, `docs/specs/walter-personal-skeleton.md`)
- OSS community health files: README rewrite (adopter-first), CONTRIBUTING.md,
  SECURITY.md, CODE_OF_CONDUCT.md, .github/ issue and PR templates (this PR)

### Changed

- `README.md` — rewritten as adopter-first with Quick Start, persona
  orientation (Builder / Founder / Operator), and docs index. Deep
  reference content preserved below the fold.
- `LICENSE` — switched from Apache-2.0 to AGPLv3 (PR #48)
- `NOTICE` — updated to reflect AGPLv3 and Xipher Labs copyright (PR #48)
- `contexts/work/AGENTS.md`, `contexts/projects-personal/AGENTS.md`,
  `contexts/personal/AGENTS.md` — genericized; personal identifiers and
  country-specific references moved to overlay and `_examples/` (PR #47)

---

[Unreleased]: https://github.com/xipher-labs/walter-os/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/xipher-labs/walter-os/releases/tag/v0.2.0
```

**RED step**: Before writing the file, write/run this bats assertion (it will fail):
```bash
# In tests/oss/oss-ready-docs.bats — initial skeleton
@test "CHANGELOG.md exists" {
  [[ -f "$REPO_ROOT/CHANGELOG.md" ]]
}
@test "CHANGELOG.md has [0.2.0] section" {
  grep -q "\[0\.2\.0\]" "$REPO_ROOT/CHANGELOG.md"
}
```

**Verify**: `bats tests/oss/oss-ready-docs.bats` — both CHANGELOG assertions pass.
`grep "\[0\.2\.0\]" CHANGELOG.md` returns the dated line.

---

## Task 2: CONTRIBUTING.md + CODE_OF_CONDUCT.md [AC-2, AC-4]

**Time estimate**: 12 minutes

**Files**:
- `CONTRIBUTING.md` (new)
- `CODE_OF_CONDUCT.md` (new)

### CONTRIBUTING.md

Exact structure:

```markdown
# Contributing to Walter-OS

Walter-OS is developed by Xipher Labs and accepts contributions under the
GNU Affero General Public License v3.

**By submitting a pull request you agree that your contribution is
AGPLv3-compatible and may be used, distributed, and modified under the terms
of the AGPLv3.** See [LICENSE](LICENSE) for the full text.

---

## Before you start

Walter-OS is a self-hostable single-operator framework. Contributions that
improve portability, documentation, skills, or the Walter-Bridge are
especially welcome. Contributions that add personal or company-specific
configuration belong in your personal overlay, not in this repo.

---

## Dev setup

```bash
git clone https://github.com/xipher-labs/walter-os
cd walter-os

# Scaffold your personal overlay (required before install)
./setup/personal-overlay-init.sh --from-skeleton

# Install Walter-OS (dev mode — no symlinks to ~/.claude production config)
./install.sh --dev
```

### Required plugin

Walter-OS requires the `obra/superpowers` plugin in Claude Code:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Then restart Claude Code. The plugin provides `/brainstorm`, `/write-plan`,
`/execute-plan` slash commands and the TDD discipline skills used in every PR.

---

## Workflow

All non-trivial contributions follow the plan-first discipline:

1. **Brainstorm** — `/brainstorm` to refine the idea.
2. **Spec + plan** — `/write-plan` produces `docs/specs/<slug>.md` and a task
   plan. For tiny/small changes, an inline description in the commit body is
   sufficient.
3. **TDD** — Write failing tests first (RED), then the minimum implementation
   (GREEN), then refactor. Never skip RED.
4. **Commit** — Conventional commits (see below). Each task in the plan is one
   atomic commit.
5. **PR** — Open against `dev` (not `main`). Fill in the PR template.
6. **Review** — Two rounds minimum. Internal Claude reviewer subagent + GitHub
   Copilot (auto-requested via REST API, see PR template).

Branch flow: `feature/<slug>` → `dev` → `staging` → `main`.
Never target `main` directly.

---

## Conventional commits

| Prefix | When |
|---|---|
| `feat:` | new capability, new skill, new command |
| `fix:` | bug fix |
| `docs:` | documentation only |
| `refactor:` | no behavior change |
| `test:` | test-only change |
| `chore:` | dep bumps, tooling |
| `security:` | security fix or hardening |
| `perf:` | performance improvement |

Rules:
- Subject line: ≤72 characters, imperative mood ("add X" not "added X").
- Body: explain *why*, not *what* (the diff shows what).
- Footer: `Refs: docs/specs/<slug>.md` and `Closes #<issue>` if applicable.

---

## CI gates (must be green before requesting review)

- `bats tests/` — all bats suites pass
- `shellcheck hooks/ setup/` — no errors
- `markdownlint` — if installed locally (`npm i -g markdownlint-cli`)
- Build: `cd apps/control-tower && pnpm build` (if touching Control Tower)

---

## Code of Conduct

This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md).
By participating you agree to abide by its terms.
```

### CODE_OF_CONDUCT.md

Fetch the verbatim Contributor Covenant 2.1 text from
`https://www.contributor-covenant.org/version/2/1/code_of_conduct/` and:
- Replace `[INSERT CONTACT METHOD]` with `conduct@xipherlabs.xyz`
- Replace `[INSERT COMMUNITY NAME]` with `Walter-OS` (in the Enforcement section
  if the template uses it — v2.1 uses `[INSERT COMMUNITY NAME]` in the preamble
  attribution line only; check the actual text)
- Add this HTML comment on the line immediately after `conduct@xipherlabs.xyz`:
  `<!-- TODO(pre-launch): set up conduct@xipherlabs.xyz mailbox -->`

**RED step**: Add to `tests/oss/oss-ready-docs.bats`:
```bash
@test "CONTRIBUTING.md exists" {
  [[ -f "$REPO_ROOT/CONTRIBUTING.md" ]]
}
@test "CONTRIBUTING.md mentions superpowers" {
  grep -q "superpowers" "$REPO_ROOT/CONTRIBUTING.md"
}
@test "CONTRIBUTING.md mentions AGPLv3" {
  grep -q "AGPLv3" "$REPO_ROOT/CONTRIBUTING.md"
}
@test "CODE_OF_CONDUCT.md exists" {
  [[ -f "$REPO_ROOT/CODE_OF_CONDUCT.md" ]]
}
@test "CODE_OF_CONDUCT.md is Contributor Covenant 2.1" {
  grep -q "Contributor Covenant" "$REPO_ROOT/CODE_OF_CONDUCT.md"
  grep -q "2\.1" "$REPO_ROOT/CODE_OF_CONDUCT.md"
}
```

**Verify**: All 5 new bats assertions pass. `grep "TODO(pre-launch)" CODE_OF_CONDUCT.md`
returns the conduct mailbox TODO line.

---

## Task 3: SECURITY.md [AC-3, AC-10]

**Time estimate**: 8 minutes

**Files**:
- `SECURITY.md` (new)

Exact structure:

```markdown
# Security Policy

## Supported versions

Walter-OS is currently in early development (v0.2.x). Security fixes are
applied to the current release series only.

| Version | Supported |
|---|---|
| 0.2.x | yes |
| 0.1.x | no (EOL) |

---

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: <!-- TODO(pre-launch): set up security@xipherlabs.xyz mailbox -->
`security@xipherlabs.xyz`

Include:
- Description of the vulnerability and its potential impact
- Steps to reproduce (with as much detail as is safe to share)
- Any proof-of-concept code (redact credentials)
- Your preferred contact for follow-up

We aim to acknowledge reports within 48 hours and provide a status update
within 7 days. We request a **90-day responsible disclosure window** before
public disclosure to allow time for a fix and coordinated release.

---

## PGP key

A PGP key for encrypted reports will be published at
`keys.openpgp.org` under `security@xipherlabs.xyz` before the v0.2.0
public launch. Until then, unencrypted email is acceptable.

Fingerprint placeholder: `[TO BE PUBLISHED PRE-LAUNCH]`

---

## Bug bounty

We do not currently run a bug bounty program. Walter-OS is solo-maintained.
We are grateful for responsible disclosure and will acknowledge contributors
in release notes.

---

## Scope

**In scope**:
- Walter-OS source code (all files in this repository)
- Default configuration shipped in the repo
- CI pipeline and GitHub Actions workflows
- Install scripts (`install.sh`, `setup/`)

**Out of scope**:
- Third-party dependencies — report those to their upstream maintainers
- Infrastructure operated by adopters running their own Walter-OS instances
- The `external/` submodule tree (those carry their own security policies)
- Vulnerabilities requiring physical access to the operator's machine

---

## Cross-reference

For commercial licensing enquiries (separate from security), see [COMMERCIAL.md](COMMERCIAL.md).
```

**RED step**: Add to `tests/oss/oss-ready-docs.bats`:
```bash
@test "SECURITY.md exists" {
  [[ -f "$REPO_ROOT/SECURITY.md" ]]
}
@test "SECURITY.md has security@xipherlabs.xyz" {
  grep -q "security@xipherlabs.xyz" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md has TODO(pre-launch) comment" {
  grep -q "TODO(pre-launch)" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md states no bug bounty" {
  grep -q "do not currently run a bug bounty" "$REPO_ROOT/SECURITY.md"
}
```

**Verify**: 4 new assertions pass. `grep -rn "TODO(pre-launch)" *.md .github/` returns
at least 2 matches (conduct, security — licensing was PR #48). `grep "90-day" SECURITY.md`
returns the disclosure window line.

---

## Task 4: README.md rewrite [AC-1]

**Time estimate**: 15 minutes

**Files**:
- `README.md` (full rewrite — read existing content first, preserve
  reference sections, reorient structure)

**Change**: Replace the current README with an adopter-first document.

Structural outline (implement in this order):

```
<div align="center">
  [badges: AGPL v3 | status: alpha | by Xipher Labs]
  # Walter-OS
  "A self-hostable AI-agent operations framework by Xipher Labs"
  [one-paragraph value prop]
</div>

---

## Who is this for?

[Three-persona table: Builder | Founder | Operator]

---

## 60-second Quick Start

[git clone + ./install.sh + superpowers plugin install]
[what you get after install]

---

## What is Walter-OS?

[Three-layer table: Agent contract | Skills+Agents | Walter-VM+Council]
[same architecture ASCII diagram — preserved from current README]
[Philosophy paragraph — preserved]

---

## Docs index

[Links: CONTRIBUTING | SECURITY | CODE_OF_CONDUCT | CHANGELOG]
[Links: docs/specs/ | docs/decisions/ (ADRs)]
[Links: superpowers plugin | Walter Council v2 spec]

---

## Built with

[Named stack: Claude Code · Codex CLI · obra/superpowers · LiteLLM · Forgejo
· Plane · Penpot · Grafana · n8n · Headscale/Tailscale · Hetzner · Cloudflare]

---

[Deep reference sections — PRESERVED from current README, moved below fold]:
## Walter Council v2
## Layered context model
## Personal overlay
## Required plugin: obra/superpowers
## Repo structure
## Disciplines (universal)
## MCP catalog
## Walter-VM — services
## Multi-account auth
## Cross-device sync
## Secrets distribution
## walter-os CLI reference
## Customization (fork checklist)
## Status / phases

---

## Sponsor / follow

[operator-handle GitHub link | xipher-labs org link]

---

## License

[![License: AGPL v3](badge)] AGPLv3. See LICENSE.
"© 2026 Xipher Labs — Walter-OS"
```

**Badge markdown** for header (copy exactly):
```markdown
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Status: Alpha](https://img.shields.io/badge/status-alpha-orange.svg)](https://github.com/xipher-labs/walter-os/releases)
```

**Value prop paragraph** (use this text):
> Walter-OS is a self-hostable, single-operator AI framework that turns Claude Code,
> Codex CLI, and Cursor into a coherent agentic system. One repo drives your agent
> contracts, skills, MCP catalog, hooks, and the Walter Council — six specialized
> agents that work autonomously on your issue tracker while you're away. Fork the
> patterns, configure your personal overlay, and operate like a team of ten.

**Personas table**:
| Persona | You are... | Walter-OS gives you... |
|---|---|---|
| **Builder** | A developer or indie hacker shipping products fast | Agent discipline, TDD scaffolding, hackathon-spinup, brand-creation |
| **Founder** | Running a small company with a lean technical team | Council autonomy, issue-to-PR pipeline, DevRel analytics, spend controls |
| **Operator** | Managing homelab / self-hosted infra | Walter-VM compose stack, Hetzner provisioning, secrets management, uptime monitoring |

**Important**: keep the existing `> [!IMPORTANT]` callout about the repo being
opinionated — it sets honest expectations. Move it into the "What is Walter-OS?"
section, not the hero.

**RED step**: Add to `tests/oss/oss-ready-docs.bats`:
```bash
@test "README.md mentions Xipher Labs" {
  grep -q "Xipher Labs" "$REPO_ROOT/README.md"
}
@test "README.md mentions AGPL" {
  grep -q "AGPL" "$REPO_ROOT/README.md"
}
@test "README.md has 60-second Quick Start" {
  grep -q "Quick Start\|quick start\|quickstart" "$REPO_ROOT/README.md"
}
@test "README.md has persona section" {
  grep -q "Builder\|Founder\|Operator" "$REPO_ROOT/README.md"
}
```

**Verify**: 4 new assertions pass. Spot-check: `grep "Xipher Labs" README.md` returns
≥3 matches (hero, footer, license section). `grep "Quick Start" README.md` returns the
section heading.

---

## Task 5: .github/ templates [AC-6, AC-7, AC-8]

**Time estimate**: 10 minutes

**Files**:
- `.github/ISSUE_TEMPLATE/bug.md` (new — directory may need creating)
- `.github/ISSUE_TEMPLATE/feature.md` (new)
- `.github/PULL_REQUEST_TEMPLATE.md` (new)

### .github/ISSUE_TEMPLATE/bug.md

```markdown
---
name: Bug report
about: Something is not working as expected
labels: bug
---

## Environment

- **Walter-OS version** (from `walter-os --version` or `git describe --tags`):
- **Compose profile** (core / devrel / design / assistant / all):
- **OS + version** (e.g. macOS 15.4 Apple Silicon):
- **Claude Code version** (from `claude --version`):

## Steps to reproduce

1.
2.
3.

## Expected behavior

<!-- What should have happened? -->

## Actual behavior

<!-- What happened instead? -->

## Logs

<!-- Paste relevant log output. Redact any secrets, domains, or personal data. -->

```
paste logs here
```

## Additional context

<!-- Any other context, screenshots, or config snippets (redacted). -->
```

### .github/ISSUE_TEMPLATE/feature.md

```markdown
---
name: Feature request
about: Propose a new capability or improvement
labels: enhancement
---

## Persona

<!-- Which persona does this benefit? Pick one (or explain if multiple). -->
- [ ] Builder (developer / indie hacker)
- [ ] Founder (small company / lean team)
- [ ] Operator (homelab / self-hosted infra)

## Use case

<!-- What are you trying to accomplish? Be specific — describe the workflow,
     not the feature. -->

## Proposed solution

<!-- How might Walter-OS address this? Rough sketch is fine — the spec
     process will refine it. -->

## Alternatives considered

<!-- What have you already tried, or what other approaches could work? -->

## Additional context

<!-- Links to prior discussion, related specs (docs/specs/), or external art. -->
```

### .github/PULL_REQUEST_TEMPLATE.md

```markdown
## Spec

**Spec**: `docs/specs/<slug>.md`
<!-- Link to the spec this PR implements. For tiny/small changes, describe
     the change inline in 2-3 sentences instead. -->

## Problem summary

<!-- 1-2 sentences: what was wrong or missing before this PR? -->

## Changes

<!-- Brief description of what changed. The diff shows what; explain why. -->

## Test plan

- [ ] All bats tests pass (`bats tests/`)
- [ ] Acceptance criteria in the spec have corresponding test assertions
- [ ] `shellcheck` clean on any new shell scripts
- [ ] `markdownlint` clean on any new Markdown files (if `markdownlint-cli` installed)
- [ ] If adding contact emails: `grep -rn "TODO(pre-launch)" . --include="*.md"` returns
      the expected count
- [ ] Build clean (`cd apps/control-tower && pnpm build`) if Control Tower touched

## Copilot review

After opening this PR, request Copilot review via:

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<NUM>/requested_reviewers \
  --input - <<<'{"reviewers":["copilot-pull-request-reviewer[bot]"]}'
```

- [ ] Copilot review requested

## Checklist

- [ ] Branch targets `dev` (not `main`)
- [ ] Conventional commit subject ≤72 chars, imperative mood
- [ ] Spec updated if acceptance criteria changed during implementation
- [ ] `Refs: docs/specs/<slug>.md` in commit footer (for major tasks)
```

**RED step**: Add to `tests/oss/oss-ready-docs.bats`:
```bash
@test ".github/ISSUE_TEMPLATE/bug.md exists" {
  [[ -f "$REPO_ROOT/.github/ISSUE_TEMPLATE/bug.md" ]]
}
@test ".github/ISSUE_TEMPLATE/bug.md has YAML frontmatter with name and labels" {
  grep -q "^name:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/bug.md"
  grep -q "^labels:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/bug.md"
}
@test ".github/ISSUE_TEMPLATE/feature.md exists" {
  [[ -f "$REPO_ROOT/.github/ISSUE_TEMPLATE/feature.md" ]]
}
@test ".github/ISSUE_TEMPLATE/feature.md has YAML frontmatter with name and labels" {
  grep -q "^name:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/feature.md"
  grep -q "^labels:" "$REPO_ROOT/.github/ISSUE_TEMPLATE/feature.md"
}
@test ".github/PULL_REQUEST_TEMPLATE.md exists" {
  [[ -f "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md" ]]
}
@test ".github/PULL_REQUEST_TEMPLATE.md mentions Copilot" {
  grep -q "Copilot" "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
}
```

**Verify**: 6 new assertions pass. Total bats assertion count in the file is ≥19.

---

## Task 6: Finalize bats suite + full verification [AC-9, AC-10]

**Time estimate**: 8 minutes

**Files**:
- `tests/oss/oss-ready-docs.bats` (finalize — consolidate all assertions written
  incrementally in Tasks 1-5 into a single clean file)

**Final bats file structure**:

```bash
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
  grep -q "Quick Start\|quick start\|quickstart" "$REPO_ROOT/README.md"
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
@test "CONTRIBUTING.md mentions AGPLv3" {
  grep -q "AGPLv3" "$REPO_ROOT/CONTRIBUTING.md"
}

# --- SECURITY.md content ---
@test "SECURITY.md has security@xipherlabs.xyz" {
  grep -q "security@xipherlabs.xyz" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md has TODO(pre-launch) comment" {
  grep -q "TODO(pre-launch)" "$REPO_ROOT/SECURITY.md"
}
@test "SECURITY.md states no bug bounty" {
  grep -q "do not currently run a bug bounty" "$REPO_ROOT/SECURITY.md"
}

# --- CODE_OF_CONDUCT.md content ---
@test "CODE_OF_CONDUCT.md is Contributor Covenant 2.1" {
  grep -q "Contributor Covenant" "$REPO_ROOT/CODE_OF_CONDUCT.md"
  grep -q "2\.1" "$REPO_ROOT/CODE_OF_CONDUCT.md"
}

# --- CHANGELOG.md content ---
@test "CHANGELOG.md has [0.2.0] section" {
  grep -q "\[0\.2\.0\]" "$REPO_ROOT/CHANGELOG.md"
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

# --- Pre-launch mailbox TODO pattern ---
@test "at least 2 TODO(pre-launch) mailbox markers exist across md files" {
  count=$(grep -rn "TODO(pre-launch)" "$REPO_ROOT" --include="*.md" | wc -l | tr -d ' ')
  [[ "$count" -ge 2 ]]
}
```

**Final verification run**:

```bash
# All OSS bats suites pass
bats tests/oss/

# markdownlint (skip gracefully if not installed)
if command -v markdownlint &>/dev/null; then
  markdownlint README.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md CHANGELOG.md
fi

# Pre-launch mailbox grep — operator checklist
grep -rn "TODO(pre-launch)" . --include="*.md"
# Expected: ≥3 lines (security@, conduct@, and licensing@ from COMMERCIAL.md)
```

**Verify**: `bats tests/oss/` exits 0. All 23+ assertions pass. The mailbox grep
returns ≥3 lines. Commit the final bats file as part of this task.

---

## Commit order

```
feat: seed CHANGELOG.md for v0.2.0 (Keep a Changelog 1.1)
Refs: docs/specs/walter-oss-ready-docs.md

feat: add CONTRIBUTING.md and CODE_OF_CONDUCT.md (Contributor Covenant 2.1)
Refs: docs/specs/walter-oss-ready-docs.md

feat: add SECURITY.md with responsible disclosure policy
Refs: docs/specs/walter-oss-ready-docs.md

feat: rewrite README.md as adopter-first (Builder/Founder/Operator)
Refs: docs/specs/walter-oss-ready-docs.md

feat: add .github/ issue templates and PR template
Refs: docs/specs/walter-oss-ready-docs.md

test: add tests/oss/oss-ready-docs.bats (23 assertions)
Refs: docs/specs/walter-oss-ready-docs.md
```

---

## Pre-launch operator checklist (not part of this PR — for reference)

After PR #51 merges, before tagging v0.2.0:
- [ ] Set up `security@xipherlabs.xyz` mailbox
- [ ] Set up `conduct@xipherlabs.xyz` mailbox
- [ ] `licensing@xipherlabs.xyz` (COMMERCIAL.md — PR #48 item)
- [ ] Publish PGP key at `keys.openpgp.org` and update SECURITY.md fingerprint
- [ ] Confirm canonical org: `xipher-labs/walter-os` vs `xipher-labs/walter-os`
      (update CHANGELOG footer links and README Quick Start URL if switching)
- [ ] Confirm status badge text: "alpha" vs "early alpha"
- [ ] Tag v0.2.0 and create GitHub Release
