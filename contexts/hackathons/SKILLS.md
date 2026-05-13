# Hackathons Context — Skill Auto-Trigger Mapping

This table documents which Walter-OS skills are active in the hackathons
context, the condition that triggers each, and whether the skill is
auto-loaded or opt-in. Skills are invoked by the agent based on trigger
conditions; this table documents the rules but does not need to be parsed
programmatically.

For the source skill files, see: `skills/<skill-name>/SKILL.md`

| Skill | Source | Trigger condition | Mode | Notes |
|---|---|---|---|---|
| `hackathon-spinup` | walter-os | Session start when WALTER_CONTEXT=hackathons | auto | Orchestrates: brand → landing → MVP architecture → demo script |
| `brainstorming` | superpowers | Ideation phase (hours 0–6) | auto | Runs at session start; drives theme analysis and API inventory |
| `writing-plans` | superpowers | Architecture or major feature decision | auto | Keeps architecture decisions fast and documented |
| `executing-plans` | superpowers | When a plan exists and implementation begins | auto | Drives focused task execution under time pressure |
| `verification-before-completion` | superpowers | Before demo submission or any public push | auto | Rapid DoD check scoped to demo requirements only |
| `brand-creation` | walter-os | Branding sprint or logo needed | opt-in | Invoke explicitly: "run brand-creation for this project" |
| `landing-page-fast` | walter-os | Landing page or public URL needed | opt-in | Invoke explicitly: "build a landing page" |
| `nanobanana` | walter-os | Image or asset generation request | opt-in | Invoke explicitly: "generate an image of..." |
| `test-driven-development` | superpowers | Judging-critical code paths only | opt-in | Use selectively — full TDD cycle too slow for hackathon pace |
| `systematic-debugging` | superpowers | Blocking bug during core loop implementation | auto | Triggers when agent cannot resolve a failure in 2 attempts |
| `web-security-baseline` | walter-os | User-facing project with auth or public API | opt-in | Invoke explicitly for projects that handle user data |
| `regulatory-research-international` | walter-os | Project touches a regulated domain (health, finance, identity) | opt-in | Set WALTER_JURISDICTION and WALTER_REGULATORY_DOMAIN first |

## What is different from work and projects-personal

- TDD is **opt-in** in hackathons, not mandatory. Apply it only on the
  paths the demo depends on.
- `definition-of-done-validator` is replaced by `verification-before-completion`
  with a hackathon-scoped checklist (demo-first, not spec-first).
- `security-auditor` agent is not auto-escalated; `web-security-baseline`
  is opt-in. Speed takes priority over security depth unless user data is
  involved.
- PHI limits still apply via global rules even if `medical-data-compliance`
  is not explicitly listed as auto — it cannot be disabled.

## Post-hackathon skill reset

After the event, when migrating the project to `projects-personal/`:

1. Remove WALTER_CONTEXT=hackathons from your environment.
2. Run `walter-os doctor` to re-apply normal discipline rules.
3. Add `test-driven-development` back as mandatory for continued development.
4. Run `definition-of-done-validator` on any spec you write for continued features.
