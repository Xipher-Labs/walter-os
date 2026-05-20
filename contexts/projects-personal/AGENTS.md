# AGENTS.md — Projects-Personal Context [GENERIC TEMPLATE]

<!-- -----------------------------------------------------------------------
  PERSONALIZATION: This file is a generic starting point.
  Copy to: ~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md
  and fill in your active personal projects. The overlay takes precedence
  over this file when present.

  Run `setup/personal-overlay-init.sh` to scaffold the overlay directory.
  Use `contexts/projects-personal/PROMPT.md` for LLM-guided recommendations.
  For real-world examples see: contexts/_examples/projects-personal-*.example.md
  ----------------------------------------------------------------------- -->

Loaded automatically when cwd matches your personal projects directory pattern.

For personal non-dev life (finance, health, journaling), see
`contexts/personal/AGENTS.md`. This context is for **personal software projects**.

## Mode

Medium autonomy. Higher than work context; lower than hackathons.

- Auto-PR is **enabled** after review iterations converge.
- Faster iteration and more experimentation than work. Wrong-but-fast is
  acceptable on branches that are not `staging` or `main`.
- Agent may open PRs (after review convergence), create branches, run dev
  migrations, generate brand assets, update docs, and refactor freely on
  `feature/*` branches.

Hard limits stay the same as the global rules: branch flow, security gates,
never auto-merge.

## Stack

Fill in your active tech stack in the personal overlay. Common examples:

- **Landing pages**: Astro (static) or Next.js App Router (dynamic). Tailwind.
- **Database**: Supabase (managed Postgres + auth + realtime + storage).
- **Deploy**: Vercel for frontend; Fly.io or Railway for stateful services.
- **Analytics**: Plausible (self-hosted preferred). Avoid GA by default.
- **Auth**: Supabase Auth or Clerk.

Replace this section in your overlay with your actual choices. Do not leave
example values — they mislead the agent about your real stack.

## Active projects

Define your active projects in the personal overlay. Example structure:

```
## Active projects

- **[Project A]** — [one-line description, current stage, stack]
- **[Project B]** — [one-line description, current stage, stack]
```

## Workflow rules

### PR flow

- Branch: `feature/<slug>` → `main` (single-tier per ADR 0013).
- Auto-PR enabled after review convergence (at least 1 review round).
- Local dev migrations: agent may run without confirmation.
- Production / staging-environment migrations: require operator
  confirmation regardless of branch name.

### Issue tracker integration

Configure your issue tracker in the overlay. Default flow:

1. Spec lives in repo at `docs/specs/<slug>.md` (versioned).
2. Issue links to spec via permalink.
3. Plan committed as `docs/specs/<slug>.plan.md`.
4. PR body includes `Closes <PROJ-NNN>` for auto-close on merge.

### Regulatory compliance

For features in regulated domains, use `regulatory-research-international`:

```
WALTER_JURISDICTION=<your-jurisdiction>
WALTER_REGULATORY_DOMAIN=<procurement|data-protection|financial|health>
```

Frameworks covered: GDPR (EU), HIPAA (US healthcare), PCI-DSS (payment
cards), SOC 2 (cloud services), ISO 27001 (information security).

## Hard limits

These apply even in personal projects and cannot be overridden by overlay:

- Never push directly to `main` or `staging`. Always via PR.
- Never commit secrets (API keys, tokens, passwords).
- Never auto-merge a PR. The operator clicks merge.
- Never publish (tweet, blog, post) without operator confirmation.
- Never spend more than $5 USD on a single LLM API call without confirmation.
- Never add a paid third-party service without operator confirmation.
- Never fork or clone repos under other people's accounts without permission.
- If any project touches health data: `medical-data-compliance` skill is
  mandatory; local LLM only for PHI analysis.

## Skill auto-trigger

See `contexts/projects-personal/SKILLS.md` for the full skill mapping table.
Key skills in this context:

- `web-security-baseline` — any PR touching network or auth surfaces
- `frontend-quality` — any PR with UI changes
- `data-migration-safety` — any DB migration file present
- `test-driven-development` — major code changes (mandatory)
- `hackathon-spinup` — WALTER_CONTEXT=hackathons or hackathon project detected
- `brand-creation` — new project setup
- `regulatory-research-international` — project touches GDPR/HIPAA/PCI domains
- `medical-data-compliance` — health-related data detected (auto-escalation)
- `definition-of-done-validator` — before PR creation

## Customization

To override this template with your project-specific config:

1. Run `setup/personal-overlay-init.sh` to scaffold the overlay.
2. Edit `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`.
3. The overlay file loads instead of this template when present.
4. Use `contexts/projects-personal/PROMPT.md` for LLM-guided recommendations.

What to fill in:
- Your active projects (names, stages, stacks)
- Your preferred toolchain choices (replace examples above)
- Issue tracker type and ticket format
- Regulatory domains that apply to your projects
- Domain-specific skills to auto-load
