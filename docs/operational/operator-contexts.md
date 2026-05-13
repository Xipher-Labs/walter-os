# Operator Contexts — Cascade, Standards, and Customization

This document is the canonical reference for the Walter-OS context system:
how the four contexts are loaded, what discipline standards apply in each,
and how to switch between them or add a new one.

## Overview

A Walter-OS context is a configuration layer that tells the AI agent how
to behave in a specific working mode. The context sits between the global
`AGENTS.md` (which applies everywhere) and the repo-level `AGENTS.md`
(which applies only to one project). It is the "who am I working for right
now" layer.

The system ships four contexts: `work`, `projects-personal`, `personal`,
and `hackathons`. Each has different autonomy levels, discipline rules, and
skill sets because the same agent behavior that is appropriate for a
hackathon (high speed, relaxed TDD) would be inappropriate at work (strict
process, mandatory security gates).

## How the three layers compose

```
[1] Global AGENTS.md        — applies everywhere, always
    ↓ (overridden by)
[2] Context AGENTS.md       — applies to the current working mode
    ↓ (overridden by)
[3] Repo AGENTS.md          — applies only to the current repo
```

**Most-specific-wins**: repo > context > global. If the same rule appears
in all three layers, the repo layer wins.

Each context also has an **operator overlay** at:
`~/.config/walter-os/overlay/contexts/<context>/AGENTS.md`

When the overlay exists, it loads instead of the repo's generic template.
The overlay is private (out-of-repo) and contains the operator's actual
company name, project names, and personal settings.

## Context cascade diagram

```
Which context loads?
───────────────────────────────────────────────────────
cwd matches ~/work/*              → contexts/work/AGENTS.md
cwd matches ~/Projects/* → contexts/projects-personal/AGENTS.md
cwd matches ~/personal/*          → contexts/personal/AGENTS.md
WALTER_CONTEXT=hackathons is set  → contexts/hackathons/AGENTS.md
(no match, no env var)            → global AGENTS.md only
───────────────────────────────────────────────────────

Overlay check (any context):
~/.config/walter-os/overlay/contexts/<context>/AGENTS.md exists?
  YES → load overlay instead of repo template
  NO  → load repo template
```

**Priority order**: overlay > repo template > (nothing)

The cascade is evaluated once at session start. Changing the cwd or the
env var during a session requires restarting Claude Code to re-evaluate.

## Standards table

| Context | Autonomy | TDD | PR flow | Review | Auto-PR | Comms |
|---|---|---|---|---|---|---|
| `work` | low | mandatory for all changes | `feature/*` → `dev` → `staging` → `main` | reviewer agent + Copilot; min 2 rounds | never | operator opens every PR manually |
| `projects-personal` | medium | mandatory for major; encouraged for small | `feature/*` → `dev` → `staging` → `main` | reviewer agent + Copilot; min 1 round | yes, after review convergence | auto-PR enabled; comms require confirmation |
| `personal` | low (assist) | n/a | n/a (no code workflow) | n/a | n/a | operator confirms all outbound sends |
| `hackathons` | high | opt-in (judging-critical paths only) | trunk-based; short-lived branches | reviewer optional | yes | demo-first; post-event cleanup required |

**What "autonomy" means in practice:**

- `low`: agent asks before acting on anything outside direct code tasks.
- `medium`: agent acts on common tasks without asking; confirms for money,
  public posts, and new paid services.
- `high`: agent acts with maximum speed; operator reviews at checkpoint
  intervals, not per commit.
- `low (assist)`: agent only suggests; never acts. Operator executes.

## How to switch contexts

**Path-based (work, projects-personal, personal):**

Navigate to a directory under the configured path prefix. The context loads
automatically when Claude Code starts in that directory.

```bash
cd ~/work/my-company-project    # → work context
cd ~/Projects/my-app  # → projects-personal context
cd ~/personal/notes             # → personal context
```

To reconfigure which path triggers which context, update the "Context
layers" section in the global `AGENTS.md`.

**Environment variable (hackathons):**

Set `WALTER_CONTEXT=hackathons` before starting Claude Code:

```bash
# In .env.local in the project root:
WALTER_CONTEXT=hackathons

# Or in the shell session:
export WALTER_CONTEXT=hackathons
```

Hackathon projects can live under any directory — the env var avoids
conflicts with path-based triggers.

**Per-repo override:**

To force a specific behavior in one repo regardless of the cwd context,
add a `AGENTS.md` at the repo root with the rules you need. The repo-level
file takes precedence over the context file.

## How to customize a context

The recommended customization flow:

1. Run `setup/personal-overlay-init.sh` to scaffold the overlay directory
   at `~/.config/walter-os/overlay/`.

2. Open `~/.config/walter-os/overlay/contexts/<context>/AGENTS.md` in
   your editor.

3. Fill in operator-specific values:
   - `work`: company name, stack, issue tracker, PR policy, security posture
   - `projects-personal`: active project names, stages, toolchain choices
   - `personal`: locale, jurisdiction, note-taking tools, PHI preferences
   - `hackathons`: preferred stack, sponsor API defaults, autonomy adjustments

4. Use the context's `PROMPT.md` to get LLM recommendations for your overlay:

   ```bash
   cat contexts/<context>/PROMPT.md
   # Paste into any LLM with your answers to the questions
   # Copy the output into your overlay AGENTS.md
   ```

5. Restart Claude Code to pick up the overlay.

**The overlay is loaded instead of (not merged with) the repo template.**
If you only want to change one section, copy the full template to the
overlay first, then edit the relevant section.

## Skill loading mechanics

Each context has a `SKILLS.md` file that documents the skill auto-trigger
rules for that context. See:

- `contexts/work/SKILLS.md`
- `contexts/projects-personal/SKILLS.md`
- `contexts/personal/SKILLS.md`
- `contexts/hackathons/SKILLS.md`

Skills are invoked by the agent based on trigger conditions described in
those files. `SKILLS.md` is human-readable documentation — the agent reads
it and applies the rules, but there is no programmatic parser.

Skills come from two sources:
- `superpowers` — the obra/superpowers plugin (brainstorming, TDD, etc.)
- `walter-os` — native skills in this repo (`skills/<name>/SKILL.md`)

## n8n workflow suggestions

The `n8n/workflows/` directory at the repo root contains curated workflow
suggestions for each context. See `n8n/README.md` for the import process
and contribution guide.

Each workflow `README.md` includes a "Walter-OS contexts" field showing
which context the workflow is most relevant to.

## How to add a fifth context

To create a new context (e.g., `freelance`, `teaching`, `homelab`):

1. Create `contexts/<name>/AGENTS.md` with the six-section template:
   Mode, Stack, Workflow rules, Hard limits, Skill auto-trigger, Customization.

2. Create `contexts/<name>/PROMPT.md` with numbered questions for overlay
   configuration.

3. Create `contexts/<name>/SKILLS.md` with the skill mapping table.

4. Add the context trigger to the "Context layers" section in the global
   `AGENTS.md`. Use a path prefix OR an env var, not both.

5. Update `setup/personal-overlay-init.sh` to scaffold the new context's
   overlay directory.

6. Add the new context to `tests/oss/operator-contexts.bats`.

## Related documents

- `docs/operational/multi-device-sync.md` — syncing the overlay across
  machines (the overlay lives at `~/.config/walter-os/` and is typically
  managed in a separate private git repo).
- `docs/operational/universal-vs-personal-config.md` — what belongs in
  the repo (universal) vs the overlay (personal) vs the repo AGENTS.md.
- `AGENTS.md` (global) — the global layer; context cascade is defined
  in the "Context layers" section.
- `setup/personal-overlay-init.sh` — scaffolds the overlay directory.
