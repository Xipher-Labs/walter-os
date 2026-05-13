> **EXAMPLE FILE — Software Engineer at a SaaS Company**
> This file shows how a full-time software engineer at a SaaS product company
> might configure their work context overlay. All org and project names are
> fictional. Replace every `[BRACKETED]` or placeholder value with your actual
> situation before placing this file at
> `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.

# AGENTS.md — Work Context [Software Engineer at SaaS]

## Company context

**saas-company** — B2B SaaS product serving mid-market customers.
Stack: Next.js frontend, Go microservices, PostgreSQL, deployed on AWS EKS.
Customer base: ~500 companies, mostly in the US and EU.

## Stack

- **Language/runtime**: Go (services) + TypeScript / Next.js (frontend)
- **Database**: PostgreSQL 16 (RDS), Redis (ElastiCache)
- **Infra**: AWS EKS, Terraform IaC, S3
- **CI**: GitHub Actions
- **Observability**: Datadog (metrics + APM + logs)
- **Issue tracker**: Linear (workspace: `acme-corp`)
- **Git host**: GitHub (`acme-corp/widget-app` and related repos)

## Workflow rules

### PR flow

- Branch: `feature/<slug>` → `dev` → `staging` → `main`
- Operator creates PRs manually. No auto-PR in work context.
- Every PR requires at least one approval from a human reviewer.
- CI must be green before merge.

### Ticket references

Linear ticket format: `ACME-NNN`
Include in PR title or body: `Closes ACME-NNN`

### Security posture

- Any PR touching `auth/`, `payments/`, or `billing/` triggers
  the security-auditor subagent automatically.
- `npm audit` and `go mod audit` run in CI on every PR.
- Secrets managed via AWS Secrets Manager — never in env files.

### Review discipline

- UI changes: include a screenshot or Loom recording.
- API changes: include an OpenAPI diff or Swagger snippet.
- Database migrations: `data-migration-safety` skill is mandatory.

## Hard limits

Standard global hard limits apply. Additional work-context limits:

- Never push directly to `main` or `staging`. Always via PR.
- Never merge your own PR without a second human approval.
- Never add a SaaS dependency without a Procurement review ticket.
- Never log PII (user email, name, payment info) at any log level.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **work** context. I'm a software engineer at
> **[COMPANY NAME]**, working on **[PRODUCT NAME]**. My specifics:
>
> - Company type: [startup / scale-up / enterprise / agency]
> - Customer: [B2B / B2C / internal tooling]
> - Main language: [Go / TypeScript / Rust / Python / Java / other]
> - Frontend: [Next.js / React / Vue / none]
> - Database: [PostgreSQL / MySQL / MongoDB / other]
> - Cloud: [AWS / GCP / Azure / Hetzner / bare-metal]
> - CI: [GitHub Actions / GitLab CI / Jenkins / Buildkite / other]
> - Issue tracker: [Linear / Jira / Plane / GitHub Issues]
> - Ticket format: [PROJ-NNN or similar]
> - Do I create PRs manually or can the agent auto-create? [manual / auto]
> - Any regulated domains? [GDPR / HIPAA / PCI-DSS / SOC2 / none]
>
> Based on the generic Walter-OS work context template, generate a customized
> `AGENTS.md` for me. Output only the Markdown content of the `AGENTS.md` file,
> ready to drop into `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.
