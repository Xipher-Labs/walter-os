---
name: vercel-cli
description: Deploy, manage, and operate Vercel projects via the official `vercel` CLI. Replaces the abandoned community Vercel MCP. Use this skill whenever the user asks to "deploy to Vercel", "list deployments", "rollback", "set env var on Vercel", "promote staging to production", "list domains", "check Vercel logs", or any operation against a Vercel project. Triggers on `vercel.json` files in the repo, on Next.js / Astro / SvelteKit / Nuxt projects when deploy is mentioned, or whenever the agent needs to interact with Vercel.
---

# Vercel CLI

The community Vercel MCP is abandoned (single version, no maintenance). Vercel
maintains an excellent **official CLI** that exposes the entire platform —
deploys, env vars, domains, logs, projects, teams, etc. The agent shells out
to `vercel` directly.

## When the agent should use this skill

- User mentions deploying / promoting / rolling back any Vercel project.
- A `vercel.json` file is present in the repo.
- Project is a known Vercel target ([Company] docs site, [Project A] landing,
  [Project B] frontend, hackathon projects).
- User asks to manage env vars / domains / preview deployments.

## Setup (one-time, per machine)

```bash
# Install via brew (already in setup/Brewfile)
brew install vercel-cli

# OR via npm
pnpm add -g vercel

# Authenticate (one-time per machine)
vercel login
# ↳ opens browser, login with your account (your Vercel email)

# Link the current directory to a Vercel project
cd ~/Projects-Personal/[project-a]-web
vercel link
# ↳ asks: existing project or new? scope?

# OR set token for non-interactive use:
export VERCEL_TOKEN="<token-from-vercel.com/account/tokens>"
```

`VERCEL_TOKEN` is checked into `~/.config/walter-os/secrets.env`. For
ad-hoc CLI use you don't need it (auth via `vercel login`); for scripts
and CI, the token is required.

## Common operations

### Deploy

```bash
# Preview deploy (default — branch != main)
vercel
# ↳ uploads, builds, returns preview URL

# Production deploy
vercel --prod

# Deploy a specific commit / non-current dir
vercel --prod --cwd ./apps/web

# Skip build cache (force rebuild)
vercel --force --prod

# Pre-built deploy (CI scenario — build artifacts already produced)
vercel build --prod
vercel deploy --prebuilt --prod
```

### Rollback / promote

```bash
# List recent deployments to pick one
vercel ls [project-a]-web --token=$VERCEL_TOKEN | head -10

# Promote a specific deployment to production
vercel promote <deployment-url-or-id> --prod

# Or roll back to the previous prod deployment
vercel rollback   # interactive
```

### Env vars (per environment)

```bash
# List
vercel env ls

# Add (asks for value via stdin)
vercel env add ANTHROPIC_API_KEY production
# ↳ pastes value when prompted

# Add from file (idempotent-ish bulk import)
while IFS='=' read -r k v; do
  echo "$v" | vercel env add "$k" production --force
done < .env.production

# Remove
vercel env rm ANTHROPIC_API_KEY production

# Pull all envs to .env.local for local dev
vercel env pull .env.local
```

### Domains

```bash
# List domains attached to a project
vercel domains ls

# Add a custom domain
vercel domains add [project-a].com.ar [project-a]-web

# Inspect DNS configuration needed
vercel domains inspect [project-a].com.ar
```

### Logs

```bash
# Tail recent function logs (server-side)
vercel logs [project-a]-web

# Specific deployment
vercel logs <deployment-url>

# Filtered
vercel logs --since 1h --output raw
```

### Inspect builds

```bash
vercel inspect <deployment-url>
# ↳ build size, regions, env vars used, etc.
```

## Project conventions for this operator

### [Company] DevRel docs site

- Project: usually `[company]-docs`
- Domain: `docs.[company].one` (or wherever they ship)
- Env: NONE in Vercel (static site, no secrets needed)
- Deploy: Vercel auto-deploys from GitHub on push to `main`
- Manual override: `vercel --prod` from local

### [Project A] (web + landing)

- Project: `[project-a]-web`
- Domains: `licit.ar` (already in CF), staging at `[project-a]-web-staging.vercel.app`
- Env required (per env):
  - `DATABASE_URL` (Supabase pooler)
  - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`
  - `RESEND_API_KEY`
  - `NEXT_PUBLIC_SITE_URL`
  - `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- Branch flow: `feature/*` → preview → `dev` → preview → `staging` → `main`
- `main` push → Vercel auto-deploys to production. CI gate ensures tests
  pass first.

### [Project B] frontend

- Project: `[project-b]-web`
- Domain: `[project-b].health` (already in CF)
- Env: minimal — most secrets stay on backend (PHI rules)
- Frontend only knows public URLs + Sentry public DSN.

### Hackathon projects

- Project name: `<event-slug>-<idea>`
- Domain: temporary `.vercel.app`, custom only if reaches finals
- Don't set up complex env, hardcode for demo.

## Hard rules

- **NEVER deploy to production without operator confirmation.** Even if
  CI is green, even if "it's just a typo". The agent stages preview,
  shows the URL, asks operator to verify, then promotes.
- **NEVER add a secret to Vercel env without checking it's not in
  `.env.example`** (which would mean someone forgot to gitignore).
- **NEVER use `vercel --prod` from a `feature/*` branch.** Always
  preview-deploy from feature branches; only `main` promotes.
- **For [Project A] / [Project B]**: production deploys require also a
  passing `definition-of-done-validator` skill check before invoking
  `vercel --prod`.

## Troubleshooting

### "Token is invalid / expired"

```bash
vercel logout
vercel login
# Re-link if project linkage broken:
vercel link
```

### "Project not found"

You're in the wrong directory or `.vercel/` linkage is missing. Run:

```bash
ls .vercel/  # should have project.json
# If missing:
vercel link --project [project-a]-web --yes
```

### Build fails on Vercel but works locally

Most common: env var present locally (.env.local) but missing on Vercel.
Check `vercel env ls` against your `.env.example`.

Second most common: Node version mismatch. Set it explicitly:

```json
// package.json
"engines": { "node": "22.x" }
```

Or `vercel.json`:

```json
{ "build": { "env": { "NODE_VERSION": "22" } } }
```

### Deployment is slow / cold start

- Switch heavy routes to `runtime: "edge"` in route handlers.
- Or deploy to multiple regions: `vercel.json` → `regions: ["iad1", "gru1"]`
  (choose regions close to your users).

## Integration with other Walter-OS skills

- `data-migration-safety` — runs DB migration check before deploying
  changes that touch Supabase schemas.
- `frontend-quality` — final review (Lighthouse, a11y, Core Web Vitals)
  on the Vercel preview URL before promoting to prod.
- `web-security-baseline` — verifies security headers in `vercel.json`
  before prod deploy.
- `pr-review` — incorporates the Vercel preview URL screenshot into PR
  description.

## Why CLI instead of MCP

- Official, maintained by Vercel directly.
- Full feature surface (the abandoned MCP only had ~10% of operations).
- Same UX as in CI (predictability).
- Token rotation is simpler (one place: `~/.local/share/com.vercel.cli/`
  + `VERCEL_TOKEN` env var).
- Cross-platform (cli runs anywhere; MCP would need re-config per host).

The MCP could come back if Vercel publishes an official one. Until then:
CLI is correct.

## Hard limits (CLI cannot do)

- Real-time analytics (use Vercel dashboard).
- Cross-project copy of envs (use `vercel env pull` + `vercel env add`).
- Edge config management (separate CLI: `vercel-edge-config-cli`).
- Team / member management (dashboard only as of CLI v34).

## References

- https://vercel.com/docs/cli
- https://vercel.com/docs/cli/deploy
- https://vercel.com/docs/cli/env
