# SPEC: Multi-agent autonomy

**Status:** Approved (2026-05-05). Decisions locked, implementation pending.
**Triggered by:** Operator: *"Para gestionar multiples agentes y darle la completa autonomia, que puedo hacer para que eso suceda?"*
**Related:** `agents/`, `skills/daily-supply-chain-audit/`, `setup/vm/services/{n8n,plane,openclaw,litellm}/`.

## Operator decisions (locked 2026-05-05)

| Question | Decision |
|---|---|
| Where do agents run? | **Walter-VM (default — orchestration plane) + M2 Studio (subscription pool, see §6.1) + Mac (coder agent only) + standby homelab node (Phase L, local-LLM PHI + Jarvis, see `docs/specs/archive/local-llm-node.md`) + Z440 (Phase Z, GPU inference, see `docs/specs/homelab-topology.md`)**. Agent WORKERS stay on walter-vm/Mac; standby homelab node/Z440/M2 are MODEL BACKENDS routed through LiteLLM. M2 = critical path for O1 (subscription auth, macOS-only). standby homelab node = critical path for L3 (PHI compliance + Jarvis). Z440 = perf upgrade for `coder` + `local-fast` agent traffic. |
| Plane workspace structure | **Single workspace `agents`**, with TWO label dimensions: `context:{work,projects-personal,personal,medical}` (drives auth/quota selection) and `lane:{research,code,review,janitor,digest,triage}` (drives which agent claims it). Cross-context links stay visible. |
| Quota model | **Subscription-first.** 4 personal + 3 corporate subscriptions form the quota pool. API keys are FALLBACK only when subscription quotas exhaust. See §6 for the pool architecture. |
| Approval-gate scope | **Confirmed + expanded** — see §7 for the full taxonomy and detection logic. |
| Telegram bot | **Single bot** (existing `WALTER_TELEGRAM_BOT_TOKEN`). Each agent prefixes its messages: `[researcher]`, `[coder]`, `[reviewer]`, etc. Operator's reply gets routed to the most-recent agent issue per chat thread. |
| Failure default | **Retry once after 60 s; on second failure, escalate to `needs-operator`** with the original error in the Plane comment trail. |

---

## 0. What "autonomy" means in this context

Five flavors, in increasing order of risk:

| # | Kind | Example today | Risk |
|---|---|---|---|
| 1 | **Time-driven** | Daily supply-chain audit at 08:30 | Low |
| 2 | **Event-driven** | Webhook fires → agent reacts | Low-Med |
| 3 | **Multi-agent delegation** | architect → implementer → reviewer | Med |
| 4 | **Long-horizon, unattended** | "Refactor X over the weekend" | Med-High |
| 5 | **Cross-machine, cross-account** | Mac + walter-vm + M2 + work/personal split | High |

We have #1 working (daily audit). Partial #3 (subagents exist). Nothing for #2, #4, #5 yet.

---

## 1. Existing primitives (what we build on, don't rebuild)

| Primitive | Where | What it does |
|---|---|---|
| **Subagents** | `agents/{architect,implementer,reviewer,security-auditor,devrel-writer,tech-writer}.md` | Specialized agent personas, dispatched in-session |
| **Skills** | `skills/*/SKILL.md` (51 of them) | Methodology + how-to for specific tasks |
| **Hooks** | `hooks/{branch-flow-guard,pre-commit-tests,daily-audit-gate}.sh` | Deterministic guardrails on tool use |
| **Plane** | `plane.${WALTER_DOMAIN}` | Issue tracker — natural "task queue" for agent work |
| **n8n** | `n8n.${WALTER_DOMAIN}` | Workflow engine, webhook receivers, schedulers |
| **OpenClaw** | `claw.${WALTER_DOMAIN}` | Multi-channel personal assistant; gateway over LiteLLM; Telegram bot |
| **LiteLLM** | `llm.${WALTER_DOMAIN}` | LLM gateway with **virtual keys per agent** (spend cap) |
| **Walter Bot** | Telegram | Always-available operator channel |
| **MCP catalog** | `mcp/servers.json` | Tool inventory; default + manual profiles |
| **Wiki + agent-memory** | `wiki/`, `~/sync/agent-memory/` | Compounding KB cross-device |
| **walter-vm cron** | system cron | Time-driven primitives (already runs daily audit) |
| **Mac launchd** | `~/Library/LaunchAgents/` | Same on the Mac side |
| **GitHub Actions** | `.github/workflows/ci.yml` | Test runner; could trigger agent work on PR events |
| **Codex CLI / Claude Code** | both have `--print`/`--bare` modes | Non-interactive, scriptable invocation |

**Result**: 80% of the plumbing is here. The missing 20% is the *coordination layer*.

---

## 2. The gap

Today, agent work is **operator-initiated, in-session**. The operator opens Claude Code, types a prompt, supervises until done. This breaks for:

- Tasks that span longer than a session.
- Tasks the operator wants to outsource entirely (e.g., "draft a weekly digest").
- Tasks triggered by external events (PR opened, email arrived, alert fired).
- Tasks that need multiple agents working in parallel (one ingests, one codes, one reviews).
- Tasks the operator should approve but not execute (destructive ops).

We need an **agent orchestrator** that the operator doesn't have to babysit.

---

## 3. Target architecture — "Walter Council"

A small set of always-on, single-purpose agents on walter-vm + the operator's Mac, coordinated through Plane as the durable task queue, OpenClaw + Telegram as the operator-facing voice, and Infisical as the secret/audit substrate.

```
                      EVENTS
       cron · webhook · email · PR · telegram · plane issue
                          │
                          ▼
     ┌──────────────────────────────────────────────────┐
     │            n8n (event router on walter-vm)       │
     │   triggers → classify → file as Plane issue      │
     └──────────────────────┬───────────────────────────┘
                            │
                            ▼
     ┌──────────────────────────────────────────────────┐
     │     PLANE — the durable task queue + audit log    │
     │   states: ready → claimed → in-progress →         │
     │           review → done | failed | needs-operator │
     └──────┬───────────────────────────────────┬───────┘
            │ pull ready                         │ post update
            ▼                                    │
     ┌──────────────────────────────────────────────────┐
     │             AGENT WORKERS                         │
     │                                                   │
     │   triage   researcher  coder    reviewer  janitor │
     │   (cwd-context aware; pick from issue label)      │
     │                                                   │
     │   each runs: claude --print / codex exec          │
     │   spend-capped via LiteLLM virtual key per agent  │
     └──────┬───────────────────────────────────┬───────┘
            │ writes                             │ reads
            ▼                                    │
     ┌──────────────────────────────────────────────────┐
     │  WORLD             │  OPERATOR-FACING               │
     │  ─────             │  ────────────                  │
     │  Forgejo PRs       │  Telegram digest (Walter Bot)  │
     │  walter-os wiki    │  OpenClaw → multi-channel      │
     │  walter-vm services│  Plane "needs-operator" lane   │
     │  Mac filesystem    │                                │
     └──────────────────────────────────────────────────┘
                          │
                          ▼
     ┌──────────────────────────────────────────────────┐
     │           SAFETY RAILS (existing + new)           │
     │  hooks · approval labels · spend caps · audit    │
     │  log · max-runtime · no-secrets-in-logs          │
     └──────────────────────────────────────────────────┘
```

---

## 4. Agent roster (proposed)

Six specialists, each a single-purpose worker. Each consumes Plane issues from its lane.

| Agent | Trigger / Lane | Capabilities | Where it runs |
|---|---|---|---|
| **triage** | Any new event hitting n8n | classify + file Plane issue with right lane label | walter-vm n8n |
| **researcher** | `lane:research` | wiki ingest, web search, fact-check, file output to wiki | walter-vm container, claude --print |
| **coder** | `lane:code` | Small diffs, RED-GREEN-REFACTOR (TDD), opens PR, no merge | Mac (uses local claude/codex with multi-profile) |
| **reviewer** | `lane:review` | Read-only on diff. Posts review comment + label. NEVER writes code. | walter-vm container |
| **janitor** | cron `lane:janitor` | Lints, audits, DR drill, dependency bumps, stale-PR sweep | walter-vm cron + container |
| **liaison** | cron daily 08:30 | Synthesizes overnight work into a digest. Posts to Telegram + Plane. | walter-vm container, OpenClaw integration |

**Key constraints:**

- **Single-purpose**. Each agent's prompt is narrow. No "do anything" agents. (Karpathy's "boring narrow tools" principle.)
- **Read mostly**. Most agents don't need write access to anything except their own output channel (a PR draft, a wiki page, a Plane comment).
- **Spend-capped**. Each agent has a LiteLLM virtual key with a daily budget (e.g., $5/day for researcher, $15/day for coder, $1/day for janitor).
- **Time-boxed**. Max-runtime per task: 30 min default, configurable per lane. Beyond that → mark as `needs-operator`.
- **Approval-gated for destructive ops**. coder may open a PR but NEVER merge. reviewer may approve but NEVER merge. Merge = operator only (already enforced by `branch-flow-guard.sh`).

---

## 5. Coordination model

### Plane as the durable task queue

Each piece of agent work = a Plane issue. State machine:

```
              ┌────────────────────┐
              │       ready        │ ← n8n / cron creates here
              └──────┬─────────────┘
                     │ atomic claim (assignee=<agent>)
                     ▼
              ┌────────────────────┐
              │     claimed        │
              └──────┬─────────────┘
                     │
                     ▼
              ┌────────────────────┐
              │   in-progress      │ ← agent posts comments as it works
              └──┬──────┬──────┬───┘
                 │      │      │
                 │      │      └─► failed (with reason in comment)
                 │      │
                 │      └─► needs-operator (auth/spend/approval block)
                 │
                 ▼
              ┌────────────────────┐
              │      review        │ ← if a PR was opened
              └──────┬─────────────┘
                     │
                     ▼
              ┌────────────────────┐
              │       done         │
              └────────────────────┘
```

**Atomic claim**: agent calls Plane API with `assignee_unset → assignee=<agent-id>` in a single PATCH. If the issue already had an assignee, claim fails — another agent got there first. No locks needed.

**Reentry**: every state transition writes a Plane comment with timestamp + agent ID + summary. Any agent (or operator) can pick up a half-done task by reading the comment trail.

### OpenClaw + Telegram as the operator's pager

OpenClaw runs on walter-vm, has a Telegram bot, has a model gateway via LiteLLM. Already deployed.

It plays two roles:

1. **Liaison synthesis**: every morning at 08:30, a cron runs the liaison agent which queries Plane for last-24h activity, drafts a digest in markdown, sends it via Telegram + posts to Plane.
2. **needs-operator escalation**: when any agent flips an issue to `needs-operator`, OpenClaw sends a Telegram message linking to the issue + asking for the specific input.

Operator replies (in Telegram or Plane) → state transitions back to `claimed` → agent resumes.

### Wiki as compounding memory

Every agent that ingests a source / makes a decision / learns something filed back into `wiki/` via the existing Karpathy-pattern flow. Future agent invocations benefit.

---

## 6. Subscription pool — quota substrate (M2 Studio)

> Promoted from Phase L deferred to critical path for O1. The operator
> wants subscriptions, not API keys, to fund agent work. This section
> spells out how that works without violating ToS or losing reliability.

### 6.1 The problem

Anthropic Pro / Max and ChatGPT Plus / Pro can't be called via raw HTTP API. They require the official `claude` / `codex` / web binary, which authenticates against a real account session. To use them programmatically (i.e., from agent workers), each subscription needs to live behind a **proxy that wraps the official binary** — `claude-code-router` (musistudio's, already evaluated) for Anthropic, equivalent for ChatGPT.

**Subscriptions in scope (7 total):**

| # | Account type | Service | Day-1 estimate of daily message budget |
|---|---|---|---|
| 1-2 | Personal Claude (Pro / Max) × 2 | Anthropic | ~200-1100/day each (Sonnet); much less Opus |
| 3-4 | Personal ChatGPT (Plus / Pro) × 2 | OpenAI | ~640/day each (GPT-4o), unlimited on Pro |
| 5 | example work org enterprise Claude | Anthropic | enterprise quota, large |
| 6 | example work org enterprise ChatGPT | OpenAI | enterprise quota, large |
| 7 | (TBD third corporate) | TBD | TBD |

Combined: **easily 3 000-5 000+ messages/day** in headroom — way more than 6 agent workers can plausibly burn. The challenge is plumbing, not capacity.

### 6.2 Architecture: pool of single-tenant proxies

```
┌─────────────────────────────────────────────────────────────┐
│  M2 Studio (always-on, on Headscale mesh)                   │
│                                                             │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ ccr-1   │  │ ccr-2   │  │ ccr-3   │  │ ccr-4   │         │
│  │ Anthr   │  │ Anthr   │  │ ChatGPT │  │ ChatGPT │   ...   │
│  │ pers#1  │  │ pers#2  │  │ pers#1  │  │ pers#2  │         │
│  │ :3461   │  │ :3462   │  │ :3471   │  │ :3472   │         │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                      │
│  │ ccr-5   │  │ ccr-6   │  │ ccr-7   │                      │
│  │ example work org  │  │ example work org  │  │ TBD     │                      │
│  │ Anthr   │  │ ChatGPT │  │ corp #3 │                      │
│  │ :3463   │  │ :3473   │  │ :34??   │                      │
│  └─────────┘  └─────────┘  └─────────┘                      │
│                                                             │
│  Each container: isolated browser profile / session token   │
│  Each: own LaunchAgent + auto-restart                       │
└──────────────┬──────────────────────────────────────────────┘
               │ Tailscale mesh
               ▼
┌─────────────────────────────────────────────────────────────┐
│   Walter-VM LiteLLM                                         │
│                                                             │
│   model_list:                                               │
│     - sonnet-pool:                                          │
│         routing: round-robin                                │
│         backends: [ccr-1, ccr-2, ccr-3 (corp anthr fallback)]│
│     - gpt-pool:                                             │
│         routing: round-robin                                │
│         backends: [ccr-4, ccr-5, ccr-6 (corp chatgpt)]      │
│     - sonnet-api (FALLBACK):                                │
│         backend: anthropic API key (rate-limit hit only)    │
│                                                             │
│   Per-agent virtual keys map to context-aware pool slices:  │
│     coder-work    → corp pools only (compliance)            │
│     coder-personal→ personal pools                          │
│     etc.                                                    │
└─────────────────────────────────────────────────────────────┘
```

### 6.3 Quota tracking (the actual hard part)

Anthropic and OpenAI **don't expose a quota API** for subscription tiers. We can't ask "how much is left on Pro #1 today?". Workarounds:

**Approach A — passive detection (recommended)**: when a CCR endpoint returns 429 or specific "rate limit" messages, mark that backend as `quota-exhausted` for a TTL (typically until the next quota window resets — Pro is rolling 5h, Plus is 3h). LiteLLM router skips exhausted backends. Use natural rotation across the 7.

**Approach B — bookkeeping**: keep a per-backend counter at LiteLLM level, decrement on each call, refill on a schedule that matches Anthropic's 5h windows. Brittle (their counters aren't public), but better insight.

**Recommendation**: start with A. Add B later if A causes too many cliff-edge failures.

### 6.4 ToS posture

Anthropic Pro ToS prohibits "programmatic use" but operator-personal proxying for personal use is widely-deployed practice (see musistudio/claude-code-router popularity). The operator's stance, already documented in `setup/vm/services/llm-proxies/compose.yml`:

> *"Operator decision: this is for personal use only, not third-party served, so subscription ToS interpretation is operator's call."*

Same applies here. **Hard rule**: agent traffic stays inside the operator's mesh. No public webhooks pointing at the pool. No third-party customers riding on it.

For corporate accounts (example work org enterprise): use the corporate API key, NOT corporate Pro proxying — enterprise contracts are explicit about programmatic use being allowed via API key only.

### 6.5 Bootstrap sequence (per subscription)

Operator-driven, one-time per subscription:

1. On M2 Studio: spin a container `ccr-N` with a clean Chrome/Chromium profile.
2. Open claude.ai (or chat.openai.com) inside that profile, log in to subscription #N.
3. Install `@musistudio/claude-code-router` inside the container (or its OpenAI equivalent).
4. CCR auto-extracts cookies → exposes `:34NN` OpenAI-compatible endpoint.
5. Add the endpoint to LiteLLM's pool config + restart LiteLLM.
6. Test: `curl litellm/v1/chat/completions -d '{model: sonnet-pool, ...}'` → response from one of the 3 sonnet backends.
7. Per-month: log in again to refresh tokens (most providers expire sessions in 30-90 days). Cron reminder.

Cost: M2 Studio idle. Operator's monthly subscription billing unchanged. Zero per-token cost beyond what's already paid.

### 6.6 Fallback to API keys

When ALL pool backends for a model class are quota-exhausted (e.g., all 3 sonnet sources hit limit at the same time — improbable but possible during a heavy batch), LiteLLM falls back to the corresponding API key (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` from Infisical). Fallback is logged loudly so operator knows real $$ was spent.

Operator-defined cap on fallback spend per day: **default $5/day total**, hard stop. Hit it → all subscription-pool-exhausted requests block until midnight reset.

---

## 7. Approval-gate — full taxonomy

> Operator decision #4 expanded. The approval-gate hook intercepts agent
> tool calls and blocks anything in this taxonomy unless the parent
> Plane issue has the `approved-by-operator` label.

### 7.1 What's blocked (with detection logic)

| Category | Detection | Why |
|---|---|---|
| **Push to main / staging / release branches** | `git push` to ref matching `^(refs/heads/)?(main\|master\|staging\|release.*)$` | Already enforced by `branch-flow-guard.sh`. Doubled-up here as defense-in-depth. |
| **PR merge** | `gh pr merge` | Operator-only. Always. No exceptions. |
| **Force-push** | `git push --force` or `--force-with-lease` to ANY branch | One typo lost work. Always operator. |
| **Modify hooks** | Edit / Write to `hooks/*.sh`, `~/.claude/settings.json` (hooks block), `.github/workflows/*` | Self-modifying agents = nightmare debugging + escape hatch. Operator-only. |
| **Modify install.sh / AGENTS.md / CLAUDE.md / mcp/servers.json** | Edit / Write to those exact paths | Walter-OS contract. Agents can read but never edit. |
| **Modify agents/* or skills/* (own definitions)** | Edit / Write to `agents/*.md` or `skills/*/SKILL.md` | Agents shouldn't rewrite their own scripture mid-session. |
| **Destructive shell** | Bash command matching `\b(rm -rf|dd if=|mkfs|:(){:|:&};:|truncate|format)\b`, OR Bash command matching `^\s*sudo\s+(rm|chmod|chown)\s+(/|-R)` | Catches the obvious foot-guns. False positives possible; that's why label exists. |
| **DROP / TRUNCATE / DELETE in SQL** | psql / supabase MCP query containing `\b(drop\s+(table|database|schema)|truncate|delete\s+from)\b` (case-insensitive) | Schema-level destruction. |
| **HTTP DELETE on managed services** | curl / API calls with method DELETE to: `cloudflare api`, `hcloud api`, `vercel api`, `stripe api`, `forgejo api/v1/repos/.*?op=delete`, B2 bucket delete | All of these can vaporize state. |
| **Money-spending ops** | Hetzner provision / resize / destroy; Stripe charge / refund; OpenAI usage > $X cumulative this session; Anthropic API > $X; B2 egress > YGB; domain registrar API | Spend caps + always-confirm rule (already in AGENTS.md money-spending guardrails). |
| **Public communication** | Tool calls to: tweet, blog publish, Slack post outside DMs/operator-channel, email send (drafts always ok), reddit/forum post, GitHub issue/comment on repo without `agent-allowed-to-comment` topic | Reputation = irreversible. |
| **Reply on operator's behalf** | Email reply, DM reply, calendar accept/decline. Drafts ok; sending = approval. | Trust delegation explicit. |
| **Auth / crypto / PHI files** | Any Edit / Write to globs: `auth/**`, `crypto/**`, `example medical app/**`, `personal/health/**`, `*.key`, `*.pem`, `*.crt`, `~/.ssh/*` | Compliance. Auto-escalates to **major rigor** + security-auditor subagent. |
| **`.env*` writes** | Edit / Write to any `*.env*` file | Secrets surface. |
| **Production DB migrations** | Any `supabase db push` or migration apply against env != local/staging | Operator confirms env. |
| **Modify Plane / Forgejo / Infisical config** | API calls that change project visibility, member access, secret access policies | Don't lock yourself out. |

### 7.2 What's NOT blocked (fast path for agent work)

- Reading any file (Read tool) — agents need full context.
- Running tests, linters, formatters (Bash with `pytest`, `cargo test`, `npm test`, `eslint`, `prettier`, `cargo fmt`, etc.).
- Writing tests (Edit / Write to `tests/**`, `**/*.test.*`, `**/*.spec.*`).
- Writing source code in feature/* branches (the normal coder workflow).
- Opening PRs (`gh pr create`), commenting on PRs (`gh pr comment`), adding labels.
- Reading from databases (SELECT queries), Plane API GETs, Infisical secret READS via the operator's session.
- Local file operations within the worktree.
- Calling the model (LiteLLM) — that's agent work itself.

### 7.3 Implementation

```bash
# hooks/approval-gate.sh — new in PR for Phase O1
#
# Reads stdin: Claude Code hook event JSON.
# Inspects the proposed tool call.
# If matches any §7.1 pattern: emit decision=block + reason.
# Else: decision=allow.
#
# Approval label check uses Plane API: agent invocations carry
# WALTER_AGENT_PLANE_ISSUE env. Hook fetches that issue's labels
# via Infisical-stored Plane token. If `approved-by-operator`
# label present, allow. Else block.
```

The hook is registered as `PreToolUse` on Bash, Edit, Write, and any MCP write-style tools.

### 7.4 Approval flow from operator's POV

1. Agent encounters a blocked operation.
2. Hook returns `decision=block` with `reason` describing the operation.
3. Agent worker catches that, files Plane comment: "Blocked by approval-gate: <op>. Add label `approved-by-operator` if you want me to proceed."
4. Agent worker flips issue to `needs-operator`, sends Telegram message.
5. Operator reviews (in Plane web or via reply to Telegram).
6. Operator adds the label OR rejects with a comment.
7. n8n webhook on label-added re-triggers the agent worker for that issue.
8. Agent re-attempts the operation — hook now sees the label, allows.
9. Audit trail: Plane comment + agent log show the approval decision and timestamp.

### 7.5 Pre-approval ("standing approvals")

For repetitive low-risk ops, operator can grant a **standing approval** scoped to a label class:

- `auto-approved:lint-fixes` — coder agent can push to feature/* and open PRs without asking, AS LONG AS the diff matches lint-fixer pattern (only `*.{ts,tsx,py,rs}` files, only style changes per linter rules).
- `auto-approved:dep-bumps` — janitor can open PRs that bump deps, but only patch + minor versions.
- `auto-approved:wiki-content` — researcher can commit to private wiki repo without per-commit approval.

Standing approvals live in `~/.config/walter-os/agent-approvals.yml`, audited weekly by janitor itself ("you have N standing approvals, are these still ok?").

### 7.6 All safety rails — full matrix

The approval-gate is one of nine. Together they form the runaway-autonomy
defense-in-depth:

| Rail | What it does |
|---|---|
| **Per-agent LiteLLM virtual key** | Spend cap. Hit cap → 429 from gateway → agent pauses, files `needs-operator` issue. With subscription-first quota model (§6), the cap is mostly about API-key fallback budget. |
| **`branch-flow-guard.sh` hook** | Already enforced: feature/* → dev → staging → main. Agents can't push to main. |
| **`pre-commit-tests.sh` hook** | Already enforced: lint+typecheck+tests must pass before commit. |
| **`daily-audit-gate.sh` hook** | Already enforced: first session of the day blocked until supply-chain scan green. |
| **`approval-gate.sh` hook (NEW)** | For destructive ops. Issue must have `approved-by-operator` label OR agent blocks + escalates. |
| **Max-runtime watchdog** | Wraps every agent invocation. Kill at N min. Default 30. |
| **Audit log** | Every agent action writes to `~/sync/agent-memory/audit/<date>.log` AND to the Plane issue's comment trail. Operator can grep + diff. |
| **No-secrets-in-logs filter** | All agent stdout/stderr passes through a redactor that masks anything matching secret-looking patterns (sk-…, eyJ…, etc.). |
| **Approval for irreversibles** | Agents may NEVER: merge to main, delete production data, run destructive SQL, send public messages, transfer money, modify auth/crypto code, modify hooks themselves. These need `approved-by-operator`. |
| **Operator panic button** | `walter-os agents pause` halts all agent workers. `walter-os agents resume` lifts. State persists in Plane so partial work isn't lost. |

---

## 8. Multi-account auth (work vs personal)

Each agent worker has a **profile assignment**:

- `triage`, `liaison`, `janitor` → personal context (no enterprise quota needed)
- `coder`, `reviewer` working on issues labeled `context:work` → enterprise (`ANTHROPIC_ENTERPRISE_KEY` from Infisical)
- `coder`, `reviewer` on `context:projects-personal` or `context:personal` → personal Pro

The agent worker picks its model auth based on the issue's `context:*` label. Wrong context = blocks + escalates (compliance).

---

## 9. Phased rollout (Phase O1 → O5)

Each phase = a usable increment. Operator can stop at any phase if the value is enough.

### Phase O1 — Foundation (~1 week)

- Define `walter-os agents` CLI subcommand: list, run-once, pause, resume, status.
- Implement `agent-worker` runner: takes (agent-name, plane-issue-id) → executes via `claude --print` or `codex exec` → posts results.
- LiteLLM virtual keys per agent (1 per agent, daily budget configured).
- Approval-gate hook (new, in `hooks/approval-gate.sh`).
- Max-runtime watchdog wrapper.
- Single Plane lane: `agent-tasks`, with custom states.
- Acceptance: operator manually creates a Plane issue → `walter-os agents run-once researcher --issue <ID>` → agent works the issue, posts result.

### Phase O2 — Specialists (~3-5 days)

- Implement `triage`, `researcher`, `coder`, `reviewer` (4 of 6).
- Each = its own SKILL.md describing the contract + a wrapper script.
- Use existing `agents/` subagents as the per-task personas.
- Agents pick up issues by label match.
- Acceptance: operator pastes a URL into Plane (`lane:research`) → researcher picks it up → ingests to wiki → state=done in <10 min.

### Phase O3 — Triggers (~3-5 days)

- n8n workflows: cron (daily/hourly), webhook receivers (GitHub, email, Telegram), Plane webhook.
- Each trigger creates a Plane issue with the right lane.
- janitor cron at 03:00 (after restic): wiki lint, dep bumps, audit ack-expiry sweep.
- Acceptance: GitHub PR opened → n8n receives webhook → reviewer Plane issue created → reviewer agent posts review comment within 10 min.

### Phase O4 — Operator UX (~3 days)

- Implement `liaison` agent with daily 08:30 digest.
- Telegram interactive: operator replies to a digest message → reply gets parsed and routed to the right Plane issue.
- `walter-os agents status` dashboard.
- Acceptance: operator wakes up, reads Telegram digest, replies "approve" to one issue → agent unblocks within 1 min.

### Phase O5 — Cross-machine + multi-account (~1 week)

- Mac-side coder agent runs in a `claude --print` loop with a worktree per issue.
- M2 Studio (when it lands) hosts heavier work + Ollama for PHI tasks.
- Per-issue `context:*` label drives auth selection.
- Acceptance: a `context:work` issue routes to enterprise quota; `context:medical` issue routes to local Ollama; cross-context workspace barriers respected.

---

## 10. What this is NOT

To keep scope honest:

- ❌ **Not a general-purpose agentic framework.** No LangGraph, no AutoGen replacement. Six specific agents for one operator's stack.
- ❌ **Not a replacement for in-session work.** When the operator IS at the keyboard, normal Claude Code / Codex flow continues. Autonomy fills the gaps.
- ❌ **Not full-stack autonomy.** Operator merges PRs, approves destructive ops, picks the long-term direction. Agents do the boring part.
- ❌ **Not internet-facing.** All agent endpoints stay behind CF Access. No public webhooks except CF-protected ones.

---

## 11. Implementation prerequisites

> Decisions are **locked** (see §0 at top). What remains is operator
> work to enable each prerequisite before the corresponding phase runs.

### Before O1 — Foundation can start

| # | Prerequisite | Operator action | Time |
|---|---|---|---|
| 1 | M2 Studio on Headscale mesh | `tailscale up` on M2; node visible from walter-vm. | 15 min |
| 2 | Plane workspace `agents` | Create the workspace; create custom labels (context:* and lane:*). | 15 min |
| 3 | Telegram bot already deployed | Confirm `WALTER_TELEGRAM_BOT_TOKEN` works (you already have this). | 0 min |
| 4 | Approval-gate hook design + tests | Agent writes hook + bats test suite as part of O1 PR. | (agent task) |
| 5 | Per-agent LiteLLM virtual keys | Agent generates 6 virtual keys via LiteLLM API at O1 PR time. | (agent task) |

### Before O3 — Triggers (n8n) can start

| # | Prerequisite | Operator action | Time |
|---|---|---|---|
| 1 | n8n owner + first credentials | First-run setup (already in onboarding-checklist § Step 8). | 5 min |
| 2 | GitHub webhook tokens | Operator creates webhook secrets per repo, stores in Infisical. | 10 min/repo |
| 3 | Plane webhook secret | Plane → Settings → Webhooks → create with shared secret in Infisical. | 5 min |

### Before O5 — Subscription pool can start

| # | Prerequisite | Operator action | Time |
|---|---|---|---|
| 1 | M2 Studio with Docker available | Operator OS-level prep. | 30 min |
| 2 | Per-subscription browser sessions | Login to claude.ai / chat.openai.com from N isolated Chrome profiles on M2. | 5 min × 7 |
| 3 | Token-refresh reminder | Cron / calendar reminder to re-login monthly per subscription. | 5 min once |
| 4 | Corporate API keys for fallback | example work org enterprise API keys in Infisical for the FALLBACK case (subscription pool exhausted). | 10 min |
| 5 | ToS acknowledgement | Operator confirms in writing (Plane decision page) the subscription-proxy stance — defensive documentation. | 15 min |

---

## 12. Acceptance criteria (for "autonomy is real")

After all 5 phases:

- [ ] Operator goes on vacation for 3 days. Returns to: zero data loss, all overnight backups verified, daily digests waiting in Telegram, ~5-10 PRs from coder agent waiting for review, wiki has 2-5 new pages, no destructive actions taken without approval.
- [ ] Operator pastes a URL into Plane → researcher ingests in <10 min, no operator interaction required.
- [ ] A GitHub PR opened on personal repo → reviewer posts review within 10 min, classifies as `lgtm`/`needs-changes`.
- [ ] LiteLLM dashboard shows per-agent spend tracking against caps. No agent has exceeded its cap unattended.
- [ ] Audit log at `~/sync/agent-memory/audit/<date>.log` is human-readable and traces every agent action.
- [ ] `walter-os agents pause` stops all workers within 30s. `resume` brings them back to where they were.

---

## 13. Reference

- [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — the wiki layer this leans on.
- Anthropic Agent SDK (referenced in CLAUDE.md) — for building the agent-worker primitives.
- `agents/*.md` — the per-task subagent personas to wrap.
- `docs/specs/secrets-runtime-architecture.md` — auth substrate.
- `docs/specs/karpathy-llm-wiki-compliance.md` — memory substrate.
