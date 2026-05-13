> **EXAMPLE FILE — Staff Engineer / Tech Lead**
> This file shows how a staff engineer or technical lead might configure their
> work context overlay. All org and project names are fictional. Replace every
> `[BRACKETED]` or placeholder value with your actual situation before placing
> this file at `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.

# AGENTS.md — Work Context [Staff Engineer / Tech Lead]

## Company context

**organization-name** — Series B product company, ~80 engineers across
5 product teams. The operator is a staff engineer spanning the platform and
data teams, responsible for architectural decisions, cross-team reviews, and
the RFC process.

## Stack

- **Platform scope**: Auth service, billing engine, shared API gateway
- **Data scope**: Analytics pipeline (Kafka → Spark → BigQuery), data catalog
- **Languages**: Go (platform), Python (data), TypeScript (frontend)
- **RFC process**: GitHub PRs in `organization-name/rfcs` repo, 2-week comment window
- **Issue tracker**: Jira (project: `PLAT`, `DATA`)
- **Decision records**: `docs/decisions/NNNN-<slug>.md` (ADR format)

## Workflow rules

### RFC and design review

- Architectural decisions ≥ 3 services impacted require an RFC in
  `organization-name/rfcs` before implementation starts.
- Cross-team changes (shared DB schema, API contract changes) require
  sign-off from affected team leads.
- ADRs committed to the relevant service repo's `docs/decisions/`.

### Code review

- Staff engineers own the final approve on PRs that cross team boundaries.
- Security changes: mandatory security-auditor subagent review.
- Performance-critical paths: benchmark results required in PR description.

### Escalation paths

- Tech decisions within a team: team lead decides.
- Cross-team technical conflicts: escalate to staff engineer round-table.
- Architecture trade-off disputes: CTO is the tiebreaker.

## Hard limits

- Never implement an ADR that hasn't gone through the RFC process if it
  affects more than one team's API surface.
- Never approve a cross-team migration without a rollback plan documented
  in the PR body.
- Never silence a failing test to unblock a release. Quarantine and track it.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **work** context. I'm a Staff Engineer /
> Tech Lead at **[COMPANY NAME]**. My specifics:
>
> - Engineering org size: [number of engineers]
> - Number of teams: [N teams, each of size M]
> - My scope: [platform / product / infra / data / cross-cutting]
> - RFC process: [yes, link to template / informal / none]
> - ADR format: [MADR / Y-statements / custom / none]
> - Issue tracker: [Linear / Jira / Plane / GitHub Issues]
> - Ticket format: [PROJ-NNN or similar]
> - Cross-team review gates: [yes / no, describe]
> - Escalation path for tech disputes: [who decides]
> - Any regulated domains: [GDPR / HIPAA / PCI-DSS / SOC2 / none]
>
> Based on the generic Walter-OS work context template, generate a customized
> `AGENTS.md` for me. Output only the Markdown content of the `AGENTS.md` file,
> ready to drop into `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.
