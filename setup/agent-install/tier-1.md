# Walter-OS — Tier I install via agent

> **For**: operators who want the agent contract (`AGENTS.md` cascade)
> + branch-flow + PR-title hooks across Claude Code, Codex CLI, and
> Cursor. Nothing else.
>
> **Time**: ~5 minutes.
>
> **Cost**: $0.
>
> **Prereqs**:
> - macOS or Linux with `bash`, `git`, `curl`.
> - `yq`, `jq`, and `gh` installed (`install.sh --check` validates).
> - One of: Claude Code, Codex CLI, or a Cursor install (the agent
>   that will execute this prompt).
>
> **How to use**: open the agent in any working directory and paste
> the entire fenced block below. The agent walks you through the
> install and asks the minimum questions.

---

```
================================================================================
WALTER-OS TIER I INSTALL — agent contract only

You are installing Walter-OS Tier I on the operator's local machine.
Tier I gives them:
  - The AGENTS.md three-level cascade (global → context → repo) wired
    into ~/.claude/ and ~/.codex/.
  - The personal overlay scaffold at ~/.config/walter-os/.
  - All Walter-OS hooks declared in walter-os/hooks/.
  - The `walter-os` CLI symlinked into ~/.local/bin/ (resolves via
    $PATH on a default macOS/Ubuntu shell setup).

Tier I does NOT install: skills catalog, MCP configs, slash commands,
self-hosted services, or Council agents. Those come in Tiers II–IV.

GROUND RULES
- Ask ONE question at a time. Wait for the operator's answer.
- For every default, explain WHY it is the default in one sentence.
- After each install step, run a verify command and report PASS/FAIL.
- If a step fails, STOP and surface the error. Do not silently retry.
- Conversation language: match the operator's language.
- Code, paths, and commit messages stay in English.
- The install is idempotent: re-run any time to refresh symlinks.

================================================================================
STEP 1 — CLONE OR DETECT EXISTING

Check if Walter-OS is already cloned:
  test -d /opt/walter-os || test -d "$HOME/walter-os" || \
    test -d "$HOME/Projects-Personal/walter-os"

If found, cd into that path. If not, ask the operator:
  "Where should I clone Walter-OS? (default: $HOME/walter-os)"

Then:
  git clone https://github.com/Xipher-Labs/walter-os.git <path>
  cd <path>

Verify:
  test -f AGENTS.md && test -f install.sh && echo OK

================================================================================
STEP 2 — DEPENDENCY CHECK

Run:
  ./install.sh --check

This validates: bash ≥4, git, curl, jq, yq, gh, and the optional
tooling Walter-OS expects (shellcheck, gitleaks, etc.). If any
required tool is missing, surface the brew/apt/snap command to
install it and STOP. Do not proceed with broken deps — yq especially
is a hard dependency for approval-gate.

================================================================================
STEP 3 — PERSONAL OVERLAY (operator personalization stays out-of-repo)

Walter-OS expects an overlay at ~/.config/walter-os/overlay/. Check
if it exists:
  test -d "$HOME/.config/walter-os/overlay"

If not, run the scaffold:
  ./setup/personal-overlay-init.sh

That creates ~/.config/walter-os/overlay/{personal.env,contexts/}.

Then prompt the operator for these 6 values, ONE AT A TIME, and write
each to ~/.config/walter-os/overlay/personal.env after their answer:

  3.1  Display name (used in commits if not set in ~/.gitconfig already)
       → WALTER_OPERATOR_NAME

  3.2  Primary email (used for git commits + future CF Access policies
       if you ever deploy Tier III)
       → WALTER_OPERATOR_EMAIL

  3.3  Casual conversation language (default: en)
       Options: es / en / pt / fr / other
       → WALTER_LANG

  3.4  Time zone (default: $(date +%Z) — your system default; common
       overrides: America/Argentina/Buenos_Aires, Europe/Berlin,
       America/New_York, Asia/Tokyo)
       → TZ

  3.5  Branch flow mode (default: single-tier — recommended for solo
       or small team). See ADR 0013 for the trade-off.
       Options:
         single-tier   feature/<slug> → main directly
         three-stage   feature/<slug> → dev → staging → main
       → WALTER_BRANCH_FLOW

  3.6  Jurisdiction for regulatory-research (default: none)
       Examples: Argentina, EU, US-California, Brazil.
       Skip with "none" if no regulated domain.
       → WALTER_JURISDICTION

Use atomic write (mktemp + mv) so a partial answer cycle doesn't
corrupt personal.env. Show the resulting file to the operator and
ask: "Looks right? (yes/no)"

================================================================================
STEP 4 — INSTALL: SYMLINKS + HOOKS + CLI

Run:
  ./install.sh --dry-run    # preview every write
  ./install.sh --upgrade    # apply (idempotent)

The --upgrade path runs run_step_0 which:
  - Symlinks AGENTS.md and the contexts/ files into ~/.claude/ and
    ~/.codex/ (whichever is installed).
  - Installs every hook declared in walter-os/hooks/ into the relevant
    settings file (~/.claude/settings.json, ~/.codex/config.toml).
  - Symlinks walter-os/bin/walter-os → ~/.local/bin/walter-os (ADR 0014).
  - Writes the personal env file at ~/.config/walter-os/env.
  - Writes the secrets template at ~/.config/walter-os/secrets.env.

Verify:
  command -v walter-os            # expect: ~/.local/bin/walter-os
  walter-os --version             # expect: "Walter-OS vX.Y.Z" (the
                                  # `--version` alias routes to the
                                  # `version` subcommand, which reads
                                  # the canonical VERSION file)

If `walter-os` is NOT found, ~/.local/bin/ may not be on $PATH.
install.sh prints the shell-rc edit needed. Ask the operator to add
it to their ~/.zshrc or ~/.bashrc, source the rc, and retry.

================================================================================
STEP 5 — VERIFY THE CASCADE LOADS

The agent contract is a three-level cascade: global (this repo) →
context (work/personal/projects-personal/hackathons) → repo (any
AGENTS.md in the current project).

Verify the global cascade is wired:
  test -L ~/.claude/CLAUDE.md && readlink ~/.claude/CLAUDE.md
  # expect a path inside the walter-os clone

  test -L ~/.codex/AGENTS.md && readlink ~/.codex/AGENTS.md
  # expect a path inside the walter-os clone (when Codex CLI is installed)

Then run the doctor with the tier filter:
  walter-os doctor --tier 1

Required ✓:
  - WALTER_OS_HOME exists
  - env file present
  - secrets template present
  - ~/.claude/CLAUDE.md symlinked (if Claude Code installed)
  - ~/.codex/AGENTS.md symlinked (if Codex CLI installed)
  - ~/.local/bin/walter-os symlinked
  - jq + git + gh installed

Acceptable ✗ (one of {claude, codex} suffices):
  - `claude CLI in PATH` — only required if the operator uses Claude Code
  - `codex CLI in PATH` — only required if the operator uses Codex CLI
  - At least ONE of the two must be ✓ for a working install; Cursor
    users may legitimately have both ✗ (Cursor doesn't ship a CLI).

If any REQUIRED check is ✗, address it (often: missing jq or yq).
The acceptable-✗ checks are informational; they tell you which agent
CLIs the operator has on this box.

================================================================================
STEP 6 — REPORT

Print to the operator:

  ✓ Walter-OS Tier I installed.
  ✓ Overlay: ~/.config/walter-os/overlay/
  ✓ Branch flow: <single-tier|three-stage>
  ✓ Hooks active in: ~/.claude/, ~/.codex/
  ✓ CLI on PATH: walter-os <version>

  Next steps:
    - RESTART your agent (Claude Code / Codex CLI / Cursor) so the
      new contract loads. The cascade only takes effect on a fresh
      agent process.
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
| Agent rules (work / personal / projects / hackathons) | `~/.config/walter-os/overlay/contexts/<ctx>/AGENTS.md` (overrides) + `walter-os/contexts/<ctx>/AGENTS.md` (template) |
| Personal env (name, email, jurisdiction, language) | `~/.config/walter-os/overlay/personal.env` |
| Hooks | `~/.claude/settings.json` (Claude Code), `~/.codex/config.toml` (Codex CLI) |
| CLI | `~/.local/bin/walter-os` → `<walter-os-clone>/bin/walter-os` |

All overlay files live **outside the cloned repo** so the repo stays
depersonalized and shareable.

## Re-running Tier I

The prompt is idempotent. Re-paste any time to:
- Change branch flow mode.
- Update operator email / jurisdiction.
- Re-install hooks after a `git pull` on walter-os.

Existing overlay answers are preserved unless the operator says
"review everything from scratch".

## Next tier

→ [Tier II — local tooling](tier-2.md) adds skills, MCPs, slash
commands, the `obra/superpowers` plugin.
