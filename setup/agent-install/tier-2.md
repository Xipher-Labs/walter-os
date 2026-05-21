# Walter-OS — Tier II install via agent

> **For**: operators who already ran Tier I and now want the full local
> toolkit — skills catalog, MCP profiles, slash commands, and the
> `obra/superpowers` plugin.
>
> **Time**: ~15 minutes.
>
> **Cost**: $0.
>
> **Prereqs**:
> - Tier I installed and verified ([`tier-1.md`](tier-1.md)).
> - Claude Code installed (Codex CLI optional — skills work on both;
>   slash commands are Claude Code only today).
>
> **How to use**: paste the entire fenced block below into your agent.

---

```
================================================================================
WALTER-OS TIER II INSTALL — local tooling (skills, MCPs, slash commands)

You are installing Walter-OS Tier II on top of Tier I.

Note: install.sh does NOT have separate --skills / --mcp-default /
--commands flags. The single `--upgrade` subcommand re-runs run_step_0
which already does all of these. The granular concept exists in the
tier description only; do not look for fictional flags.

Tier II completes:
  - The full skills catalog (~50 skills) symlinked into ~/.claude/skills/
    AND ~/.codex/skills/ (whichever is installed).
  - Subagents symlinked into ~/.claude/agents/.
  - Slash commands symlinked into ~/.claude/commands/.
  - The default MCP profile merged into ~/.claude/settings.json
    (preserving any operator-added MCPs already there).
  - Codex config at ~/.codex/config.toml (idempotent — pass --upgrade
    to regenerate if needed).
  - The `obra/superpowers` plugin (TDD, planning, worktrees) — operator
    runs this themselves inside Claude Code.

Tier II does NOT install: self-hosted services or Council agents.

GROUND RULES (same as Tier I)
- Ask ONE question at a time.
- Explain each default.
- Verify after each step.
- Stop on errors.
- Match operator language; keep code/paths in English.

================================================================================
PRECHECK — verify Tier I

Run:
  walter-os doctor --tier 1

If any check returns ✗, STOP and tell the operator to re-run Tier I
first ([`tier-1.md`](tier-1.md)). Do not proceed with a broken Tier I
foundation.

================================================================================
STEP 1 — INSTALL obra/superpowers PLUGIN (operator action)

This is mandatory. AGENTS.md depends on these skills:
  /brainstorm, /write-plan, /execute-plan, test-driven-development,
  systematic-debugging, using-git-worktrees, verification-before-completion.

Inside Claude Code, the operator runs (you cannot run this directly
because it's an interactive Claude Code slash command):

  /plugin marketplace add obra/superpowers-marketplace
  /plugin install superpowers@superpowers-marketplace

Then restart Claude Code.

Tell the operator EXACTLY these two commands, ask them to run them
in Claude Code, restart, then come back and confirm. Wait for "done".

Verify after they restart:
  ls ~/.claude/plugins/ 2>/dev/null | grep -i superpowers
  # expect a directory matching the plugin name

If Codex CLI is also installed and a parallel Codex adapter is
available, point the operator at https://github.com/obra/superpowers
README for the current Codex install path.

================================================================================
STEP 2 — RUN install.sh --upgrade (does everything Tier II needs)

From the walter-os clone:
  cd <walter-os-clone>
  ./install.sh --upgrade

This single command (one and only one) handles:
  - skills/ → ~/.claude/skills/ + ~/.codex/skills/  (symlink)
  - agents/ → ~/.claude/agents/                     (symlink)
  - commands/ → ~/.claude/commands/                 (symlink)
  - default MCP profile merged into ~/.claude/settings.json
  - daily-supply-chain-audit hook installed
  - approval-gate hook installed
  - PATH symlink for walter-os CLI (carry-over from Tier I)

Verify:
  ls -la ~/.claude/skills/ | grep -c -- '-> '
  # expect a non-trivial count of symlinks (~50)

  jq -r '.mcpServers | keys[]' ~/.claude/settings.json 2>/dev/null | wc -l
  # expect ≥ 1 MCP entry (count depends on which MCPs you have
  # credentials for — install.sh skips MCPs whose env vars are unset).

  test -f ~/.claude/commands/pr.md && \
    test -f ~/.claude/commands/audit.md && \
    echo "slash commands OK"

================================================================================
STEP 3 — HIGH-RISK MCP PROFILE (optional, opt-in only)

Walter-OS ships a second MCP profile for money-spending / lateral-
movement-risk MCPs (hcloud, cloudflare, vercel, stripe, railway,
bitwarden). It is NOT loaded by default.

If the operator wants the high-risk profile pre-written for later
swap-in:

  walter-os profile high-risk    # swap in
  walter-os profile default      # swap back

Ask the operator if they want to install (write) it now. If yes:
  walter-os profile-bootstrap init high-risk

(Token configuration for each high-risk MCP is the operator's
follow-up via Infisical or their secrets manager — not in scope
for this tier.)

================================================================================
STEP 4 — DAILY SUPPLY-CHAIN AUDIT

Walter-OS expects the daily-supply-chain-audit skill to run before
the first agent session of the day. install.sh --upgrade already
installs the hook that gates the first session per day. Verify:

  test -x ~/.config/walter-os/hooks/daily-audit-gate.sh && \
    echo "daily-audit-gate.sh installed"

Alternative: a cron-based run that doesn't gate sessions:
  walter-os audit schedule

Ask which the operator prefers. Default to the hook (already installed).

================================================================================
STEP 5 — VERIFY THE FULL TIER II STACK

Run:
  walter-os doctor --tier 2

Expected output (subset):
  ✓ WALTER_OS_HOME exists
  ✓ env file present
  ✓ ~/.claude/CLAUDE.md symlinked to walter-os
  ✓ ~/.codex/AGENTS.md symlinked to walter-os
  ✓ ~/.local/bin/walter-os symlinked
  ✓ ~/.claude/settings.json present
  ✓ skills symlinked into ~/.claude/skills
  ✓ audit ran today
  ✓ claude CLI in PATH
  ✓ codex CLI in PATH
  ✓ jq installed
  ✓ git installed
  ✓ gh (GitHub CLI) installed

  (Bootstrap tooling section — optional checks)

If any tier-1 or tier-2 line is ✗, stop and surface the error before
moving on.

================================================================================
STEP 6 — REPORT

Print to the operator:

  ✓ Walter-OS Tier II installed.
  ✓ Skills: <N> symlinked into ~/.claude/skills/
  ✓ Slash commands: /pr, /audit, /ingest, /review, /security-review
  ✓ MCPs: default profile active
  ✓ Daily audit hook: active

  Next steps:
    - RESTART Claude Code to pick up the new MCPs + slash commands.
    - Optional: add Tier III for the self-hosted stack (1–2 hours,
      costs ~€25–50/mo for a Hetzner VM).
      → setup/agent-install/tier-3.md

  Tokens still needed (per the MCPs you have credentials for):
    [list any MCP in ~/.claude/settings.json that has a placeholder
     token — operator pushes real values to Infisical or their secrets
     store before relying on them]

================================================================================
END
```

---

## What the operator sees

After Tier II, in addition to Tier I:

| Concern | Where it lives |
|---|---|
| Skills | `~/.claude/skills/*` (symlinks to `walter-os/skills/*`) + `~/.codex/skills/` |
| Subagents | `~/.claude/agents/*` |
| Slash commands | `~/.claude/commands/*` |
| MCP default profile | `~/.claude/settings.json` |
| Codex CLI config | `~/.codex/config.toml` |
| Superpowers plugin | `~/.claude/plugins/superpowers/` |
| Daily audit hook | `~/.config/walter-os/hooks/daily-audit-gate.sh` (referenced by `~/.claude/settings.json`) |

## Re-running Tier II

Idempotent. Re-paste to:
- Bump skills/agents/commands after a `git pull` on walter-os.
- Re-merge MCPs after editing `mcp/servers.json`.
- Swap the high-risk profile in/out for provisioning work.

## Next tier

→ [Tier III — self-hosted stack](tier-3.md) provisions a Hetzner VM
with 25+ services behind Cloudflare Access.
