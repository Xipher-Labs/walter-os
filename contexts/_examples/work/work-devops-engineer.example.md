> **EXAMPLE FILE — DevOps / Platform Engineer**
> This file shows how a DevOps or platform engineer might configure their work
> context overlay. All org and project names are fictional. Replace every
> `[BRACKETED]` or placeholder value with your actual situation before placing
> this file at `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.

# AGENTS.md — Work Context [DevOps / Platform Engineer]

## Company context

**widget-inc** — SaaS company with a ~20-engineer engineering org.
The operator owns the platform: Kubernetes clusters, CI/CD pipelines,
secrets management, observability stack, and on-call rotation.

## Stack

- **IaC**: Terraform + Helm (EKS), Ansible (VM config)
- **Containers**: Docker + Kubernetes (EKS or GKE)
- **CI/CD**: GitHub Actions + ArgoCD
- **Secrets**: HashiCorp Vault (or AWS Secrets Manager)
- **Observability**: Prometheus + Grafana + Loki + PagerDuty
- **Cloud**: AWS (primary), GCP (some data workloads)
- **Incident tooling**: PagerDuty + Slack bot + runbook wiki

## Workflow rules

### Change management

- All infra changes go through Terraform plan review before apply.
- Destructive changes (resource deletion, scaling to zero) need two
  human approvals in the PR.
- Maintenance windows: Tuesdays and Thursdays 02:00–04:00 UTC.
- No unplanned deploys to production on Fridays.

### On-call

- On-call rotation: weekly, shared with 2 other engineers.
- P1 SLA: respond within 15 min, resolve or escalate within 1 hour.
- Post-mortem required for any P1 or P2 incident.

### Runbook standards

Every service must have a runbook at `docs/runbooks/<service>.md` covering:
common alerts, restart procedure, rollback steps, escalation path.

## Hard limits

- Never destroy production infrastructure without explicit sign-off in the
  incident Slack channel (`#platform-oncall`) from the on-call lead.
- Never commit Vault root tokens or AWS root credentials anywhere.
- Never auto-apply Terraform plans in production — always review the plan
  output first.
- Never silence a PagerDuty alert without triaging the root cause.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **work** context. I'm a DevOps / Platform
> Engineer at **[COMPANY NAME]**. My specifics:
>
> - Infra scale: [number of clusters / services / environments]
> - IaC tools: [Terraform / Pulumi / CDK / CloudFormation / Ansible / other]
> - Container platform: [Kubernetes (EKS/GKE/AKS) / ECS / bare-metal Docker]
> - Cloud: [AWS / GCP / Azure / Hetzner / hybrid]
> - CI/CD: [GitHub Actions / GitLab CI / Jenkins / ArgoCD / other]
> - Secrets manager: [HashiCorp Vault / AWS Secrets Manager / GCP Secret Manager]
> - Observability: [Prometheus+Grafana / Datadog / New Relic / Honeycomb]
> - Incident tool: [PagerDuty / OpsGenie / VictorOps / Slack-only]
> - On-call rotation: [yes/no, how many engineers]
> - Maintenance window: [day and time]
> - Regulated domains: [SOC2 / PCI-DSS / HIPAA / ISO27001 / none]
>
> Based on the generic Walter-OS work context template, generate a customized
> `AGENTS.md` for me. Output only the Markdown content of the `AGENTS.md` file,
> ready to drop into `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.
