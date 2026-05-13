> **TEMPLATE** — Copy this file to `~/.config/walter-os/overlay/contexts/work/AGENTS.md`
> and fill in your company-specific details. The overlay takes precedence over the
> repo's generic `contexts/work/AGENTS.md` when present.
> See `setup/personal-overlay-init.sh` to scaffold the overlay directory.

# AGENTS.md — Work Context [TEMPLATE]

Loaded automatically when cwd matches your work directory pattern
(configure the cwd trigger in the global `AGENTS.md` context layers section).

## Company context

<!-- Replace with your company name and a brief description -->
**[Company Name]** — [What the company does. 1-2 sentences. Key products/services.]

Product surface (relevant to your work):
- **[Product A]** — [brief description]
- **[Product B]** — [brief description]

Customer base: [who buys, what they care about]

## Stack

<!-- List your actual tech stack -->
- **Core services**: [language/runtime]
- **Frontend**: [framework]
- **Infra**: [cloud provider / on-prem / hybrid]
- **CI**: [GitHub Actions / GitLab CI / other]
- **Observability**: [Datadog / Grafana / etc.]
- **Databases**: [Postgres / MySQL / etc.]

## Workflow rules

### PR creation

[Describe your PR flow — who creates PRs, any restrictions, required reviewers]

### Branch flow

Same global dev → staging → main rule, with these specifics:
- `dev`: [how dev is tested]
- `staging`: [staging environment details]
- `main`: [merge requirements, canary process if any]

### Issue tracker integration

[Linear / Jira / Plane / GitHub Issues — how specs link to tickets]
- Ticket format: `Refs: [PROJ-NNN]`
- Plan goes as a comment on the ticket; spec markdown lives in repo.

## Security posture

[Add any company-specific security requirements here]
- Language-specific: [`cargo audit` / `npm audit` / `pip-audit`]
- Auth/crypto changes: auto-invoke `security-auditor` subagent.

## Approvals required

These actions need explicit "yes, proceed" in the chat:
- Pushing to any branch other than the current feature branch.
- Modifying CI configuration.
- Adding a new production dependency.
- Posting anything publicly (blog, social).
- [Add company-specific approval requirements]

## Skill loading (this context)

Auto-loaded in addition to the global skills:
- `web-security-baseline`
- `frontend-quality`
- `data-migration-safety`
- [Add domain-specific skills relevant to your stack]

## Glossary (auto-injected when relevant)

<!-- Add domain-specific terms the agent should know -->
- **[Term]**: [definition]
