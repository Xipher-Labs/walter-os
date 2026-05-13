# Work Context — Skill Auto-Trigger Mapping

This table documents which Walter-OS skills are active in the work context,
the condition that triggers each, and whether the skill is auto-loaded or
opt-in. Skills are invoked by the agent based on trigger conditions; this
table documents the rules but does not need to be parsed programmatically.

For the source skill files, see: `skills/<skill-name>/SKILL.md`

| Skill | Source | Trigger condition | Mode | Notes |
|---|---|---|---|---|
| `web-security-baseline` | walter-os | Any PR touching network endpoints, auth surfaces, or public-facing APIs | auto | Blocks PR if baseline violations found |
| `frontend-quality` | walter-os | Any PR with UI component changes or CSS modifications | auto | Covers a11y, performance, bundle size |
| `data-migration-safety` | walter-os | Any DB migration file present in the diff | auto | Checks rollback path, no-downtime requirements |
| `brainstorming` | superpowers | Before any major spec or design decision | auto | Runs before `/write-plan` for major tasks |
| `writing-plans` | superpowers | Any task classified as major (> 200 LOC, critical path) | auto | Produces `docs/specs/<slug>.md` + plan file |
| `executing-plans` | superpowers | When a plan file exists and work begins | auto | Drives task-by-task execution |
| `test-driven-development` | superpowers | All code changes (mandatory in work context) | auto | RED-GREEN-REFACTOR enforced; skipping RED is a violation |
| `verification-before-completion` | superpowers | Before every PR creation | auto | Runs DoD checklist before `gh pr create` |
| `code-reviewer` | superpowers | Review phase of every PR | auto | Fresh-context subagent; never inherits implementer context |
| `systematic-debugging` | superpowers | Bug investigation or test failure analysis | auto | Triggers when agent encounters an unexpected failure |
| `root-cause-tracing` | superpowers | Post-incident or recurring failure pattern | opt-in | Invoke explicitly: "run root-cause-tracing on this failure" |
| `definition-of-done-validator` | walter-os | Before PR creation | auto | Every AC in spec must have a mapped test |
| `security-auditor` (agent) | walter-os | Any change in auth/, crypto/, PHI-adjacent code, or money flows | auto-escalation | Escalates to a dedicated security-auditor subagent |
| `daily-supply-chain-audit` | walter-os | First session of the day | auto | Runs via `daily-audit-gate.sh` hook |
| `pr-review` | walter-os | PR review phase | auto | Checklist; complements superpowers' code-reviewer |
| `defensive-programming` | superpowers | Any function handling external input or network data | opt-in | Apply explicitly on security-sensitive code paths |

## Notes

- "auto" means the skill is triggered automatically when the condition is met.
- "auto-escalation" means the agent escalates to a subagent without asking.
- "opt-in" means the operator or agent invokes the skill explicitly.
- Add domain-specific skills (e.g., `solana-rpc-review`, `ansible-playbook-review`)
  in your overlay's AGENTS.md skill section.
