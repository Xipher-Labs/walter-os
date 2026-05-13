# Projects-Personal Context — Overlay Configuration Prompt

Paste this prompt into any LLM (Claude, GPT-4, Gemini) to get tailored
recommendations for your
`~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`.

---

I am configuring the projects-personal context for Walter-OS, an AI agent
framework. The projects-personal context AGENTS.md controls how an AI coding
agent behaves when I am working on my own software projects (side projects,
open-source work, apps I am building for myself or others). I need you to
recommend what to write in my overlay file based on my answers below.

1. What are your active personal software projects?
   For each project, describe:
   - Project name and one-sentence description
   - Current stage: idea / MVP / launched / mature
   - Primary tech stack
   - Monetization intent (none / planned / active)

2. What is your primary tech stack for personal projects?
   - Frontend: (React, Vue, Svelte, Astro, other)
   - Backend/runtime: (Node.js, Python, Rust, Go, other)
   - Database: (Supabase, Postgres, SQLite, other)
   - Deploy target: (Vercel, Fly.io, Railway, self-hosted, other)
   - Auth: (Supabase Auth, Clerk, custom, none)

3. Do any of your projects touch regulated domains?
   - GDPR / data protection (user data from EU residents)
   - HIPAA (US health data)
   - PCI-DSS (payment card data)
   - Other financial regulation
   - None

4. What is your issue tracker for personal projects?
   (GitHub Issues / Linear / Plane / none / other)

5. What is your preferred autonomy level for the agent on personal projects?
   - Can it open PRs automatically after review convergence?
   - Can it run database migrations on dev without asking?
   - Can it generate brand assets (logos, images) without asking?

6. What Walter-OS skills do you want to auto-trigger in this context?
   Common options: hackathon-spinup, brand-creation, landing-page-fast,
   nanobanana, regulatory-research-international, medical-data-compliance.

7. Are there any hard limits you want to add beyond Walter-OS defaults?
   (e.g., never spend on cloud resources, always use a specific deploy target)

---

## Constraints for your recommendations

- The overlay file must be in English.
- Do not include passwords, API keys, or secrets in the overlay file.
- Keep the overlay focused on agent behavior rules and project context.
- The overlay path is:
  `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`
- The overlay takes precedence over the repo's generic template when present.
- Write recommendations as direct instructions to the agent.

Format your output as a complete `AGENTS.md` file ready to paste into the
overlay path.
