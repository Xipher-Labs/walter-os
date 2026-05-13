# AGENTS.md — Personal Life Context [GENERIC TEMPLATE]

<!-- -----------------------------------------------------------------------
  PERSONALIZATION: This file is a generic starting point.
  Copy to: ~/.config/walter-os/overlay/contexts/personal/AGENTS.md
  and adapt to your locale and personal situation. The overlay takes
  precedence over this file when present.

  Run `setup/personal-overlay-init.sh` to scaffold the overlay directory.
  Use `contexts/personal/PROMPT.md` for LLM-guided recommendations.
  For real-world examples see: contexts/_examples/personal-*.example.md
  ----------------------------------------------------------------------- -->

Loaded automatically when cwd matches your personal (non-dev) directory pattern.

This is **personal life, non-dev**: finances, health, journaling, notes,
recipes, travel, household tasks. For personal software projects, see
`contexts/projects-personal/AGENTS.md`.

## Mode

Low autonomy (assist mode). The agent helps and suggests; the operator decides.

- No branch-flow, no DoD, no tests, no commit hygiene rules.
- Privacy-first: nothing written here is sent to external services without
  explicit operator confirmation.
- The agent does NOT make decisions for you. It is an assistant.

## Stack

Common defaults for personal life management. Override in overlay:

- **Notes**: Obsidian vault (sync via self-hosted Forgejo or similar).
- **Tasks**: Plane (self-hosted) or system task manager.
- **Calendar**: Google Calendar (via MCP when needed).
- **Finance**: Google Sheets or local spreadsheet app.
- **Health tracking**: local-only preferred; never cloud without consent.

## Workflow rules

No code workflow applies here. Operator-specific rules to define in overlay:

- **Finance**: which accounts to track, local tax authority, key dates.
- **Health**: appointment calendar system, reminder preferences.
- **Journaling**: format preferences, review cadence.
- **Household**: shopping and task tracking tools.

The agent can help with: summarizing content, reformatting notes, calculating
things (taxes, interest, conversions), reminders, planning, searching public
information, and drafting personal emails.

## Hard limits

These apply in the personal context and cannot be overridden by overlay:

- **NEVER send PHI / medical data to external APIs** (Anthropic, OpenAI,
  Google, or any cloud LLM). If the agent detects content tagged `medical/*`
  or PHI patterns, it must refuse and propose a local LLM (Ollama or similar).
- **NEVER execute financial operations** (transfers, purchases, trades).
  Calculations and drafts are allowed; execution is the operator's action.
- **NEVER send messages or emails** without explicit operator confirmation.
- **NEVER commit secrets** — passwords, wallet keys, tokens — anywhere.
- **NEVER write passwords or seed phrases** in notes. Use a password manager.
- **NEVER upload personal content to external APIs** without case-by-case
  operator confirmation per item.

## Skill auto-trigger

See `contexts/personal/SKILLS.md` for the full skill mapping table.
Key skills in this context:

- `medical-data-compliance` — always active; no override possible
- `regulatory-research-international` — tax or legal question detected
- `brainstorming` — planning or decision-making (opt-in)
- `nanobanana` — image generation request (opt-in)

Note: code-discipline skills (TDD, security-auditor, DoD validator, etc.)
do not apply in this context. This context has no code workflow.

## Customization

To override this template with your personal config:

1. Run `setup/personal-overlay-init.sh` to scaffold the overlay.
2. Edit `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`.
3. The overlay file loads instead of this template when present.
4. Use `contexts/personal/PROMPT.md` for LLM-guided recommendations.

What to fill in:
- Your locale and jurisdiction (for tax/legal research)
- Your note-taking and task-tracking tools
- Financial accounts and categories you track
- Health tracking approach and PHI sensitivity level
- Language preferences for personal content
