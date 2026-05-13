> **TEMPLATE** — Copy this file to
> `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`
> and fill in your active personal projects. The overlay takes precedence over the
> repo's generic `contexts/projects-personal/AGENTS.md` when present.
> See `setup/personal-overlay-init.sh` to scaffold the overlay directory.

# AGENTS.md — Projects-Personal Context (dev) [TEMPLATE]

Loaded automatically when cwd matches your personal projects directory pattern.

For personal non-dev life (finance, health, journaling), see
`contexts/personal/AGENTS.md`. This context is for **personal software projects**.

## Mode

This is your sandbox. Higher autonomy than work context:

- Auto-PR is **enabled** after Codex review + 2-5 review iterations converge.
- Faster iteration, more experimentation. Wrong-but-fast is acceptable on
  branches that aren't `staging` or `main`.

Hard limits stay the same: branch flow, security gates, never auto-merge.

## Active projects

<!-- List your active personal software projects here -->

### [Project A] — [Brief description]

Stack: [framework + backend + hosting]

Key context for the agent:
- Domain: [what problem it solves]
- Regulatory framework: [if applicable — use `regulatory-research-international`
  skill with WALTER_JURISDICTION and WALTER_REGULATORY_DOMAIN parameters]
- Target users: [who uses it]
- Differentiator: [what makes it different]

When implementing: [any project-specific rules for the agent]

### [Project B] — [Brief description]

Stack: [framework]

<!-- Add more projects as needed -->

### Hackathons — full-spectrum spinup

When working on a hackathon project, the `hackathon-spinup` meta-skill
orchestrates: brand → landing → MVP architecture → demo script. Optimize for
shipping, not perfection. Cut features, never tests.

## Issue tracker integration

<!-- Your project tracker of choice -->
[Plane / Linear / GitHub Issues] loaded for this context. Issue/spec/plan flow:

1. Spec lives in repo at `docs/specs/<slug>.md` (versioned).
2. Issue links to spec via permalink.
3. Plan goes both as a comment on the issue **and** as
   `docs/specs/<slug>.plan.md` (committed).
4. PR description includes `Closes <PROJ-NNN>` for auto-close on merge.

## Toolchain shortcuts

<!-- Adjust to your actual preferences -->
- **Landing pages**: Astro for static, Next.js App Router for dynamic. Tailwind
  always. Shadcn/ui as starting point.
- **Database**: Supabase for managed Postgres + auth + realtime + storage.
  Drizzle ORM in TypeScript projects.
- **Deploy**: Vercel for frontend, Fly.io or Railway for stateful services.
- **Analytics**: Plausible (self-hosted). No GA.
- **Email**: Resend.
- **Auth**: [Supabase Auth / Clerk / Auth.js]

## Regulatory compliance

For features touching regulated domains, use `regulatory-research-international`
with the appropriate jurisdiction and domain parameters:

```
WALTER_JURISDICTION=<your-country-or-region>
WALTER_REGULATORY_DOMAIN=<procurement|data-protection|financial|health>
```

Frameworks reference: GDPR (EU), HIPAA (US healthcare), PCI-DSS (payment cards),
SOC 2 (cloud services), ISO 27001 (information security).

## What the agent can do autonomously here

- Open PRs (after the review iteration loop converges).
- Create branches.
- Run migrations on `dev`. Migrations on `staging` need confirmation.
- Generate brand assets (logos, hero images, social).
- Update `docs/` as part of code changes.
- Refactor freely on `feature/*` branches.

## What the agent must NOT do here

- Publish (tweet, blog) without confirmation.
- Spend more than $5 USD on a single LLM API call without confirmation.
- Add a paid third-party service without confirmation.
- Fork or clone repos under other people's accounts without permission.

## Skill loading (this context)

Auto-loaded in addition to the global skills:
- `hackathon-spinup`
- `brand-creation`
- `regulatory-research-international`
- `medical-data-compliance` (if any project touches health data)
- `landing-page-fast`
- `frontend-quality`
- `data-migration-safety`
- `web-security-baseline`
