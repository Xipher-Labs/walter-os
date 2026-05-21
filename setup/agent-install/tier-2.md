# Walter-OS — Tier II install via agent

> **For**: operators who already ran Tier I and now want the full local
> toolkit — skills catalog, MCP profiles, slash commands, and the
> `obra/superpowers` plugin.
>
> **Time**: ~15 minutes.
>
> **Prereqs**:
> - Tier I installed and verified ([`tier-1.md`](tier-1.md)).
> - Claude Code installed (Codex CLI optional — skills work on both;
>   slash commands are Claude Code only today).
>
> **How to use**: paste the entire block between the `===` lines below
> into your agent.

---

```
================================================================================
WALTER-OS TIER II INSTALL — local tooling (skills, MCPs, slash commands)

You are installing Walter-OS Tier II on top of Tier I. Tier II gives:
  - The full skills catalog (~50 skills) symlinked into ~/.claude/skills/.
  - The default MCP profile (29 read-mostly MCPs) at ~/.claude/settings.json.
  - The high-risk MCP profile pre-written at ~/.claude/settings.high-risk.json
    (NOT activated by default — operator swaps in for provisioning work).
  - The `obra/superpowers` plugin (TDD, planning, worktrees).
  - Slash commands: /level, /pr, /ingest, /review, /security-review.

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
  test -d ~/.config/walter-os/overlay && \
    test -x ~/.local/bin/walter-os && \
    test -s ~/.config/walter-os/overlay/personal.env && \
    echo OK

If any of those fail → STOP and tell the operator to run Tier I first.

================================================================================
STEP 1 — INSTALL obra/superpowers PLUGIN

This is mandatory. AGENTS.md depends on these skills:
  /brainstorm, /write-plan, /execute-plan, test-driven-development,
  systematic-debugging, using-git-worktrees, verification-before-completion.

Inside Claude Code, the operator runs (you cannot run this directly
because it's an interactive Claude Code command):

  /plugin marketplace add obra/superpowers-marketplace
  /plugin install superpowers@superpowers-marketplace

Then restart Claude Code.

Tell the operator EXACTLY these two commands, and ask them to run them
in Claude Code, then come back and confirm. Wait for their "done".

Verify after they restart:
  ls ~/.claude/plugins/ | grep -i superpowers   # expect a directory

If Codex CLI is also installed, install the parallel package:
  npm install -g @obra/superpowers-codex    # or whatever the Codex
                                             # adapter is named
(Check the superpowers README for the current Codex install path.)

================================================================================
STEP 2 — SYMLINK SKILLS CATALOG

From the cloned walter-os repo:
  ./install.sh --skills

This symlinks every skill in walter-os/skills/* into ~/.claude/skills/
without copying (so a `git pull` on walter-os updates them automatically).

Existing skills with the same name are preserved (your custom skills
override Walter-OS skills — same precedence as AGENTS.md cascade).

Verify:
  ls -la ~/.claude/skills/ | grep -c "walter-os"
  # expect ~50 (the number of Walter-OS skills)

================================================================================
STEP 3 — WRITE THE TWO MCP PROFILES

Default profile (29 MCPs, read-mostly): github, filesystem, slack, linear,
plane, supabase, gmail, google_calendar, google_drive, telegram, notion,
obsidian, elevenlabs, grafana, forgejo, postgres, sentry, playwright,
maestro, sequential_thinking, memory, brave_search, penpot, +6 more.

High-risk profile (6 MCPs, opt-in): hetzner, cloudflare, vercel, stripe,
railway, bitwarden.

Ask the operator:
  4.1  Which of the 29 default MCPs are NOT relevant for you?
       (e.g. skip "slack" if you don't use Slack. Show the full list.)
  4.2  Do you have credentials ready for the MCPs you want?
       For each MCP that requires a token, ask separately and write it
       to the corresponding Infisical path OR (if no Infisical) to the
       overlay env file at ~/.config/walter-os/overlay/mcp-tokens.env
       (chmod 600).

Then run:
  ./install.sh --mcp-default

This generates ~/.claude/settings.json with the filtered MCP list and
the operator's tokens substituted.

For the high-risk profile, run:
  ./install.sh --mcp-high-risk

This generates ~/.claude/settings.high-risk.json (NOT active). The
operator activates it manually when needed:
  walter-os profile high-risk    # swap in
  walter-os profile default      # swap back

Verify:
  test -s ~/.claude/settings.json
  test -s ~/.claude/settings.high-risk.json
  jq '.mcpServers | keys | length' ~/.claude/settings.json
  # expect ~29 minus whatever the operator skipped

================================================================================
STEP 4 — SLASH COMMANDS

Install Walter-OS slash commands into ~/.claude/commands/:
  ./install.sh --commands

Commands installed:
  /pr               — prepare/open PR after implementer is done
  /ingest <url>     — ingest source into the operator wiki
  /review           — request structured PR review
  /security-review  — invoke security-auditor agent
  /audit            — run daily-supply-chain-audit on demand
  /init             — initialize a new project (induction interview)

(Note: /brainstorm, /write-plan, /execute-plan come from superpowers,
not Walter-OS.)

Verify:
  ls ~/.claude/commands/ | wc -l   # expect ≥ 6

================================================================================
STEP 5 — DAILY SUPPLY-CHAIN AUDIT

Walter-OS expects the daily-supply-chain-audit skill to run before the
first session of the day. Two ways to wire it:

  a) Hook (default, recommended): hooks/daily-audit-gate.sh blocks the
     first agent session of the day until the audit completes. Run:
       ./install.sh --daily-audit-hook
     The first session of the day adds ~10 sec of audit. After that,
     instant.

  b) Cron (silent): runs at 08:30 daily, writes report to
     ~/.config/walter-os/audit-YYYY-MM-DD.md. No session blocking.
       walter-os audit schedule

Ask which one the operator prefers. Default to (a).

Verify (for option a):
  test -x ~/.config/walter-os/hooks/daily-audit-gate.sh

================================================================================
STEP 6 — VERIFY THE FULL STACK

Run end-to-end:
  walter-os doctor

Expected output:
  ✓ Overlay present
  ✓ Hooks active (branch-flow-guard, pr-title-validator, daily-audit-gate)
  ✓ Skills catalog: 47 skills linked
  ✓ MCP default profile: 24 servers configured (5 skipped per operator)
  ✓ MCP high-risk profile: written, not active
  ✓ Superpowers plugin: detected
  ✓ Slash commands: 6 installed

If any line says ✗, stop and surface the error.

================================================================================
STEP 7 — REPORT

Print to the operator:

  ✓ Walter-OS Tier II installed.
  ✓ Skills: <N> available (run `walter-os skills list` to see)
  ✓ MCPs: default profile active, high-risk written but not active
  ✓ Slash commands: /pr, /ingest, /review, /security-review, /audit, /init
  ✓ Daily audit: <hook|cron>

  Next steps:
    - RESTART Claude Code to pick up the new MCPs + slash commands.
    - Optional: add Tier III for the self-hosted stack (1–2 hours, costs
      ~€25-50/mo for Hetzner VM).
      → setup/agent-install/tier-3.md

  Tokens still needed (per the MCPs you enabled):
    [list any MCP that has placeholder tokens — push to a password
     manager or Infisical before relying on them]

================================================================================
END
```

---

## What the operator sees

After Tier II, in addition to Tier I:

| Concern | Where it lives |
|---|---|
| Skills | `~/.claude/skills/*` (symlinks to `walter-os/skills/*`) |
| Default MCPs | `~/.claude/settings.json` |
| High-risk MCPs | `~/.claude/settings.high-risk.json` (inactive until swapped) |
| Slash commands | `~/.claude/commands/*.md` |
| Superpowers plugin | `~/.claude/plugins/superpowers/` |
| Daily audit | hook in `~/.claude/settings.json` OR cron job |

## Re-running Tier II

Idempotent. Re-paste to:
- Add MCPs you skipped on first install.
- Bump skills catalog after a Walter-OS `git pull`.
- Swap between default and high-risk MCP profile.

## Next tier

→ [Tier III — self-hosted stack](tier-3.md) provisions a Hetzner VM with
25+ services behind Cloudflare Access (Plane, Forgejo, Grafana, n8n,
Infisical, LiteLLM, Penpot, Metabase, etc.).
