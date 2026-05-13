> **EXAMPLE FILE — Hackathon Team Lead**
> This file shows how a team lead coordinating a small group at a hackathon
> might configure their hackathon context overlay. All project and org names
> are fictional. Replace every `[BRACKETED]` or placeholder value with your
> actual situation before placing this file at
> `~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`.
> Activate this context by running: `export WALTER_CONTEXT=hackathons`.

# AGENTS.md — Hackathons Context [Team Lead]

## Event overview

- **Event**: [Hackathon name] — [duration: 24h / 48h / 72h]
- **Track**: [AI / Web3 / Healthcare / Open / other]
- **Judging criteria**: [list top 3]
- **Submission deadline**: [date and time, timezone]
- **Demo format**: [3-minute live demo / recorded video]

## Team

- **Size**: [N people]
- **Roles**:
  - Backend: `<team-member-handle>`
  - Frontend: `<team-member-handle>`
  - ML / API integration: `<team-member-handle>`
  - Design / pitch: `<team-member-handle>` (if applicable)
- **Communication**: [Discord / Slack / WhatsApp / in-person only]
- **Shared repo**: `<your-org>/<project-name>` (GitHub, private during event)

## Project

- **Name**: `<project-name>`
- **Pitch**: [one sentence]
- **Stack**: [e.g., FastAPI + React + PostgreSQL + GPT-4o]
- **Key differentiator**: [what makes this unique for the judges]

## Team coordination rules

- **Standup cadence**: every 4 hours (brief — what's done, what's next, blockers).
- **Integration points**: backend and frontend sync at hours 8, 16, 24.
- **Branch strategy**: each member owns a `feat/<name>/<feature>` branch.
  No force-push to `main`. Merge when feature works end-to-end.
- **Conflict resolution**: team lead decides if two approaches conflict.
  No bikeshedding — time is the enemy.

## Mode: ship fast

Standard rigor rules are relaxed for the event. Minimums that hold:

- No hardcoded API keys. `.env` file, not committed.
- CI must pass before merging to `main` (but keep CI fast — no E2E).
- The demo path must work from a clean checkout.
- Every team member must be able to explain their piece of the codebase
  for judge Q&A.

## Pitch and demo prep

- Demo script drafted by hour 36. Dry run at hour 44.
- Slide deck: 5 slides max (problem / solution / demo / traction / ask).
- Designate one speaker and one backup. Rehearse the opening 30 seconds.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for a **hackathon** context. I'm the team lead.
> My specifics:
>
> - Hackathon name: [name]
> - Duration: [24h / 48h / 72h]
> - Track / theme: [theme]
> - Team size: [N people]
> - Team roles: [list roles and skill levels]
> - Communication channel during event: [Discord / Slack / WhatsApp / in-person]
> - Shared repo location: [GitHub org or username]
> - Judging criteria: [list top 3]
> - My personal strongest skill: [backend / frontend / ML / design / pitching]
> - Our team's biggest coordination risk: [integration / time / communication / other]
>
> Based on the generic Walter-OS hackathon context template, generate a
> customized `AGENTS.md` for me. Output only the Markdown content of the
> `AGENTS.md` file, ready to drop into
> `~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`.
