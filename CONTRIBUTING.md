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

# Wire up the git hooks (gitleaks pre-commit secret scan)
# This configures core.hooksPath = .githooks and verifies gitleaks is installed.
bash scripts/setup-githooks.sh
```

> **gitleaks required**: Walter-OS ships a pre-commit hook that blocks commits
> containing secrets. Install gitleaks before making any commits:
> `brew install gitleaks` (macOS) or `apt install gitleaks` (Debian/Ubuntu).
> The hook uses `.githooks/pre-commit` (tracked in the repo via `core.hooksPath`).
> Run `bash scripts/setup-githooks.sh` once after cloning to activate it.

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

Walter-OS uses a 3-round review pattern (Copilot → Codex → collaborative).
See `AGENTS.md` for details.

Branch flow: `feature/<slug>` → `dev` → `staging` → `main`.
Never target `main` directly.

---

## Title convention

All PR titles and issue titles must follow the `[TYPE] -CATEGORY- title` format.
CI enforces this: PRs **fail** on mismatch; issues **warn** (allowing maintainer edits).

### Format

```
[TYPE] -CATEGORY- title body
```

**TYPE** (uppercase, in brackets — 5 allowed values):

| TYPE | When to use |
|---|---|
| `FEAT` | new feature, new skill, new command |
| `FIX` | bug fix |
| `DOCS` | documentation only |
| `CHORE` | maintenance, dependency bumps, cleanup |
| `TEST` | test-only changes |

**CATEGORY** (uppercase, in dashes — 8 allowed values):

| CATEGORY | Scope |
|---|---|
| `SECURITY` | auth, crypto, secrets, vulnerabilities, supply chain |
| `BUSINESS` | pricing, sales, marketing, revenue model |
| `COMPLIANCE` | GDPR, SOC2, PHI, legal frameworks |
| `OPERATIONS` | DevOps, infrastructure, monitoring, deployment |
| `TECHNICAL` | engineering, refactoring, architecture, code quality |
| `CUSTOMER` | UX, onboarding, user-facing features |
| `CONTENT` | content generation, marketing assets, copy |
| `LEARNING` | learning loops, knowledge management, retrospection |

**Title body**: sentence case, imperative mood, <=60 characters, no trailing period.

### Examples

Valid:
- `[FEAT] -BUSINESS- saas-metrics-dashboard skill (MRR/ARR/churn)`
- `[FIX] -SECURITY- enforce CCR_APIKEY on sub-router /v1 routes`
- `[CHORE] -OPERATIONS- bump hcloud-cli to v1.45 + audit baseline`
- `[DOCS] -COMPLIANCE- expand GDPR self-assessment template`

Invalid:
- `feat: add new skill` — conventional-commit format, no category
- `[feat] -security- add thing` — lowercase type and category
- `Add new feature` — no type or category
- `[FEAT] add thing` — missing category dashes

### Local pre-check

Before running `gh pr create`, validate your title locally:

```bash
./hooks/pr-title-validator.sh "[FEAT] -BUSINESS- your title here"
# exit 0 = valid, exit 1 = invalid (prints error)
```

CI runs the same regex; the hook saves a round-trip.

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

---

## Contributors

Walter-OS is maintained by **Xipher Labs**.

### Core

- **Xipher Labs maintainers** — original design and maintenance

### Collaborators

- **Juan Marchetto** ([@JuanMarchetto](https://github.com/JuanMarchetto)) — collaborator; surfaced the idea + execution path for the v0.2.0 OSS launch

### Acknowledgments

Walter-OS builds on the shoulders of others. Selected upstream work that shaped this framework:

- [Anthropic Claude Code](https://claude.com/claude-code) + the Claude Agent SDK — agent runtime + tool-use protocol
- [`obra/superpowers`](https://github.com/obra/superpowers-marketplace) by Jesse Vincent — methodology skills (brainstorming / writing-plans / executing-plans / test-driven-development / systematic-debugging / verification-before-completion)
- [LiteLLM](https://github.com/BerriAI/litellm) — model gateway
- [Hermes Agent](https://hermes-agent.nousresearch.com/) by Nous Research — alternative agent runtime
- [`musistudio/claude-code-router`](https://github.com/musistudio/claude-code-router) — Claude Code routing
- Hetzner Cloud — affordable EU compute that makes self-hosting practical

If you're building on top of Walter-OS, open an issue + we'll add you here.
