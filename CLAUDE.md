# Claude Code entry — Walter-OS

Read `@AGENTS.md` in this directory for the full agent contract. That file is the
cross-tool source of truth (Claude Code, Codex CLI, Cursor).

## Required plugin

Walter-OS expects **`obra/superpowers`** to be installed:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Then restart Claude Code. Without it, slash commands `/brainstorm`,
`/write-plan`, `/execute-plan` won't work and several skills referenced
in `AGENTS.md` won't be available.

## Claude Code-specific additions

- **Compaction** — when context gets compacted, preserve the full list of modified
  files, the active spec path (`docs/specs/<slug>.md`), and any pending verification
  steps. Drop tool output noise first.
- **Subagent preference** — for any task that involves searching >5 files or
  reading >2000 lines of unrelated code, dispatch to a subagent instead of doing
  it inline. Keep main context clean.
- **Skill preloading** — `nanobanana`, `daily-supply-chain-audit`,
  `definition-of-done-validator` are high-priority. Preload via `skills:` field
  in subagent definitions when relevant.
- **Memory** — agent memory directories live at `.claude/agent-memory/<agent>/`
  per project. Reviewer and security-auditor maintain durable notes there.
- **Hooks** — see `~/.claude/settings.json`. Never bypass without operator
  approval logged in the chat.

@AGENTS.md
@contexts/work/AGENTS.md
@contexts/projects-personal/AGENTS.md
@contexts/personal/AGENTS.md
