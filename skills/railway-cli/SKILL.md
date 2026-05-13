---
name: railway-cli
description: Deploy, manage, and operate Railway projects via the official `railway` CLI. Use this skill whenever the user asks to "deploy to Railway", "list Railway services", "set Railway env var", "scale a Railway service", or any operation against Railway. Replaces the dropped community railway-mcp. SPENDS MONEY — confirmation required before any state-changing action.
---

# Railway CLI (`railway`)

Railway provides an excellent **official CLI** (Rust binary) that exposes
the full platform: services, databases, env vars, logs, deploys, scaling.
Replaces the dropped community railway-mcp.

## Setup (one-time, per machine)

```bash
brew install railway          # macOS (already in setup/Brewfile if added)
# or: npm i -g @railway/cli

railway login                 # opens browser
# OR for CI / non-interactive:
export RAILWAY_TOKEN="<token-from-railway.app/account/tokens>"

# Link a repo to a Railway project
cd ~/Projects-Personal/<project>
railway link
# ↳ pick project + environment
```

`RAILWAY_TOKEN` lives in Infisical workspace `walter-os` for ad-hoc CLI
use, or per-project workspace for service-bound deployments.

## Common operations

### Projects + services

```bash
railway list                       # all projects in your account
railway status                     # current project + service + environment
railway service                    # interactive service picker
railway environment staging        # switch environment
```

### Deploy

```bash
# Deploy current dir to linked service
railway up

# Deploy a specific Dockerfile / nixpacks build
railway up --detach

# Tail logs of latest deploy
railway logs
railway logs --filter <service>
```

### Env vars

```bash
railway variables                       # list current env's vars
railway variables --set KEY=value       # add/update
railway variables --delete KEY
railway run -- pnpm dev                 # run a local command with Railway env injected
```

### Database management

```bash
railway connect postgres           # opens psql connected to the linked DB
railway connect redis              # redis-cli connected
```

### Scaling / restart

```bash
railway redeploy                   # rebuild + redeploy current service
railway down                       # stop the service (keeps it deployable)
```

## Project conventions for this operator

Railway is the alternative to Vercel for **stateful** services
(Postgres, Redis, queues, long-running workers). Use it when:

- The service can't run on Vercel's serverless model.
- A self-hosted Postgres on Walter-VM is overkill or wrong (e.g.,
  customer-facing app needing managed backups + connection pooling).
- You want isolated env per branch (Railway ephemeral environments).

For cost reasons, prefer:
1. Walter-VM (€0 marginal cost) — for personal infra
2. Vercel Hobby (free) — for static + light serverless
3. Railway — for stateful services that need managed ops
4. Hetzner Cloud (via hcloud CLI) — for full VMs

## Hard rules

- **NEVER deploy to production without operator confirmation.** Even
  if CI is green. Stage on a preview environment first.
- **Cost guardrails**: Railway charges by usage (CPU/RAM/network). Any
  scaling action prints expected cost delta before applying.
- **Never delete a service or environment from CLI.** Deletion is
  interactive in the Railway dashboard.
- **Token scope**: prefer per-project tokens to global account tokens.
- **Branch flow**: same as elsewhere — `feature/*` → preview env →
  `main` → prod. No skip levels.

## Troubleshooting

### "Project not linked"
```bash
ls .railway/   # missing? then:
railway link
```

### "Invalid token"
```bash
railway logout
railway login
```

### Deploy slow / failing
```bash
railway logs --tail 200
# Common: Node version mismatch → set in railway.json or package.json engines
```

## Why CLI instead of MCP

- Official, maintained by Railway directly.
- 146 tools claimed by the community MCP map 1:1 to the CLI surface.
- Token rotation simpler (one place: env var or `~/.railway/`).
- Same interface as in CI (predictability).

## What this skill does NOT cover

- Railway team / billing management (web dashboard only).
- One-click templates (web UI only).
- Webhook configuration (web UI; can be scripted via API).

## References

- https://docs.railway.app/develop/cli
- https://railway.app/cli
