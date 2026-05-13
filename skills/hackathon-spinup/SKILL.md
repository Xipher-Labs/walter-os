---
name: hackathon-spinup
description: Orchestrate the full spinup of a hackathon (or any new ~/Projects-Personal/Hackatons/<name>) project from rough one-liner to deployed MVP. Triggered automatically when a new directory is created under ~/Projects-Personal/Hackatons/ OR when the user says "new hackathon project", "spin up <name>", "Colosseum submission", "MVP in 48h". Sequence: deep discovery via GPT-5.5 thinking iterations → SDD-style spec → Plane workspace + Obsidian KB scaffolding → brand identity → landing → MVP code → demo. Cuts features, never cuts tests on the critical path.
---

# Hackathon Spinup

Meta-skill that takes a one-liner ("I want to build X for hackathon Y")
through structured discovery and out the other side as a deployed,
demoable MVP. Phase -1 (Discovery) is the new addition — uses thinking
models for deep questioning before any code is written.

## Phase -1: Discovery (45–90 min, BEFORE anything else)

The bulk of hackathons fail at "we built the wrong thing", not at "we
shipped slowly". Phase -1 prevents that.

### Step 1: Operator one-liner

Operator provides one rough sentence:

> "I want to build a tool that helps SMBs auto-categorize
> their invoices using LLMs."

### Step 2: Thinking model — first interrogation pass (15 min)

Agent invokes the strongest available thinking model via OpenCode (or
Claude CLI / Codex CLI) with this prompt:

```
You are a senior product strategist + technical co-founder.

The operator has proposed: "<one-liner>"

Phase 1 of 2: ask 8–12 sharp questions that surface critical
unknowns. Focus on:
  - target user (specific role, not demographic)
  - exact pain point (what they do today that's broken)
  - existing alternatives (what they currently use)
  - distribution channel (how they'll find the product)
  - monetization model (price, frequency)
  - regulatory / compliance constraints (especially for Argentine
    fintech / health / public-sector domains)
  - technical risks (most likely failure modes)
  - 90-second demo: what does the judge see?

Output as numbered questions. Wait for answers before moving to Phase 2.
```

Operator answers in plaintext. Agent saves both questions and answers
to `docs/hackathon/<project>/discovery-pass-1.md`.

### Step 3: Thinking model — second interrogation pass (15 min)

Agent invokes the model again with pass-1 results, asks the followups:

```
Pass 2: Given the answers above, ask the FOLLOWUP questions that
expose the riskiest assumptions. Specifically:
  - 3 things that COULD make this not-work
  - the smallest thing the operator could build first that would
    falsify the riskiest assumption
  - what would success look like at hour 48 (concrete, observable)
  - what's the ONE feature that, if cut, the project still ships
    and demos credibly
```

Operator answers. Saved to `docs/hackathon/<project>/discovery-pass-2.md`.

### Step 4: Strongest pro model — generate the functional document (15 min)

Agent invokes the strongest available pro model (e.g. GPT-5.5 pro,
Claude Opus 4.7) with both discovery passes as context:

```
Synthesize pass-1 + pass-2 into a single, opinionated functional
document. Format:

# <project> — Functional Specification

## 1. Business idea (200 words max)
   - Problem
   - User
   - Solution one-liner
   - Why now

## 2. Definition of Done (SDD-style)
   - Outcome 1: <user can do X and observe Y>
   - Outcome 2: ...
   Each with: testable criterion, evidence (screenshot / log line),
   responsible component.

## 3. Stack (be specific, justify each)
   - Frontend: <framework + version>
   - Backend: <approach>
   - Database: <Postgres / Supabase / etc.>
   - Auth: <concrete mechanism>
   - Infra: <Vercel / Walter-VM / Railway>
   - Why each over alternatives: 1 line per choice

## 4. Architecture (ASCII diagram, single page)

## 5. Test strategy
   - Unit: <what to test>
   - Integration: <key flows>
   - E2E: <happy path>
   - DoD validator: <how each "Outcome" is verified>

## 6. Plan (8–15 tasks, each ≤30min)
   T1: <task with file path + acceptance check>
   T2: ...

## 7. Demo script (90 seconds)

## 8. Risks + mitigations
```

Saved as `docs/specs/<project>.md` — canonical spec for the build.

### Step 5: Bootstrap project workspace

Once the operator says "go", the skill provisions in parallel:

1. **Plane workspace + project**:
   - Workspace: `hackaton` (existing)
   - Project: `<project-name>`
   - Initial issues: one per task from section 6 of the spec
   - Connected to GitHub repo via PAT integration (see Plane skill).

2. **Obsidian KB folder**:
   - `~/Obsidian/vault/projects/<project-name>/`
   - Linked notes: discovery passes, spec, daily progress, decisions log
   - Auto-synced to Forgejo via Obsidian Git plugin.

3. **GitHub repo** (private):
   - `<your-org>/<project-name>`
   - Initial commit: `docs/specs/<project>.md` + scaffolded README + MIT LICENSE
   - GitHub Actions starter (lint + test + build).

4. **Devcontainer**:
   - Pulled from `walter-os/templates/devcontainer-templates/<stack>/`
   - Dockerfile + devcontainer.json + post-create.sh
   - Isolates this project's tooling — no version conflicts.

5. **Infisical**:
   - Workspace: `hackaton`, environment: `<project-name>`
   - Initial secrets: empty, populated as features need them.

6. **Vercel project** (if web):
   - Project: `<project-name>`, connected to GitHub
   - Preview deploys on `feature/*`.

7. **n8n workflow** (when Phase K4 lands):
   - Trigger: Plane issue → "in_progress"
   - Action: spawn Claude Code container with spec + task, execute,
     open PR.

All idempotent — re-running the skill verifies + creates what's missing.

### Step 6: Continue to Phase 0+

Skill resumes the original 0-7 sequence using the generated spec as input.

### When to skip Phase -1

- Operator already has a written spec → skip to Phase 0.
- Known stack + previously-validated idea → run pass 1 only.
- Fork of existing project → skip to Phase 3 directly.

## Phase 0: Idea lock (30 min)

Before anything else:

1. **One-sentence pitch** — write it. If you can't fit the project in one
   sentence, the project is too big for 48h.
2. **Demo script** — 90 seconds, written first. What does the judge see?
   What's the wow moment? Working backwards from the demo prevents you
   from building features that don't show up in it.
3. **Cut list** — write down 5 things you will NOT build. Permission
   slip to ignore them when temptation hits.

Output: `docs/hackathon/pitch.md`, `docs/hackathon/demo-script.md`.

## Phase 1: Identity (1–2 hours)

Project needs a name, logo, and palette before anything else. Branded
projects get more attention than nameless ones in the gallery. This phase
runs in parallel with Phase 2.

Invoke the `brand-creation` skill:

1. Generate 3 name candidates (pick one).
2. Generate 6 logo variations via `nanobanana` with consistent style ref.
3. Pick one, iterate 2–3 turns to refine.
4. Extract palette (3–5 colors) and pair with 1–2 fonts (system or Google
   Fonts only — no custom fonts in 48h).
5. Save: `assets/brand/<project>/logo.svg`, `palette.json`, `fonts.txt`.

## Phase 2: Architecture (1 hour, parallel with Phase 1)

Decide the stack in 60 minutes. Prefer boring and known over shiny.

Default starter for a Solana-flavored hackathon project:
- **Frontend**: Next.js 15 App Router + Tailwind + shadcn/ui
- **Backend**: Supabase (auth + DB + storage + realtime). No custom backend.
- **Wallet**: `@solana/wallet-adapter` + Phantom + Backpack.
- **Program** (if smart contract needed): Anchor framework, single program.
- **Deploy**: Vercel for frontend, devnet for program.
- **Analytics**: Plausible (self-hosted) or none.

Output: `docs/hackathon/architecture.md` — single page, max 200 words. ASCII
diagram if it helps.

## Phase 3: Scaffolding (2 hours)

```bash
pnpm create next-app@latest <project> --typescript --tailwind --app --import-alias "@/*"
cd <project>
pnpm add @solana/wallet-adapter-react @solana/wallet-adapter-wallets \
  @solana/wallet-adapter-react-ui @solana/web3.js
pnpm add -D @types/node
# anchor init programs/<name>  (if smart contract needed)
```

Set up:
- Supabase project (staging env from day one)
- Vercel deploy connected to `main` branch
- Domain (use a .xyz or .app for $1, or use Vercel subdomain)
- Basic landing page with logo, pitch, "connect wallet" button

Output: deployable scaffold. URL works. Wallet connects. Database empty.

## Phase 4: Spec the MVP (1 hour)

One spec, three acceptance criteria max. If you have more, you're
over-scoping.

Example:
- AC-1: Wallet-connected user can submit X.
- AC-2: Submission persists to DB and shows in feed.
- AC-3: Action records on-chain (devnet) with tx signature linked from feed.

Output: `docs/specs/mvp.md` + plan file.

## Phase 5: Build (24–30 hours)

This is the bulk. Discipline holds:

- TDD on the critical path only. UI polish doesn't need tests in a hackathon.
- Commit every 30 minutes minimum. Hackathons eat sleep; you'll forget
  what you did 4 hours ago. Commits are your memory.
- Don't refactor mid-build. Ugly working code beats elegant broken code at
  the deadline.
- Time-box every sub-task. If a 2-hour task hits 3 hours, stop. Skip it
  or ask for help. Tasks that overrun usually overrun by 4x, not 1.5x.

## Phase 6: Polish (4 hours)

Last 4 hours before deadline:

1. **Demo dry run** — record yourself doing the demo. Watch it. Fix the
   embarrassing parts.
2. **Edge cases on the happy path** — empty states, loading states, error
   states for the 3 paths the demo touches. Ignore everything else.
3. **README** — pitch + architecture diagram + install steps + demo video
   link. Judges read READMEs.
4. **Submission package** — 90s video, slide deck (3 slides max), GitHub
   link, deployed URL.

## Phase 7: Submit + sleep

Submit 30 minutes before deadline, not at the wire. You'll find a typo,
trust me.

## Failure modes to watch

- **Scope creep at hour 12** — "we should also add..." No.
- **New dependency at hour 36** — never. Use what you already imported.
- **"Let me just refactor this real quick" at any point** — never.
- **Sleep deprivation past hour 30** — degrades judgment. Better to ship
  with one less feature than to commit a security bug at 4am.

## Hackathon-specific commands

`/spec mvp` — generates the MVP spec from a one-liner.
`/scaffold <stack>` — runs Phase 3 commands and verifies deploy works.
`/demo-script` — produces a 90s demo script from the spec.

## What this skill does NOT do for you

- Pick a winning idea. That's on you.
- Network with judges and other teams. Half the value of a hackathon.
- Sleep. Please sleep.
