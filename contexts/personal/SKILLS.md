# Personal Life Context — Skill Auto-Trigger Mapping

This table documents which Walter-OS skills are active in the personal context,
the condition that triggers each, and whether the skill is auto-loaded or
opt-in. Skills are invoked by the agent based on trigger conditions; this
table documents the rules but does not need to be parsed programmatically.

Note: code-discipline skills (TDD, security-auditor, DoD validator, etc.) do
not appear in this table — they are not applicable to the personal life context.

For the source skill files, see: `skills/<skill-name>/SKILL.md`

| Skill | Source | Trigger condition | Mode | Notes |
|---|---|---|---|---|
| `medical-data-compliance` | walter-os | Always active in personal context — no override | auto | Blocks any PHI/medical data from going to external APIs; local LLM only |
| `regulatory-research-international` | walter-os | Tax, legal, or regulatory question detected | auto | Requires WALTER_JURISDICTION env var for jurisdiction-specific answers |
| `brainstorming` | superpowers | Planning or decision-making task | opt-in | Invoke explicitly: "help me brainstorm options for..." |
| `nanobanana` | walter-os | Image generation request | opt-in | Invoke explicitly: "generate an image of..." |
| `systematic-debugging` | superpowers | Troubleshooting a broken tool or workflow | opt-in | Applies to non-code tools (spreadsheet formulas, automation, etc.) |

## What is NOT in this context

The following skills are intentionally absent from the personal context:

- `test-driven-development` — no code workflow in personal context
- `definition-of-done-validator` — no spec/AC workflow
- `web-security-baseline` — no network code
- `data-migration-safety` — no database migrations
- `security-auditor` (agent) — no auth or crypto code
- `frontend-quality` — no UI components to audit
- `hackathon-spinup` — wrong context; use hackathons context instead
- `brand-creation` — use projects-personal context for software projects

## Notes

- "auto" means the skill triggers automatically when the condition is met.
- "opt-in" means the operator or agent invokes the skill explicitly.
- PHI handling is non-negotiable: `medical-data-compliance` cannot be
  disabled or bypassed by the overlay.
- Add personal-specific tools in your overlay's AGENTS.md skill section
  (e.g., a custom Obsidian automation skill).
