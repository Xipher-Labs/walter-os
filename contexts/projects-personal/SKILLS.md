# Projects-Personal Context — Skill Auto-Trigger Mapping

This table documents which Walter-OS skills are active in the projects-personal
context, the condition that triggers each, and whether the skill is auto-loaded
or opt-in. Skills are invoked by the agent based on trigger conditions; this
table documents the rules but does not need to be parsed programmatically.

For the source skill files, see: `skills/<skill-name>/SKILL.md`

| Skill | Source | Trigger condition | Mode | Notes |
|---|---|---|---|---|
| `web-security-baseline` | walter-os | Any PR touching network endpoints, auth surfaces, or public-facing APIs | auto | Same as work context |
| `frontend-quality` | walter-os | Any PR with UI component changes or CSS modifications | auto | Same as work context |
| `data-migration-safety` | walter-os | Any DB migration file present in the diff | auto | Same as work context |
| `brainstorming` | superpowers | Before any major spec or design decision | auto | Runs before `/write-plan` for major tasks |
| `writing-plans` | superpowers | Any task classified as major | auto | Produces `docs/specs/<slug>.md` + plan file |
| `executing-plans` | superpowers | When a plan file exists and work begins | auto | Drives task-by-task execution |
| `test-driven-development` | superpowers | Major code changes (mandatory); small tasks may use inline tests | auto | Required for major tasks; encouraged for small |
| `verification-before-completion` | superpowers | Before every PR creation | auto | Runs DoD checklist |
| `code-reviewer` | superpowers | Review phase of every PR | auto | Fresh-context subagent |
| `systematic-debugging` | superpowers | Bug investigation or unexpected failure | auto | Same as work context |
| `definition-of-done-validator` | walter-os | Before PR creation | auto | Every AC in spec must have a mapped test |
| `security-auditor` (agent) | walter-os | Auth, crypto, PHI, or money flow changes | auto-escalation | Mandatory escalation, same as work |
| `hackathon-spinup` | walter-os | WALTER_CONTEXT=hackathons set, or project name contains "hackathon" | opt-in trigger | Orchestrates brand → MVP → demo script |
| `brand-creation` | walter-os | New project setup or brand design request | opt-in | Invoke explicitly: "run brand-creation for this project" |
| `regulatory-research-international` | walter-os | Project touches GDPR, HIPAA, PCI-DSS, or SOC 2 domains | opt-in | Set WALTER_JURISDICTION and WALTER_REGULATORY_DOMAIN first |
| `medical-data-compliance` | walter-os | Any health-related data or PHI detected in the project | auto-escalation | Cannot be disabled; escalates to compliance review |
| `landing-page-fast` | walter-os | New product landing page needed | opt-in | Invoke explicitly: "build a landing page for this project" |
| `nanobanana` | walter-os | Image or asset generation request | opt-in | Invoke explicitly: "generate an image of..." |
| `daily-supply-chain-audit` | walter-os | First session of the day | auto | Runs via `daily-audit-gate.sh` hook |

## Notes

- "auto" means the skill triggers automatically when the condition is met.
- "auto-escalation" means the agent escalates to a subagent without asking.
- "opt-in" means the operator or agent invokes the skill explicitly.
- This context has higher autonomy than work; the agent will invoke opt-in
  skills more readily when the trigger condition is obvious.
- Add project-specific skills in your overlay's AGENTS.md skill section.
