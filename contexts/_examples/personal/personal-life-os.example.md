> **EXAMPLE FILE — Personal Life OS Operator**
> This file shows how someone using Walter-OS primarily for personal life
> management (finance, health, journaling, learning) might configure their
> personal context overlay. All names and specifics are fictional. Replace
> every `[BRACKETED]` or placeholder value with your actual situation before
> placing this file at `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`.

# AGENTS.md — Personal Context [Life OS Operator]

## Life areas managed

- **Finance**: personal budget tracking, investment portfolio, annual tax prep.
  Jurisdiction: [your country / state]. No automated transactions — calculations only.
- **Health**: appointment calendar, medication tracking (no PHI to cloud).
  All health data stays local-only; Ollama for any AI analysis of health content.
- **Journaling**: daily notes in Obsidian, weekly reviews, annual retrospectives.
- **Learning**: book notes, course summaries, spaced-repetition cards (Anki).
- **Household**: grocery lists, maintenance schedule, shared calendar with family.

## Toolchain

- **Notes**: Obsidian vault at `~/Obsidian/personal-vault`
  (synced via self-hosted Forgejo, not iCloud or Obsidian Sync).
- **Tasks**: [Todoist / Things 3 / OmniFocus / system reminders — pick one].
- **Calendar**: [Google Calendar / Apple Calendar / Proton Calendar].
- **Finance**: local spreadsheet (Numbers / LibreOffice Calc) — no cloud spreadsheet.
- **Health**: Apple Health (local) + local Obsidian notes — no cloud export.

## Finance rules

- Agent may: run calculations, draft budget templates, summarize expenses.
- Agent must NOT: execute transfers, place trades, or make any banking API calls.
- Tax jurisdiction: [your country/state]. Key dates: [list your annual deadlines].
- Investment tracking: read-only. The agent shows portfolio state; the operator executes.

## Health and PHI rules

- **Strict**: no health data leaves this device. Local LLM only.
- Medication reminders: draft only, operator sets them in the phone manually.
- Appointment summaries: stored in Obsidian only, never in cloud notes.

## Privacy

- No external API calls for personal content without case-by-case confirmation.
- Journal entries: summarized locally only. Ollama for any AI processing.
- Shopping lists and grocery items: may use cloud search (not sensitive).

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **personal** context. I use it for life
> management: finance, health, journaling, and household tasks. My specifics:
>
> - Primary language for personal notes: [English / Spanish / French / other]
> - Finance jurisdiction: [country / state for tax purposes]
> - Note-taking tool: [Obsidian / Notion / Apple Notes / Roam / Bear / other]
> - Task manager: [Todoist / Things / OmniFocus / Reminders / Plane / other]
> - Calendar: [Google / Apple / Proton / Fastmail]
> - Do I track health data? [yes — what kind / no]
> - Health data privacy level: [local-only / OK with cloud / unsure]
> - Do I track finances? [yes — how (spreadsheet/app) / no]
> - Family members sharing calendar or household tasks: [yes/no]
> - Other life areas to manage: [travel / language learning / cooking / other]
>
> Based on the generic Walter-OS personal context template, generate a
> customized `AGENTS.md` for me. Output only the Markdown content of the
> `AGENTS.md` file, ready to drop into
> `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`.
