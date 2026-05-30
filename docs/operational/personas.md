# Personas — who Walter-OS is for (in detail)

The [README](../../README.md) names the three primary personas in three
sentences each. This document is the detailed version with the matching
**"this is NOT for you if"** lists — read carefully, the negative cases
are as important as the positive ones.

Walter-OS is built for three primary personas plus a fourth time-boxed
use case (hackathons).

## Builder — solo engineer, shipping product fast

**This is for you if:**

- You write code most of the day and context-switch between multiple tools
  (Claude Code, Codex CLI, Cursor, Antigravity, terminal).
- You want your AI agents to follow the same disciplines everywhere — same
  branch flow, same commit format, same rigor levels — without configuring
  each tool separately.
- You self-host at least some services (Postgres, Forgejo, Plane) and want
  them wired into your agent's MCP catalog automatically.

**This is NOT for you if:**

- You want a no-configuration experience. Every service requires first-run
  setup; the personal overlay is mandatory.
- You need enterprise features: SSO beyond Google IdP, RBAC, audit trails
  for compliance. Walter-OS has none of that.
- You are not comfortable with Docker, DNS configuration, and Linux sysadmin
  basics.

Pick **Mode 1 (Lite)** or **Mode 2 (client install)** in the README. Relevant
context template: [`contexts/projects-personal/`](../../contexts/projects-personal/AGENTS.md).

## Founder — pre-PMF, needs GTM tooling without a DevOps hire

**This is for you if:**

- You want a self-hosted PostHog, Postiz, n8n, and Metabase stack without
  paying $300+/mo for SaaS equivalents.
- You want AI agents that can help you with content publishing, analytics
  workflows, and competitive research — all routed through your own LiteLLM
  gateway with cost visibility.
- You are comfortable spending a one-time 4–8 hour setup window to get a
  permanent GTM stack that you own.

**This is NOT for you if:**

- You need uptime SLAs. This is a single-VM setup; if the VM goes down, your
  services go down.
- You are looking for a managed SaaS replacement with customer support.
- Your team has more than 2–3 people. Walter-OS is designed for solo or
  micro-team use; multi-user access requires manual Plane/Forgejo user
  management.

Pick **Mode 2 (client install)** + the founder-skills bundle, OR **Mode 3
(self-hosted stack)** if you want the GTM-stack benefits. Relevant context
templates: [`contexts/projects-personal/`](../../contexts/projects-personal/AGENTS.md),
[`contexts/work/`](../../contexts/work/AGENTS.md).

## Operator — homelab enthusiast, life-OS

**This is for you if:**

- You want Syncthing, Headscale, Synapse/Element, and Grafana in one
  composable stack.
- You think of your VM as an "always-on personal brain" — project management
  (Plane), git hosting (Forgejo), secrets vault (Infisical), and AI gateway
  (LiteLLM) all in one place.
- You want your AI tools to respect privacy: secrets stay on your VM,
  medical/PHI data stays on a local LLM, and you control routing decisions.

**This is NOT for you if:**

- You want a NAS-first setup. Walter-OS has SeaweedFS as an optional service
  but is not a primary NAS solution.
- You want automatic zero-downtime updates. Updates are manual (`git pull` +
  `./install.sh --upgrade` + `docker compose up -d`).
- You need mobile-first management. There is no Walter-OS mobile app; the
  Control Tower browser UI is the management surface.

Pick **Mode 3 (self-hosted stack)** in the README. Relevant context:
[`contexts/personal/`](../../contexts/personal/AGENTS.md).

## Hackathon participant — brief mention

Walter-OS ships a [`contexts/hackathons/`](../../contexts/hackathons/AGENTS.md)
context with a PROMPT.md template optimized for 48-hour sprint mode (brand
→ landing → MVP → demo). The
[`hackathon-spinup`](../../skills/hackathon-spinup/SKILL.md) skill
orchestrates the full sequence. Hackathon use does not require the full VM
stack — you can run Walter-OS purely as the agent contract layer on your
laptop. Activate the context with `WALTER_CONTEXT=hackathons` in your shell
before invoking your agent.
