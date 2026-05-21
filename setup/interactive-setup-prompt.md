# Walter-OS — Interactive setup prompt

> **How to use this file**
>
> 1. Clone the repo: `git clone https://github.com/Xipher-Labs/walter-os.git ~/walter-os`
> 2. Open Claude Code, Codex CLI, or Cursor inside the clone.
> 3. Paste the **entire block below** (between the `===` lines) into your agent.
> 4. Answer the questions one at a time. The agent writes overlay files, env vars,
>    and pre-flight checks for you.
>
> The prompt is idempotent: re-run it any time you want to change your config.
> Existing answers are preserved unless you ask the agent to override them.

---

```
================================================================================
WALTER-OS INTERACTIVE SETUP — operator-driven configuration

You are configuring Walter-OS for the operator interactively. Walter-OS is an
agent-contract framework with multiple knobs that change behavior radically.
Your job is to walk the operator through each knob, write the resulting
configuration to the personal overlay at ~/.config/walter-os/overlay/, and
verify that the changes loaded correctly.

GROUND RULES
- Ask ONE question at a time. Wait for the operator's answer. Do not assume.
- For every recommended default, explain WHY it is the default in one sentence.
- After each answer, write the file change immediately and show the diff.
- If the operator's answer conflicts with a hard limit in AGENTS.md, refuse
  and explain — do not silently downgrade safety.
- At the end, run the verification checks listed in section 9 and report.
- Default conversation language: the operator's casual language (Spanish if
  they answer in Spanish, English otherwise). Code, commits, and committed
  docs always stay in English (AGENTS.md rule).

================================================================================
SECTION 1 — OPERATOR PROFILE

Ask the operator for:
1.1  Display name (used in commits if not already set in ~/.gitconfig).
1.2  Primary email (used for CF Access policies + git commits).
1.3  Jurisdiction for regulatory-research-international skill
     (e.g. "Argentina", "EU", "US-California", "Brazil", "none").
1.4  Casual-conversation language preference (es / en / pt / other).
1.5  Time zone (e.g. "America/Argentina/Buenos_Aires").

Write to: ~/.config/walter-os/overlay/personal.env
Format:
  WALTER_OPERATOR_NAME="..."
  WALTER_OPERATOR_EMAIL="..."
  WALTER_JURISDICTION="..."
  WALTER_LANG="..."
  TZ="..."

================================================================================
SECTION 2 — CONTEXT LAYERS (which directories trigger which AGENTS.md)

Walter-OS auto-loads context files based on cwd. Ask which contexts the
operator wants enabled, and what directory pattern triggers each.

Defaults (recommended for most operators):
  work             → ~/work/*
  projects-personal → ~/Projects-Personal/* (case-insensitive)
  personal         → ~/personal/*
  hackathons       → triggered by env var WALTER_CONTEXT=hackathons

Ask:
2.1  Enable WORK context? (default: yes if you have a day job)
     If yes — what directory pattern? (default: ~/work/*)
2.2  Enable PROJECTS-PERSONAL context? (default: yes)
     If yes — what directory pattern? (default: ~/Projects-Personal/*)
2.3  Enable PERSONAL (non-dev life) context? (default: yes)
     If yes — what directory pattern? (default: ~/personal/*)
2.4  Enable HACKATHONS context? (default: yes, env-triggered)

For each enabled context, run setup/personal-overlay-init.sh to scaffold the
overlay AGENTS.md and prompt the operator to fill the stack section
(language, framework, issue tracker, deploy target).

Write to: ~/.config/walter-os/overlay/contexts/<context>/AGENTS.md

================================================================================
SECTION 3 — BRANCH FLOW MODE

Two modes (see ADR 0013 for the trade-off):

  single-tier   feature/<slug> → main directly
                Default for solo operators and small teams.

  three-stage   feature/<slug> → dev → staging → main
                For teams with a real dev integration branch + staging deploy.

Ask:
3.1  Which mode? (default: single-tier)

The branch-flow-guard hook will enforce the chosen mode. Push to main/staging
is blocked unconditionally in either mode.

Write to: ~/.config/walter-os/overlay/personal.env
  WALTER_BRANCH_FLOW="single-tier"   # or "three-stage"

================================================================================
SECTION 4 — TASK RIGOR POLICY

AGENTS.md defines three rigor levels: tiny / small / major. The agent
self-classifies today, but the operator can declare a default or floor.

Ask:
4.1  How should the agent decide rigor per task?
     a) auto-classify (default) — agent picks tiny/small/major per task.
     b) always-ask — agent must prompt "is this tiny/small/major?" before code.
     c) floor=small — never run a task at "tiny" rigor (skip-test discipline).
     d) floor=major — always full TDD + reviewer + DoD validator (heavy).
4.2  Auto-escalation to major is ALWAYS on for: auth/, crypto/, money flows,
     PHI, audit logs, prod DB migrations, hooks/ changes. Confirm operator
     accepts. (default: yes, this is a hard rule)

Write to: ~/.config/walter-os/overlay/personal.env
  WALTER_TASK_RIGOR_POLICY="auto"  # or "always-ask" | "floor-small" | "floor-major"

================================================================================
SECTION 5 — MCP PROFILE

Walter-OS ships two MCP profiles:

  default      29 read-mostly MCPs, auto-loaded every session.
               Safe for day-to-day work. No money-spending, no destructive ops.

  manual       6 high-risk MCPs (hetzner, cloudflare, vercel, stripe, railway,
               bitwarden). Money-spending or lateral-movement-risk.
               Manually swap in only for the duration of provisioning work.

Ask:
5.1  Activate the default profile now? (default: yes)
5.2  Pre-write the manual profile to ~/.claude/settings.high-risk.json for
     later swap? (default: yes)
5.3  Which MCPs in the default profile are NOT relevant for you?
     (e.g. if you don't use Slack, skip it. Show the full list.)

Write to: ~/.claude/settings.json (default), ~/.claude/settings.high-risk.json

================================================================================
SECTION 6 — COUNCIL AGENT TRUST TIERS

The Walter Council has 6 agents with per-agent trust tiers
(low / medium / high) that determine auto-approval scope.

Defaults (see ADR 0009):
  reviewer    high     — read-only audits, low blast radius.
  triage      medium   — Plane label routing, low impact if wrong.
  researcher  medium   — wiki writes, recoverable via git.
  coder       medium   — PR drafts, operator always reviews.
  liaison     low      — public communication, every action gated.
  janitor     low      — destructive cleanup, every action gated.

Ask:
6.1  Accept defaults? (recommended for first install)
6.2  If overriding any — which agent, which new tier, and why?

Write to: ~/.config/walter-os/trust-tiers.yml

================================================================================
SECTION 7 — SKILLS TO PRELOAD

Some skills are mandatory (daily-supply-chain-audit, definition-of-done-
validator, verification-before-completion). Others depend on the operator's
stack.

Ask:
7.1  Tech stack — pick all that apply:
     [ ] Rust / Cargo
     [ ] Next.js / React / Astro / SvelteKit
     [ ] React Native / Expo
     [ ] Solana programs
     [ ] Python / FastAPI / Django
     [ ] Go
     [ ] Other (describe)
7.2  Active domains — pick all that apply:
     [ ] Medical / PHI → forces medical-data-compliance skill
     [ ] Public procurement → loads regulatory-research-international
     [ ] DeFi / payment flows → loads security-auditor by default
     [ ] DevRel / content → loads content-writer + devrel-analyst
     [ ] B2B SaaS → loads pricing-experiment + saas-metrics-dashboard
7.3  Run-cadence skills — confirm enablement:
     [ ] daily-supply-chain-audit (default: yes, blocks first session if CVE)
     [ ] ai-spend-tripwire (default: yes, monthly budget alert)
     [ ] weekly-review-coach (default: ask, Friday OKR retro)

Write to: ~/.config/walter-os/overlay/skills.yml

================================================================================
SECTION 8 — WALTER-HOST (optional self-hosted stack)

Walter-OS the agent framework works without any server. Walter-Host is a
separate, optional Hetzner VM with 25+ services (Plane, Forgejo, Grafana,
Infisical, LiteLLM, n8n, Penpot, Metabase, etc.) behind Cloudflare Access.

Ask:
8.1  Do you want to deploy Walter-Host?
     a) No, only the local agent contract. (default for evaluators)
     b) Yes, on Hetzner Cloud (€25-€50/mo for CPX31-CPX41).
     c) Yes, on existing self-hosted hardware.
8.2  If yes — what domain? (e.g. mycorp.dev — needs DNS control)
8.3  If yes — confirm operator accepts "spends money" rules from AGENTS.md
     before any hcloud-cli skill is invoked.

If yes, hand off to docs/operational/walter-host-deployment.md for step-by-step.

================================================================================
SECTION 9 — VERIFICATION

After all answers are collected and files written, run:

  ./install.sh --check
  ./install.sh --dry-run
  ./hooks/branch-flow-guard.sh --self-test
  ./hooks/wiki-validator.sh --self-test
  bash -n hooks/*.sh
  cat ~/.config/walter-os/overlay/personal.env | grep -v "^#"

Report:
  - Files written + counts.
  - Hooks self-test results.
  - Any TODO blocks left in the overlay (e.g. "fill in your stack").
  - Next concrete command for the operator to run (most often:
    `./install.sh --upgrade` then restart Claude Code / Codex CLI).

================================================================================
END OF INTERACTIVE SETUP

Begin with Section 1 question 1.1. Wait for the answer. Apply. Show diff.
Move to 1.2. Continue.
```

---

## Quick reference — what each section controls

| Section | Knob | File written | Reversible? |
|---|---|---|---|
| 1 | Operator profile | `~/.config/walter-os/overlay/personal.env` | yes — edit file |
| 2 | Context layers + dir patterns | `~/.config/walter-os/overlay/contexts/<ctx>/AGENTS.md` | yes — delete overlay file |
| 3 | Branch flow mode | `~/.config/walter-os/overlay/personal.env` | yes — flip env var |
| 4 | Task rigor policy | `~/.config/walter-os/overlay/personal.env` | yes — flip env var |
| 5 | MCP profile | `~/.claude/settings.json` (+ high-risk variant) | yes — swap files |
| 6 | Council trust tiers | `~/.config/walter-os/trust-tiers.yml` | yes — edit file |
| 7 | Skills to preload | `~/.config/walter-os/overlay/skills.yml` | yes — edit file |
| 8 | Walter-Host deploy | (out-of-band — separate VM provisioning) | yes — `hcloud server delete` |

All overlay files live in `~/.config/walter-os/overlay/` — **outside the repo**.
That folder is gitignored by Walter-OS. Back it up to a separate dotfiles repo
or a password manager note if you want portability.

## Re-running setup

This prompt is idempotent. Re-paste it any time to:
- Change context patterns (e.g. moved `~/work/` to `~/clients/`).
- Promote your rigor floor (`auto` → `floor-small`).
- Add a stack you didn't have at first install.
- Swap MCP profiles.

The agent reads existing overlay files first and only asks about knobs that
have no answer yet — unless you say "review everything from scratch".
