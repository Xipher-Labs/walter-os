> **EXAMPLE FILE — Solo Hackathon Participant**
> This file shows how a solo developer competing in a hackathon might configure
> their hackathon context overlay. All project and org names are fictional.
> Replace every `[BRACKETED]` or placeholder value with your actual situation
> before placing this file at
> `~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`.
> Activate this context by running: `export WALTER_CONTEXT=hackathons`.

# AGENTS.md — Hackathons Context [Solo Participant]

## Event overview

- **Event**: [Hackathon name] — [duration: 24h / 48h / 72h / 1 week]
- **Track**: [AI / Web3 / Healthcare / Climate / Open / other]
- **Judging criteria**: [innovation / technical depth / UX / impact / demo quality]
- **Submission deadline**: [date and time, timezone]
- **Demo format**: [3-minute video / live demo / slide deck]

## Project

- **Name**: `<your-org>/<project-name>`
- **Pitch**: [one sentence — what it does and who it helps]
- **Stack**: [e.g., Next.js + Supabase + OpenAI API]
- **Key differentiator**: [what makes this entry stand out for this track]

## Mode: ship fast

During a hackathon, the standard rigor rules are relaxed:

- **Tests**: write at least one integration test per major feature, but skip
  unit tests for scaffolding code. E2E is optional.
- **Commits**: atomic per feature, no squash required. Message quality matters
  less than shipping.
- **PRs**: no formal PR process — commit directly to `main` with `--no-verify`
  if hooks are blocking progress.
- **Documentation**: write the README last (30 minutes before submission).

What CANNOT be skipped:

- No hardcoded API keys — use `.env` even in hackathons.
- No committing secrets to the repo (public or private).
- The demo must work from a clean clone on the judge's machine.

## Timeline template (48h)

| Hour | Goal |
|------|------|
| 0–2  | Idea validation, stack choice, repo setup |
| 2–8  | Core feature: working end-to-end (ugly OK) |
| 8–16 | Polish core, add 2nd feature |
| 16–24 | Integrate AI/API, fix critical bugs |
| 24–36 | UX pass, README, demo script |
| 36–44 | Buffer for integration issues + submission prep |
| 44–48 | Record demo video, submit |

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for a **hackathon** context. I'm competing solo.
> My specifics:
>
> - Hackathon name: [name]
> - Duration: [24h / 48h / 72h / 1 week]
> - Track / theme: [AI / Web3 / Healthcare / Climate / Open innovation / other]
> - Judging criteria: [list the top 3]
> - My stack for this event: [languages, frameworks, APIs, AI models]
> - My strongest skill: [backend / frontend / ML / design / pitching]
> - My biggest risk: [shipping on time / demo quality / integration complexity]
> - Prior hackathon experience: [first time / N hackathons]
>
> Based on the generic Walter-OS hackathon context template, generate a
> customized `AGENTS.md` for me. Output only the Markdown content of the
> `AGENTS.md` file, ready to drop into
> `~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`.
