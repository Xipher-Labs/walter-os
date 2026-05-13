# Personal Life Context — Overlay Configuration Prompt

Paste this prompt into any LLM (Claude, GPT-4, Gemini) to get tailored
recommendations for your
`~/.config/walter-os/overlay/contexts/personal/AGENTS.md`.

---

I am configuring the personal context for Walter-OS, an AI agent framework.
The personal context AGENTS.md controls how an AI assistant behaves when I
am working on personal life tasks: finance, health, journaling, notes,
household management, and learning. I need you to recommend what to write
in my overlay file based on my answers below.

1. Which personal life areas do you actively manage with an AI assistant?
   (Check all that apply)
   - Personal finance (budgeting, investments, taxes)
   - Health (appointments, medical notes, fitness tracking)
   - Journaling and personal reflection
   - Learning (books, courses, papers)
   - Household (shopping lists, recipes, tasks)
   - Other: ___

2. What is your locale and jurisdiction?
   - Country:
   - State/province (if relevant for tax):
   - Primary language for personal content:

3. What tools do you use for personal content management?
   - Notes: (Obsidian, Notion, Bear, Apple Notes, other)
   - Tasks: (Plane, Things, Todoist, Apple Reminders, other)
   - Calendar: (Google Calendar, Apple Calendar, other)
   - Finance tracking: (Google Sheets, YNAB, local spreadsheet, other)

4. How strict do you want PHI (health data) handling?
   - Never send any health data to external APIs (local LLM only)
   - Allow anonymized health queries to external APIs
   - No preference (use Walter-OS defaults)

5. What tax and regulatory research do you need?
   - Jurisdiction for tax research:
   - Specific tax types you track (income, VAT, capital gains, other):
   - Any other legal domains: (property, contracts, privacy law, other)

6. What language do you prefer for personal content?
   (This may differ from your technical work language)

7. Are there categories of personal content you want the agent to avoid
   entirely? (e.g., never read health directory, never access financial files)

---

## Constraints for your recommendations

- The overlay file must be in English (agent instructions must be in English
  even if your personal content is in another language).
- Do not include financial account numbers, medical record IDs, or personal
  identification in the overlay.
- The overlay path is:
  `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`
- The overlay takes precedence over the repo's generic template when present.
- PHI hard limits cannot be relaxed by the overlay — they are global.
- Write recommendations as direct instructions to the agent.

Format your output as a complete `AGENTS.md` file ready to paste into the
overlay path.
