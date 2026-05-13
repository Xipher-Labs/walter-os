# AGENTS.md — Walter-OS Global

> Source of truth for agent behavior across Claude Code, Codex CLI, Cursor, and any
> tool that reads `AGENTS.md`. Loaded for every project unless overridden by a more
> specific file (context-level or repo-level).

## Operator profile

<!-- -----------------------------------------------------------------------
  PERSONALIZATION: Replace this generic profile with your own.
  Create ~/.config/walter-os/overlay/profile.md and add a section like:

    ## Operator profile (personal overlay)
    You are working with [Your Name], [your role] at [your company/project],
    based in [your location]. [Disciplines]. [Language preferences].
    Tone: [your preferred tone].

  The overlay file is loaded by the global cascade when present. See
  setup/personal-overlay-init.sh to scaffold the overlay directory.

  For real-world examples, see contexts/_examples/ — the labeled example files
  show a complete populated work context you can learn from.
  ----------------------------------------------------------------------- -->

You are working with **the operator**. Tone: direct, no padding, no sycophancy,
no "great question!" Push back on bad ideas with reasoning. When uncertain, say
so explicitly. Accuracy beats agreement.

The operator has not yet configured a personal profile overlay. Run
`setup/personal-overlay-init.sh` to scaffold `~/.config/walter-os/overlay/`
and add your personal profile there.

## Context layers

This file is the **global** layer. Two more layers stack on top:

1. **Context layer** — depending on cwd or env var:
   - Inside `~/work/*` → also load `<walter-os>/contexts/work/AGENTS.md` (work context)
   - Inside `~/Projects-Personal/*` → also load `<walter-os>/contexts/projects-personal/AGENTS.md` (personal dev projects)
   - Inside `~/personal/*` → also load `<walter-os>/contexts/personal/AGENTS.md` (personal non-dev life: finance, health, journaling)
   - `WALTER_CONTEXT=hackathons` set (any directory) → also load `<walter-os>/contexts/hackathons/AGENTS.md` (hackathon / time-boxed events)

   **Personal overlay** — if `~/.config/walter-os/overlay/contexts/<context>/AGENTS.md`
   exists, it is loaded instead of the repo's generic template. The overlay lets you
   maintain personal configuration out-of-repo. Run `setup/personal-overlay-init.sh`
   to scaffold the skeleton.

   For the full cascade diagram, standards table, and customization guide, see
   `docs/operational/operator-contexts.md`.
2. **Repo layer** — any `AGENTS.md` at the project root.

Conflicts resolve **most-specific-wins**: repo > context > global.

## Plugins (required)

Walter-OS depends on **`obra/superpowers`** — Anthropic's official-marketplace
plugin by Jesse Vincent that ships battle-tested methodology skills:
`brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`,
`systematic-debugging`, `using-git-worktrees`, `verification-before-completion`,
plus the `/brainstorm`, `/write-plan`, `/execute-plan` slash commands.

Install in Claude Code (one-time, per machine):

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Then restart Claude Code. Walter-OS skills layer on top — where there's
overlap, superpowers wins. Walter-OS provides domain-specific skills for
common operator areas (branding, hackathons, DevRel, regulatory research,
Solana infrastructure, security auditing). Operator-specific skills live in
the personal overlay.

## Universal disciplines (apply everywhere)

### Task rigor levels (tiny / small / major)

These levels apply **per task, not per context**. The context (work /
projects-personal / personal) affects approval and PR gates, but it does not
lower the minimum rigor level.

| Level | Criteria | Plan / Spec | Tests | Review | Commit |
|---|---|---|---|---|---|
| **tiny** | typo, single-line config, dep bump, comment fix | none | lint + typecheck | self | atomic |
| **small** | bug fix < 50 LOC, single function add, refactor < 100 LOC | inline 2-3 sentences in commit body | RED-GREEN-REFACTOR (TDD mandatory) | self + reviewer subagent in projects-personal | atomic |
| **major** | new feature, schema change, refactor > 200 LOC, anything in critical path (auth, money, PHI, audit-trail) | spec in `docs/specs/<slug>.md` + plan via `/write-plan` | full TDD + DoD validator | reviewer subagent + Copilot + security-auditor agent when applicable | atomic per task in plan |

**Auto-escalate to major** (regardless of LOC):
- Any change in `auth/`, `crypto/`, or code that moves money (Solana TX, Stripe).
- Any change that touches PHI or `personal/health/*`.
- Any change to an audit log for a project that requires traceability (tender history, patient access log, financial audit trail).
- Any production DB migration.
- Any change to Walter-OS hooks or configs that affects multiple projects.

**How the agent applies this**:
1. Before starting, classify the task. If two levels seem plausible, choose the
   higher one.
2. Tell the operator: "This is tiny/small/major because X. Proceeding with Y rigor."
3. If an apparently tiny change grows, **escalate in place**: stop, reclassify,
   then resume with the correct workflow.

**Not valid reasons to lower rigor**:
- "It is only for feature/*" — major is still major.
- "It is a POC" — if it will remain, use full rigor; scratch work goes in `sandbox/`.
- "It is urgent" — shortcuts on major work create incidents that cost far more
  than the time saved.

### Brainstorm → Plan → Test → Code → Review → Verify

No code is written without a written plan. The flow uses superpowers slash
commands:

1. `/brainstorm` — refine the rough idea before any concrete planning. The
   `brainstorming` skill drives this.
2. `/write-plan` — produce `docs/specs/<slug>.md` with the spec (problem,
   decisions, acceptance criteria, non-goals) plus a plan with 2–5 minute
   tasks, exact file paths, and verification steps per task.
3. `/execute-plan` — dispatch task-by-task to subagents under TDD discipline.

Each task runs RED (failing test) → GREEN (minimum code) → REFACTOR →
COMMIT. Skipping RED is a violation. `test-driven-development` (from
superpowers) enforces this.

### Tests cover three layers

1. **Code tests** — unit, integration, e2e (Playwright/Cypress).
2. **Definition of Done tests** — every acceptance criterion in the spec must have
   a test that maps to it. The `definition-of-done-validator` skill verifies
   coverage before allowing PR creation.
3. **Business workflow tests** — for projects in regulated domains, tests
   live in `tests/business/<project>/` and validate end-to-end legal/operational
   flows, not just code paths.

### Branch flow (non-negotiable)

```
feature/<slug> → dev → staging → main
```

- `dev`: local docker-compose, Postgres in container, `.env.local` only.
- `staging`: Vercel + Supabase staging project, anonymized realistic data.
- `main`: production. Tagged with semver on merge.

PRs must target the next level. Skipping levels is blocked by
`hooks/branch-flow-guard.sh`. Hotfix to main requires `--allow-branch-skip`
flag + justification in PR body.

Exception on record: the six Council v2 branches (F through V) were cut from
each other in a chain with no intermediate `dev` branch. Each PR body documents
the `--allow-branch-skip` justification. Post-merge, the `dev` branch will be
re-established.

### Definition of Done

A task is "done" only when **all** of these are true:

- [ ] Spec exists at `docs/specs/<slug>.md` and is up to date
- [ ] All acceptance criteria have corresponding tests
- [ ] All tests pass: unit + integration + e2e + DoD validator
- [ ] Lint + typecheck + format clean
- [ ] Security scan clean (`cargo audit` / `npm audit` / equivalent)
- [ ] Build clean
- [ ] Reviewer subagent has approved or comments resolved
- [ ] If staging: smoke test recorded as evidence (gif/video)
- [ ] If main: changelog updated + semver tag

The `verification-before-completion` workflow enforces this list.

### Review loop (standard pattern for every substantive PR)

**Round 1 — Copilot**
1. Claude opens the PR + immediately requests Copilot review via the REST
   API pattern below.
2. Copilot returns findings (typically within 5–15 min).
3. Claude addresses each finding: one commit per finding, conventional
   commit message, `Refs: copilot-review-round-1` in the footer.
4. Claude re-requests Copilot review.

**Round 2 — Codex cross-review (standard, NOT a fallback)**
5. Once Copilot Round 1 fixes are pushed, Claude invokes Codex CLI:
   ```bash
   CODEX_HOME=/tmp/codex-minimal codex review --base <target-branch> \
     > /tmp/codex-review.txt 2>&1
   ```
   (See Codex bypass pattern below if `~/.codex/config.toml` has parse
   errors.)
6. Codex independently audits the PR — it catches what Copilot misses:
   cross-file deployment-flow issues, compose/env-template drift, supply-
   chain gaps, hidden security regressions.
7. Claude addresses each Codex finding: one commit per finding,
   `Refs: codex-review-round-2` in the footer.
8. Claude re-requests Copilot review (so Copilot sees the Codex-driven
   fixes too).

**Round 3 — Collaborative (only if findings remain after Round 2)**
9. If Copilot Round 2 or any verification step still flags issues: Claude
   and Codex review together (Claude reads Codex output + applies fixes;
   Codex re-runs after each fix).
10. After Round 3, if findings still remain → **ESCALATE to operator**.
    Do not proceed to merge.

**Merge criteria** — any of these triggers merge:
- Round 1 returns clean (rare for substantive PRs)
- Round 2 returns clean
- Round 3 returns clean
- Remaining findings are P3 cosmetic — operator may choose to defer to a
  post-merge cleanup PR

**When Copilot is unavailable** (PR > 20k LOC cap, or repeated capacity
refusals): skip Copilot, run Codex twice (as Round 1 and Round 2). Or
split the PR.

**How to auto-request Copilot review** (mandatory after every `gh pr create`):

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<NUM>/requested_reviewers \
  --input - <<<'{"reviewers":["copilot-pull-request-reviewer[bot]"]}'
```

- Bot login is `Copilot` (id `175728472`), but the GraphQL endpoints
  (`gh pr edit --add-reviewer copilot|github-copilot|...`) all fail with
  `Could not resolve user/team`. Only the REST `requested_reviewers`
  endpoint works.
- Validation: response JSON has `requested_reviewers[].login == "Copilot"`.
- **This is part of the agent's `gh pr create` reflex** — don't open a PR
  without it. If you skip the call you've half-finished Round 1 and Copilot
  won't post a review at all.

**How to invoke Codex review** (mandatory in every substantive PR):

```bash
# If ~/.codex/config.toml has parse errors, use the minimal bypass that
# still inherits the operator's auth.json:
mkdir -p /tmp/codex-minimal \
  && echo 'approval_policy = "never"' > /tmp/codex-minimal/config.toml \
  && cp ~/.codex/auth.json /tmp/codex-minimal/
CODEX_HOME=/tmp/codex-minimal codex review --base <target-branch> \
  > /tmp/codex-review.txt 2>&1

# Standard path (clean codex config):
codex review --base <target-branch> > /tmp/codex-review.txt 2>&1
```

Paste relevant Codex findings as a PR comment and address them with
fix-loop commits referencing `Refs: codex-review-round-N` in the footer.

### Commit hygiene

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `perf:`, `security:`.
- Subject line ≤ 72 chars, imperative mood ("add X" not "added X").
- Body explains *why*, not *what* (the diff shows what).
- Reference the spec: `Refs: docs/specs/<slug>.md`.
- Reference the issue: `Closes PROJ-123` (adapt to your project tracker format).

### PR / issue title convention

All PR and issue titles created by agents (Claude, Codex, or any automated
tool) MUST follow the Walter-OS `[TYPE] -CATEGORY- title` convention.

**Format**: `[TYPE] -CATEGORY- title`

- **TYPE** (uppercase, in brackets): `FEAT` / `FIX` / `DOCS` / `CHORE` / `TEST`
- **CATEGORY** (uppercase, in dashes): `SECURITY` / `BUSINESS` / `COMPLIANCE` / `OPERATIONS` / `TECHNICAL` / `CUSTOMER` / `CONTENT` / `LEARNING`
- **Title body**: sentence case, imperative mood, <=60 characters, no trailing period.

Examples:
- `[FEAT] -BUSINESS- saas-metrics-dashboard skill (MRR/ARR/churn)`
- `[FIX] -SECURITY- enforce CCR_APIKEY on sub-router /v1 routes`
- `[CHORE] -OPERATIONS- bump hcloud-cli to v1.45 + audit baseline`

**Before calling `gh pr create`**, validate the title:

```bash
./hooks/pr-title-validator.sh "$TITLE"
# exit 0 = valid; exit 1 = invalid; exit 2 = missing argument
```

CI enforces this in `.github/workflows/pr-title-lint.yml` (PR) and
`.github/workflows/issue-title-lint.yml` (issues, warn-only).
See CONTRIBUTING.md -> "Title convention" for the full reference table.

### Wiki integrity (mandatory — Phase M+)

Every write to `~/sync/wiki/**` MUST validate frontmatter YAML against
`wiki/SCHEMA.md` BEFORE the write. The `wiki-validator.sh` hook enforces this.

- Pages with broken frontmatter are rejected. No silent fixes — the agent
  must repair frontmatter explicitly and re-attempt.
- Cross-links use the `[[page-slug]]` format. Wikilink validation is
  planned (Phase U) — currently only frontmatter is enforced on write.
- Type inference is allowed from path (e.g. `people/*` → type: person) but
  must be made explicit in frontmatter, not implicit.

### Trust tiers (Council agents — Phase T+)

The Walter Council uses per-agent trust tiers (`low` / `medium` / `high`) stored
in `~/.config/walter-os/trust-tiers.yml`. The tier determines which categories of
`approval-gate.sh` decisions auto-approve without operator review.

Current assignments: reviewer=high, triage=medium, researcher=medium, coder=medium,
liaison=low, janitor=low.

**Blocked for ALL tiers** (hardcoded in `approval-gate.sh`, no override possible):
push to main/staging/release, merge PRs, force-push any branch, modify hooks/
AGENTS.md/install.sh/mcp/servers.json, modify agent definitions, destructive shell
(`rm -rf`, `dd`), SQL destructive (DROP, TRUNCATE, DELETE FROM), DELETE on managed
services, money-spending, public communication, auth/crypto/PHI files, env-file
writes, production DB migrations.

### Things agents must NEVER do

- Push directly to `main` or `staging`. Always via PR.
- Commit secrets. The `.env*` files are gitignored — do not bypass.
- Run `rm -rf` on paths that aren't strictly inside the working repo.
- Modify migrations after they've been applied to staging.
- Disable a test to make CI pass. Fix the underlying issue.
- Auto-merge a PR. Operator clicks merge.
- Install MCP servers, skills, or plugins not on the trusted list (see "Supply
  chain" below).
- Generate images of real public figures (use stock or licensed).
- Read or transmit data tagged "PHI"/"medical" to any external API.
  Local LLMs only for that data (see personal context).
- Write to `~/sync/wiki/**` without passing `wiki-validator.sh` first.
- Modify `hooks/`, `AGENTS.md`, `install.sh`, or `mcp/servers.json` without
  explicit operator approval (these are in the "blocked for ALL" gate category).

### Design stack (when to use what)

Visual design and UX responsibilities are split this way:

| Task | Tool | Access |
|---|---|---|
| **Design critique** (mockup feedback, design system check) | **Claude Design** plugin | claude.ai/cowork (web only — no CLI/API) |
| **UX writing** (microcopy, error states, empty states) | Claude Design or `devrel-writer` agent | web or CLI |
| **A11y audit** (WCAG checks on Figma/Penpot mockups) | Claude Design | web only |
| **Research synthesis** (interview notes → insights) | Claude Design or `customer-interview-synthesizer` (skill, deferred) | web or CLI |
| **Image / illustration generation** | `nanobanana` skill | CLI |
| **Brand identity** (logo, palette, type) | `brand-creation` skill + nanobanana | CLI |
| **UI design files** (mockups, components, prototypes) | **Penpot** (self-host, MCP) or Figma | CLI (Penpot MCP) or desktop |
| **Technical diagrams** (architecture, flow) | Excalidraw or Tldraw | web |
| **Static design output** (posters, PDFs) | `anthropic-skills:canvas-design` plugin | CLI plugin |
| **Slide decks** | `anthropic-skills:pptx` plugin | CLI plugin |

**When to open Claude Design (web)** vs **work from the CLI**: Claude Design
lives in Cowork (claude.ai). It is the right choice when a mockup already
exists in Figma/Penpot and needs qualitative review (UX, a11y, copy). For
generation, iteration, and asset production, CLI workflows with nanobanana and
the Penpot MCP are more flexible.

### Testing strategy (layered)

Applicable test layers by project type:

| Layer | Rust / systems | Next.js + Supabase | React Native + Solana |
|---|---|---|---|
| Unit | `cargo test` | `vitest` | `vitest` + `cargo test` (programs) |
| Integration | solana-test-validator + fixtures | Supabase staging + Drizzle | local validator + RN dev mode |
| E2E web | n/a | **Playwright** (MCP) | n/a |
| E2E mobile | n/a | n/a | **Maestro** (MCP) |
| Visual regression | n/a | Chromatic / Percy / Playwright snapshots | same |
| Property-based | `proptest` | `fast-check` | both |
| Mutation | `cargo-mutants` | `stryker` | both |
| Load / perf | criterion + custom harness | k6 | n/a |
| Solana program | `anchor test` + `solana-program-test` | n/a | `anchor test` |

**Maestro vs Playwright**: they do not replace each other. Maestro is excellent
for mobile (YAML flows, realistic gestures, easy maintenance). Playwright is
better for web (granular DOM control, network interception, visual diffs).
Projects with both a React Native app and a web portal need both.

**When to write tests**: superpowers' `test-driven-development` skill enforces
RED→GREEN→REFACTOR. That is the default discipline. Non-unit layers (E2E,
visual, mutation) run separately in CI, not in pre-commit (too slow).

### MCP load profiles (default vs high-risk)

Walter-OS writes two Claude Code configs: `~/.claude/settings.json` (default)
and `~/.claude/settings.high-risk.json` (manual / opt-in).

- **default** profile — read-mostly, low-blast-radius MCPs. Loaded
  automatically in every session. Today: 23 MCPs (github, filesystem, slack, linear, plane,
  supabase, gmail, google_calendar, google_drive, telegram, notion, obsidian,
  elevenlabs, grafana, forgejo, postgres, sentry, playwright, maestro,
  sequential_thinking, memory, brave_search, penpot).

- **manual** profile — destructive / money-spending / lateral-movement-risk.
  Not loaded by default. Today: 6 MCPs (`hetzner`, `cloudflare`, `vercel`,
  `stripe`, `railway`, `bitwarden`).

**How to activate the high-risk profile** (when provisioning, spending money,
or accessing secrets):

```bash
mv ~/.claude/settings.json ~/.claude/settings.default.json
mv ~/.claude/settings.high-risk.json ~/.claude/settings.json
# (restart Claude Code)
# ... do destructive work ...
# When done:
mv ~/.claude/settings.json ~/.claude/settings.high-risk.json
mv ~/.claude/settings.default.json ~/.claude/settings.json
```

Or simply re-run `./install.sh --upgrade`, which regenerates the default. CLI:
`walter-os profile high-risk` / `walter-os profile default`.

### Money-spending MCPs / actions (extra guardrails)

Some MCPs can spend real money: Hetzner Cloud (provisioning VMs), Backblaze B2
(storage egress), Anthropic/OpenAI/Gemini (token consumption), ElevenLabs
(voice generation), domain registrars, etc.

For any MCP marked `"money": true` in [mcp/servers.json](mcp/servers.json) (currently:
`hetzner`), the agent **must**:

1. **Read before write.** Default to read-only operations (list, describe).
   Never provision, resize, destroy, or transfer without explicit confirmation
   in chat for THAT specific action.
2. **Show the bill.** Before any state-changing action, print the expected
   monthly cost delta in a human-readable form. "Provisioning CPX41: €25.20/mo"
   not "Calling create_server".
3. **One action per confirmation.** The operator confirming "spin up the VM"
   does NOT authorize "and also create 3 networks and a load balancer". Each
   resource = one confirmation.
4. **Stop on partial state.** If a multi-step provisioning sequence fails
   midway, do NOT auto-retry or auto-clean. Stop, print state, ask.
5. **Never schedule destructive ops.** No "delete this VM at 03:00 tomorrow".
   Destruction is always interactive.
6. **Tokens scoped.** `HCLOUD_TOKEN` should be read-only by default; mint a
   write-scoped token only when actively provisioning, then revoke.

The `ai-spend-tripwire` skill complements this for LLM API spend specifically.

## Supply chain — daily, mandatory

Before the first Claude Code session of the day, the `daily-audit-gate.sh` hook
runs the `daily-supply-chain-audit` skill. The skill:

- Diffs `~/.claude/settings.json`, `.mcp.json`, `~/.codex/config.toml` against
  signed baselines.
- Runs Snyk `mcp-scan` and Cisco `mcp-scanner` against installed MCP servers.
- Queries `agentaudit.dev` and `mcpskills.io` for trust scores on each package.
- Checks NVD for new CVEs in `claude-code`, `codex-cli`, and every installed MCP.
- Diffs each MCP's tool definitions against yesterday's snapshot (tool-name
  shadowing detection).
- Verifies all skills/MCPs are pinned to commit hashes, not branches.

If anything CVSS ≥ 7 is found, the gate blocks the session until triaged.
Reports land at `~/.config/walter-os/audit-YYYY-MM-DD.md`.

**Claude Code minimum version: 2.0.65** (CVE-2025-59536 + CVE-2026-21852 patches).
The audit verifies this on every run.

## Tooling preferences

- **OS**: macOS (Apple Silicon), zsh.
- **Package managers**: `pnpm` for Node, `uv` for Python, `cargo` for Rust.
- **Editors**: Cursor primary; Claude Code in terminal for agentic work; Codex CLI
  for second-opinion reviews and GPT-5.5 access.
- **Containers**: OrbStack on Mac (faster than Docker Desktop). On Linux: native
  Docker.
- **Secrets**: `.env.local` for dev (gitignored). Production secrets in
  Vaultwarden via Tailscale to local LLM node. Never hardcode, never commit.
- **Testing**: Vitest/Jest for JS, pytest for Python, `cargo test` for Rust.
  Playwright for e2e. Always.

## Multi-agent escalation pattern

For non-trivial work, decompose:

1. **Architect** subagent — produces `docs/specs/<slug>.md` and the plan.
2. **Implementer** subagent (or main session) — executes plan, task by task, with
   TDD.
3. **Reviewer** subagent — reads diff, no write tools.
4. **Security-auditor** subagent — only invoked on changes touching auth, crypto,
   medical data, or money flows.
5. **Tech-writer** subagent — generates docs/changelog from the diff.

For very long sessions, use git worktrees so subagents don't pollute each other's
context. The `using-git-worktrees` skill handles this.

## When to invoke another model

Some tasks benefit from cross-model second opinion:

- **Codex (GPT-5.5)** — invoked via `bash` from Claude Code: `codex "review the
  changes on branch X for security and edge cases"`. Best for: alternative
  reasoning paths, security review, when Claude has been in the same context too
  long and might be drift-confirming.
- **Claude (from Codex)** — same pattern, reverse direction. Use Claude for
  literary/long-form writing, complex refactors with deep context.
- **Local Ollama (standby homelab node / local LLM node, Phase L)** — for anything tagged PHI/medical/legal-
  privileged that must not leave the homelab.

## Repo language

All files committed to this repository must be in English: context templates,
specs, plans, ADRs, operational docs, commit messages, and code comments.
The operator's personal overlay files (`~/.config/walter-os/overlay/`) may be
in any language — they are private and out-of-repo.

## Output format

- Code blocks: always specify language. Always.
- File paths: absolute when referring to system, relative when in repo context.
- Long answers: tight prose, headers only when there are 3+ distinct sections.
- No emojis in code, commits, or technical docs. Casual chat is fine.
- Use the operator's preferred language for casual conversation. Keep
  code, docs, commits, and specs in English.

## Loaded skills (auto-trigger by description match)

These are always available. The agent decides when to apply based on context.

**From superpowers** (auto-loaded once the plugin is installed):
- `brainstorming`, `writing-plans`, `executing-plans` — the planning flow
- `test-driven-development` — RED-GREEN-REFACTOR
- `systematic-debugging`, `root-cause-tracing` — debugging discipline
- `verification-before-completion` — DoD-adjacent gate
- `using-git-worktrees` — parallelize work across branches
- `code-reviewer` (agent), `defensive-programming`, `condition-based-waiting`

**Walter-OS native** (this repo):
- `nanobanana` — image gen via Gemini
- `daily-supply-chain-audit` — daily security scan (also triggered by hook)
- `pr-review` — PR checklist (complements superpowers' code-reviewer)
- `definition-of-done-validator` — DoD enforcement
- `ai-spend-tripwire` — guardrail on LLM API spend
- `hackathon-spinup` — 48h project orchestration
- `brand-creation` — logo, palette, identity pipeline
- `project-induction` — guided new-project interview → charter + AGENTS.md + Plane
  epic (Phase R — available after Council v2 Phase R merge)

Context-specific skills load via the context files. See each context's
`SKILLS.md` for the full mapping table.

## Related files

- `contexts/work/AGENTS.md` — generic work context template (overlay: `~/.config/walter-os/overlay/contexts/work/AGENTS.md`)
- `contexts/projects-personal/AGENTS.md` — generic personal projects template (overlay: `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`)
- `contexts/personal/AGENTS.md` — generic personal life template (overlay: `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`)
- `contexts/hackathons/AGENTS.md` — hackathons context template (trigger: `WALTER_CONTEXT=hackathons`)
- `docs/operational/operator-contexts.md` — cascade diagram, standards table, customization guide
- `contexts/_examples/` — real-world reference examples (labeled, not loaded by default)
- `mcp/servers.json` — canonical MCP server registry
- `setup/local-llm-node.md` — homelab setup notes (superseded by `docs/specs/archive/local-llm-node.md` for Phase L)
- `docs/specs/walter-council-v2.md` — Council v2 full spec (9 improvements + Control Tower)
- `docs/specs/walter-council-v2.plan.md` — implementation plan (62 tasks, Phases F–V)
- `docs/decisions/0008-control-tower-stack.md` — ADR: Next.js 16 for Control Tower
- `docs/decisions/0009-agent-trust-tiers.md` — ADR: per-agent trust tiers
- `docs/operational/council-v2-prereqs.md` — operator prereqs per phase
- `docs/operational/council-v2-deployment-runbook.md` — merge order + post-merge verification
