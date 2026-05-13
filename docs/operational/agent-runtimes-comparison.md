# Agent Runtimes Comparison

This document helps Walter-OS operators choose between the supported agent
runtime options. All three options connect to Walter-Bridge (LiteLLM) for
cost attribution and multi-provider routing.

---

## Decision Matrix

| Dimension | Hermes Agent | OpenClaw | Vanilla LiteLLM (as agent) |
|---|---|---|---|
| Out-of-the-box platform integrations | 20+ (Telegram, Discord, Slack, GitHub, Jira, Linear, Notion, Gmail, Calendar, and more) | Telegram (primary); Matrix via Beeper (Phase 2) | None — LiteLLM is a gateway, not an agent; integrations are custom-built |
| Skill-learning / self-improvement loop | Built-in Curator (autonomous background skill management; off by default) | None built-in; relies on Walter-OS skill prompts (static) | None — no agent layer |
| Deployment backends supported | 7 (Docker, bare metal, Kubernetes, Railway, Fly.io, Render, Heroku) | Docker and bare metal | Docker (any docker-capable host) |
| LiteLLM / Walter-Bridge integration | Native — set `OPENAI_BASE_URL=http://litellm:4000` and key; full cost attribution | Native — set `OPENAI_API_BASE` + key; full cost attribution | Native — LiteLLM IS the runtime; no extra integration |
| Web dashboard | Yes (port 9119) — real-time conversation view, skill library browser | Yes (Phase 2 — port 18789 admin UI; not yet available in Phase 1) | Yes — LiteLLM UI at port 4000; shows cost/usage but not agent conversations |
| RAM requirement (baseline) | ~1 GB (without browser tools); ~3 GB with browser automation | ~300 MB | ~300 MB |
| License | MIT (Nous Research) | AGPL-3.0 (Walter-OS) | MIT (BerriAI) |
| Upstream maintenance cadence | Weekly releases; Nous Research team; 20+ contributors | Monthly updates; Walter-OS community | Biweekly releases; BerriAI team; 100+ contributors |

---

## Choose Hermes Agent if...

- You need multi-platform reach (Discord, Slack, GitHub, Gmail, etc.) from
  day one without writing custom webhook code. Hermes Agent ships 20+
  integrations; OpenClaw is Telegram-primary.
- You want the built-in Curator skill-learning loop and accept the trade-off
  (autonomous behavior mutation in exchange for self-improvement over time).
  Hermes Agent is the only option here.
- You are deploying on Kubernetes, Railway, or another orchestrator and need
  a runtime with first-class support for those backends. Hermes Agent supports
  7 deployment backends vs OpenClaw's 2.

---

## Choose OpenClaw if...

- You only need a Telegram bot for a single operator. OpenClaw covers this
  use case with ~700 MB less RAM than Hermes Agent (base config).
- Your host has tight memory constraints (< 1.5 GB available for agent
  services). OpenClaw is the lighter runtime.
- You prefer the simplest possible setup: one npm package, one bot, zero
  external image dependencies. OpenClaw installs itself from npm at startup;
  Hermes Agent requires pulling the Docker image.

---

## Neither — vanilla LiteLLM-as-agent if...

- You want to build custom integrations from scratch with full control over
  the agent logic (e.g., n8n workflow → LiteLLM → custom action).
- You only need an OpenAI-compatible API endpoint for other tools (Claude
  Code, Codex, Cursor) and do not need an autonomous agent at all.

---

## References

- **Hermes Agent**: https://hermes-agent.nousresearch.com
  - Docker Hub: https://hub.docker.com/r/nousresearch/hermes-agent
  - GitHub: https://github.com/NousResearch/hermes-agent
  - License: MIT
- **OpenClaw**: https://openclaw.dev
  - npm: `npm install -g openclaw`
  - Walter-OS service: `setup/walter-host/services/openclaw/`
  - License: AGPL-3.0 (via Walter-OS)
- **LiteLLM (Walter-Bridge)**: https://github.com/BerriAI/litellm
  - Walter-OS service: `setup/walter-host/services/litellm/`
  - Docs: https://docs.litellm.ai
  - License: MIT
