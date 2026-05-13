# AGENTS.md — Work Context [GENERIC TEMPLATE]

<!-- -----------------------------------------------------------------------
  PERSONALIZATION: This file is a generic starting point.
  Copy to: ~/.config/walter-os/overlay/contexts/work/AGENTS.md
  and fill in your company-specific details. The overlay takes precedence
  over this file when present (checked by the global AGENTS.md cascade).

  Run `setup/personal-overlay-init.sh` to scaffold the overlay directory.
  Use `contexts/work/PROMPT.md` to get LLM recommendations for your overlay.
  For real-world examples see: contexts/_examples/work-*.example.md
  ----------------------------------------------------------------------- -->

Loaded automatically when cwd matches the work directory pattern configured
in the global `AGENTS.md` context layers section.

## Mode

Low autonomy. The agent prepares work and asks before acting.

- Agent may create branches, draft PRs, and prepare descriptions. The
  operator opens every PR manually unless the overlay explicitly changes this.
- Operator confirmation required before: pushing to any non-feature branch,
  modifying CI configuration, adding a production dependency, posting anything
  publicly.
- Any change touching auth, key handling, or network-exposed surfaces
  auto-invokes the `security-auditor` subagent.

## Stack

Fill in your tech stack in the personal overlay. Common examples:

- Language/runtime: Rust / Go / TypeScript / Python
- Frontend: React / Vue / Svelte
- Infra: AWS / GCP / Azure / bare-metal / Hetzner
- CI: GitHub Actions / GitLab CI / Buildkite
- Observability: Grafana + Prometheus / Datadog / Honeycomb

Replace this section in your overlay with your actual stack. Do not
leave example values in production — they mislead the agent.

## Workflow rules

### PR flow

- Branch: `feature/<slug>` → `dev` → `staging` → `main`
- Operator creates every PR manually (default). Override in overlay if
  your team trusts auto-PR.

### Issue tracker integration

Configure your issue tracker (Linear / Jira / Plane / GitHub Issues) in
the overlay. Default ticket reference format: `Refs: [PROJ-NNN]`.

Spec flow:
1. Spec lives in repo at `docs/specs/<slug>.md`.
2. Issue links to spec via permalink.
3. Plan committed as `docs/specs/<slug>.plan.md`.
4. PR body includes `Closes <PROJ-NNN>` for auto-close on merge.

### Security posture

- Dependency audit (`npm audit` / `cargo audit` / `pip-audit`) runs on
  every PR.
- Secrets never appear in logs, even at debug level.
- `security-auditor` subagent is mandatory on auth/crypto/PHI changes.

## Hard limits

These apply in the work context and cannot be overridden by the overlay:

- Never push directly to `main` or `staging`.
- Never commit secrets (API keys, tokens, passwords, `.env` files).
- Never auto-merge a PR. The operator clicks merge.
- Never disable a failing test to make CI green. Fix the root cause.
- Never post publicly (Slack, social, email) without operator confirmation.

## Skill auto-trigger

See `contexts/work/SKILLS.md` for the full skill mapping table with
trigger conditions. Key auto-loaded skills in this context:

- `web-security-baseline` — any PR touching network or auth surfaces
- `frontend-quality` — any PR with UI changes
- `data-migration-safety` — any DB migration file present
- `test-driven-development` — all code changes (mandatory)
- `definition-of-done-validator` — before PR creation

## Customization

To override this template with your company-specific config:

1. Run `setup/personal-overlay-init.sh` to scaffold the overlay.
2. Edit `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.
3. The overlay file loads instead of this template when present.
4. Use `contexts/work/PROMPT.md` for LLM-guided recommendations on
   what to add.

What to fill in:
- Company description, product, customer base
- Your actual tech stack (remove the examples above)
- Issue tracker type and ticket format
- PR policy (auto-PR or manual)
- Team-specific security requirements
- Domain-specific skills to auto-load
