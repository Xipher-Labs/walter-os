# Hackathons Context — Overlay Configuration Prompt

Paste this prompt into any LLM (Claude, GPT-4, Gemini) to get tailored
recommendations for your
`~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`.

---

I am configuring the hackathons context for Walter-OS, an AI agent framework.
The hackathons context AGENTS.md controls how an AI coding agent behaves
during time-boxed competitive events (hackathons, buildathons, demo days).
I need you to recommend what to write in my overlay file and what to do
first when a hackathon starts, based on my answers below.

1. What hackathon event are you preparing for (or participating in now)?
   - Event name:
   - Organizer (ETHGlobal, Devpost, HackMIT, other):
   - Duration (24h / 36h / 48h / 72h / other):
   - Dates:

2. What track or theme are you targeting?
   - Track name:
   - Judging criteria (copy from the event website if available):

3. What sponsor APIs and SDKs are available at this event?
   List the ones you are most interested in using:
   1.
   2.
   3.

4. What is your team composition?
   - Team size: (solo / 2 / 3 / 4 / 5)
   - Your role: (full-stack / backend / frontend / design / PM)
   - Team members' primary skills:

5. Are there any tech stack constraints for this hackathon?
   (e.g., must use Ethereum, must be a mobile app, must use a specific sponsor API)

6. What is your go-to hackathon stack when there are no constraints?
   - Frontend:
   - Backend:
   - Database:
   - Deploy:

7. What Walter-OS skills do you want active during the hackathon?
   Auto-active by default: hackathon-spinup, brainstorming, writing-plans,
   verification-before-completion.
   Optional: brand-creation, landing-page-fast, nanobanana, web-security-baseline.

---

## Recommended first steps for this hackathon

Based on your answers, recommend:

1. Which 2–3 sponsor APIs to integrate and why.
2. What the core demo loop should look like (one sentence: "A user does X, the
   system does Y, the judge sees Z").
3. What to build in hours 0–6 to lock the ideation.
4. Which Walter-OS skills to activate for this specific event.
5. Any track-specific gotchas to watch out for.

---

## Constraints for your recommendations

- The overlay file must be in English.
- Do not include team members' personal data in the overlay.
- The overlay path is:
  `~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`
- Keep the overlay focused on event-specific agent behavior rules.
- After the hackathon, remove or archive the event-specific overlay and
  revert WALTER_CONTEXT to the appropriate regular context.

Format your output as:
1. A complete `AGENTS.md` overlay file ready to paste.
2. A brief action plan for hours 0–6 based on the event details.
