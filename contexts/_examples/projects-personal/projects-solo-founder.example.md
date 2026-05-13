> **EXAMPLE FILE — Solo Founder / Indie Hacker**
> This file shows how a solo founder or indie hacker building their own product
> might configure their projects-personal context overlay. All org and project
> names are fictional. Replace every `[BRACKETED]` or placeholder value with
> your actual situation before placing this file at
> `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`.

# AGENTS.md — Projects-Personal Context [Solo Founder / Indie Hacker]

## Active projects

- **widget-app** — B2B SaaS tool for [target user]. Stack: Next.js + Supabase.
  Stage: private beta, 15 paying customers. Deploy: Vercel + Supabase.
- **side-tool** — CLI utility for developers. Stack: Go. Stage: public, ~200 stars.
  Deploy: GitHub Releases.

## Stack

- **Frontend**: Next.js App Router + Tailwind + shadcn/ui
- **Backend / DB**: Supabase (Postgres + auth + storage + realtime)
- **Deploy**: Vercel (frontend), Supabase (backend)
- **Payments**: Stripe (via `stripe-node` + webhooks)
- **Analytics**: Plausible (self-hosted)
- **Email**: Resend + React Email
- **Issue tracker**: Linear (workspace: `<your-workspace>`)

## Workflow rules

### PR flow

- Branch: `feature/<slug>` → `dev` → `staging` → `main`
- Auto-PR enabled after 1 review round.
- Dev migrations: agent may run without confirmation.
- Staging migrations: operator confirms.

### Revenue and payments

- Any change to Stripe integration, webhook handlers, or subscription logic
  auto-invokes the security-auditor subagent.
- Test Stripe flows with test-mode keys only. Never use live keys in dev.
- Always test webhook handling with `stripe listen --forward-to` locally.

### Regulatory

- GDPR applies (EU customers). Privacy policy linked from app footer.
- No PII stored beyond what the user explicitly provides.
- Right-to-erasure: Supabase RLS + a `delete_user_data()` function.

## Hard limits

- Never push directly to `main`. Always via PR.
- Never commit live Stripe API keys.
- Never merge a billing change without a Stripe test-mode run captured in the PR.
- Never auto-send user emails without testing the template in Resend preview.
- Never spend more than $20/month on SaaS tools without justifying ROI.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **projects-personal** context. I'm a solo
> founder / indie hacker building **[YOUR PRODUCT NAME]**. My specifics:
>
> - Product type: [B2B SaaS / B2C app / developer tool / marketplace / other]
> - Stage: [idea / building / private beta / launched / scaling]
> - Customer count: [0 / N paying / N free users]
> - Main stack: [Next.js+Supabase / Rails / Django / Go / Rust / other]
> - Deploy target: [Vercel / Fly.io / Railway / Hetzner / AWS / other]
> - Payments: [Stripe / Paddle / Lemon Squeezy / none]
> - Regulated domains: [GDPR / HIPAA / PCI-DSS / none]
> - Issue tracker: [Linear / Plane / GitHub Issues / Notion / none]
> - Other active projects: [list names and stages]
>
> Based on the generic Walter-OS projects-personal context template, generate
> a customized `AGENTS.md` for me. Output only the Markdown content of the
> `AGENTS.md` file, ready to drop into
> `~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md`.
