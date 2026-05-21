# Walter-OS — Tier I install via agent

> **For**: operators who want the agent contract (`AGENTS.md` cascade) +
> branch-flow + PR-title hooks across Claude Code, Codex CLI, and Cursor.
> Nothing else.
>
> **Time**: ~5 minutes.
>
> **Prereqs**:
> - macOS or Linux with `bash`, `git`, `curl`.
> - One of: Claude Code, Codex CLI, or a Cursor install (the agent that
>   will execute this prompt).
>
> **How to use**: open the agent in any working directory and paste the
> entire block between the `===` lines below. The agent walks you through
> the install and asks the minimum questions.

---

```
================================================================================
WALTER-OS TIER I INSTALL — agent contract only

You are installing Walter-OS Tier I on the operator's local machine.
Tier I gives them:
  - The AGENTS.md three-level cascade (global → context → repo).
  - The personal overlay scaffold at ~/.config/walter-os/overlay/.
  - hooks/branch-flow-guard.sh + hooks/pr-title-validator.sh.
  - The `walter-os` CLI on $PATH.

Tier I does NOT install: skills catalog, MCP configs, slash commands,
plugins, self-hosted services, or Council agents. Those come in Tiers II–IV.

GROUND RULES
- Ask ONE question at a time. Wait for the operator's answer.
- For every default, explain WHY it is the default in one sentence.
- After each install step, run a verify command and report PASS/FAIL.
- If a step fails, STOP and surface the error. Do not silently retry.
- Conversation language: match the operator's language (Spanish/English/etc.).
- Code, paths, and commit messages stay in English.
- The install is idempotent: if Walter-OS is already installed, the
  agent SKIPS the clone step and runs `install.sh --upgrade` to refresh.

================================================================================
STEP 1 — CLONE OR DETECT EXISTING

Check if Walter-OS is already cloned:
  test -d /opt/walter-os || test -d "$HOME/walter-os" || test -d "$HOME/Projects-Personal/walter-os"

If found, use that path. If not, ask the operator:
  "Where should I clone Walter-OS? (default: /opt/walter-os)"

Then:
  git clone https://github.com/Xipher-Labs/walter-os.git <path>
  cd <path>

Verify:
  test -f AGENTS.md && test -f install.sh && echo OK

================================================================================
STEP 2 — DEPENDENCY CHECK

Run:
  ./install.sh --check

This validates: bash ≥4, git, curl, optional `gh` (for PR ops). If any
required tool is missing, surface the apt/brew/winget command to install
it and STOP. Do not proceed to install with broken deps.

================================================================================
STEP 3 — PERSONAL OVERLAY SCAFFOLD

Ask the operator for the following, ONE AT A TIME:

  3.1  Display name (used in commits if not set in ~/.gitconfig already)
       → WALTER_OPERATOR_NAME

  3.2  Primary email (used for git commits + future CF Access policies if
       you ever deploy Tier III)
       → WALTER_OPERATOR_EMAIL

  3.3  Casual conversation language (default: en)
       Options: es / en / pt / fr / other
       → WALTER_LANG

  3.4  Time zone (default: Europe/Madrid; common: America/Argentina/Buenos_Aires,
       Europe/Berlin, America/New_York, Asia/Tokyo)
       → TZ

  3.5  Branch flow mode (default: single-tier — recommended for solo / small team)
       Options:
         single-tier   feature/<slug> → main directly
         three-stage   feature/<slug> → dev → staging → main
       → WALTER_BRANCH_FLOW

  3.6  Jurisdiction for regulatory-research (default: none)
       Examples: Argentina, EU, US-California, Brazil. Skip with "none" if
       you don't work in regulated domains.
       → WALTER_JURISDICTION

After all 6 questions, run:
  ./setup/personal-overlay-init.sh

This scaffolds ~/.config/walter-os/overlay/{personal.env,contexts/}.

Then write the operator's answers to ~/.config/walter-os/overlay/personal.env.
Use a temp file + atomic mv to avoid partial writes.

Show the resulting file to the operator and ask: "Looks right? (yes/no)"

================================================================================
STEP 4 — INSTALL HOOKS + CLI

Run:
  ./install.sh --dry-run    # preview what install.sh would change
  ./install.sh --upgrade    # apply

This:
  - Symlinks AGENTS.md and contexts/ into ~/.claude/ and ~/.codex/.
  - Installs hooks/branch-flow-guard.sh + hooks/pr-title-validator.sh
    into ~/.config/walter-os/hooks/.
  - Installs the `walter-os` CLI into ~/.local/bin/.
  - Wires the hooks into ~/.claude/settings.json (if Claude Code is
    installed) and ~/.codex/config.toml (if Codex CLI is installed).

Verify:
  ./hooks/branch-flow-guard.sh --self-test   # expect "OK"
  ./hooks/pr-title-validator.sh "[FEAT] -OPERATIONS- test"   # expect exit 0
  which walter-os                            # expect ~/.local/bin/walter-os
  walter-os --version                        # expect a semver

If $PATH doesn't include ~/.local/bin, tell the operator how to add it
to their shell rc and STOP until they confirm they've sourced it.

================================================================================
STEP 5 — VERIFY THE CASCADE LOADS

The agent contract is a three-level cascade: global (this repo) → context
(work/personal/projects-personal/hackathons) → repo (any AGENTS.md in the
current project).

Verify the global cascade is wired:
  test -L ~/.claude/CLAUDE.md && readlink ~/.claude/CLAUDE.md
  # expect: <walter-os-path>/AGENTS.md (or similar symlink)

================================================================================
STEP 6 — REPORT

Print to the operator:

  ✓ Walter-OS Tier I installed.
  ✓ Overlay: ~/.config/walter-os/overlay/
  ✓ Branch flow: <single-tier|three-stage>
  ✓ Hooks active in: ~/.claude/, ~/.codex/

  Next steps:
    - RESTART your agent (Claude Code / Codex CLI / Cursor) so the new
      contract loads. The cascade only takes effect on a fresh process.
    - Optional: add Tier II for skills catalog + MCP configs (15 min).
      → setup/agent-install/tier-2.md

  Anything that didn't fit cleanly:
    [list any STEP that returned non-zero or required operator action]

================================================================================
END
```

---

## What the operator sees

After Tier I:

| Concern | Where it lives |
|---|---|
| Agent rules (work / personal / projects / hackathons) | `~/.config/walter-os/overlay/contexts/<ctx>/AGENTS.md` (overrides) + `~/walter-os/contexts/<ctx>/AGENTS.md` (template) |
| Personal env vars (name, email, jurisdiction, language) | `~/.config/walter-os/overlay/personal.env` |
| Hooks (branch flow, PR title) | `~/.config/walter-os/hooks/` |
| CLI | `~/.local/bin/walter-os` |

All of this lives **outside the cloned repo** so the repo stays
depersonalized and shareable.

## Re-running Tier I

This prompt is idempotent. Re-paste it any time to:
- Change branch flow mode.
- Update operator email / jurisdiction.
- Re-install hooks after a Walter-OS version bump.

The agent reads existing overlay values first and only asks about knobs
that have no answer yet. Say "review everything from scratch" if you
want to redo all 6 questions.

## Next tier

→ [Tier II — local tooling](tier-2.md) adds skills, MCPs, slash commands,
the `obra/superpowers` plugin.
