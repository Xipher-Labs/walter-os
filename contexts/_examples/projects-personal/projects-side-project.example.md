> **EXAMPLE FILE — Side Project Developer (Working a Day Job)**
> This file shows how a developer with a full-time job might configure their
> projects-personal context overlay for side projects. All org and project
> names are fictional. Replace every `[BRACKETED]` or placeholder value with
> your actual situation before placing this file at
> `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`.

# AGENTS.md — Projects-Personal Context [Side Project Developer]

## Active projects

- **weekend-tool** — Open-source CLI tool for [use case]. Stack: Rust.
  Stage: public, maintained on weekends. Real users: ~50 stars on GitHub.
- **automation-script** — Personal automation scripts (no public users).
  Stack: Python. Stage: personal use only, no deployment.

## Stack

- **Languages**: Rust (primary), Python (scripts), TypeScript (occasional)
- **Deploy**: GitHub Releases (CLIs), no servers for personal projects
- **Issue tracker**: GitHub Issues (simple, free)
- **Time budget**: ~4 hours/weekend. Fast iterations, low polish OK.

## Workflow rules

### Time-sensitive defaults

- Prefer simple solutions over elegant ones — time is scarce.
- Auto-PR enabled (don't need manual confirmation for personal projects).
- Skip E2E tests if writing them takes longer than the feature itself
  (flag in PR body: "E2E deferred — tracked in issue #NNN").
- CI must pass before merge. Don't bypass CI.

### Real users vs no real users

- If project has real users: treat it like production. No breaking changes
  without a migration plan or major version bump.
- If project has no real users: acceptable to break things on `main` as long
  as it's documented in the commit message.

### Breakage tolerance

- `feature/*`: break freely, experiment, throw away code.
- `main`: stable enough that I'm not embarrassed if someone clones it.
- No `staging` environment for personal projects — dev → main directly
  after PR review.

## Hard limits

- Never commit secrets (even to private repos — repos get public by accident).
- Never merge without at least one quick self-review of the diff.
- Never introduce a paid dependency for a zero-revenue project without
  checking if there's a free/open-source alternative first.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **projects-personal** context. I have a
> full-time job and work on side projects in my spare time. My specifics:
>
> - Time budget for side projects: [hours per week]
> - Number of active projects: [N]
> - Do any projects have real users? [yes (N users) / no]
> - Do any projects generate revenue? [yes ($X/month) / no]
> - Primary language(s): [Rust / Go / TypeScript / Python / other]
> - Deploy target: [GitHub Releases / Vercel / Fly.io / none]
> - Issue tracker: [GitHub Issues / Linear / Notion / none]
> - Breakage tolerance: [high (personal only) / medium (small OSS users) / low (paying users)]
> - Any regulated domains: [GDPR / HIPAA / none]
>
> Based on the generic Walter-OS projects-personal context template, generate
> a customized `AGENTS.md` for me. Output only the Markdown content of the
> `AGENTS.md` file, ready to drop into
> `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`.
