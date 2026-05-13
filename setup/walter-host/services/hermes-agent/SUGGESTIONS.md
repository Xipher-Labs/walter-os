# Hermes Agent — Operator Suggestions

Guidance for configuring and operating Hermes Agent on Walter-OS.
See `README.md` for the quickstart.

---

## 1. When to use Hermes Agent vs OpenClaw

| Criterion | Hermes Agent | OpenClaw |
|---|---|---|
| Out-of-the-box platform integrations | 20+ (Telegram, Discord, Slack, GitHub, Jira, Linear, Notion, Gmail, Calendar, and more) | Telegram primary; Matrix via Beeper (Phase 2) |
| Skill-learning loop | Built-in Curator (autonomous background skill management; off by default) | No built-in skill learning; relies on Walter-OS skill prompts |
| Deployment backends | 7 (Docker, bare metal, Kubernetes, Railway, Fly.io, Render, Heroku) | Docker and bare metal only |
| Docker image source | Docker Hub (`nousresearch/hermes-agent`) | npm package installed into `node:24-slim` at runtime |
| LiteLLM / Walter-Bridge integration | Native OpenAI-compatible endpoint; point at `http://litellm:4000` | Same pattern (`OPENAI_API_BASE`) |
| Community | Nous Research (MIT, actively maintained, weekly releases) | Walter-OS community (AGPL, operator-focused) |

**Rule of thumb**: choose Hermes Agent when you need broad platform reach from day one, or when you plan to enable the skill-learning loop. Choose OpenClaw when you want a minimal, Telegram-only personal assistant with the lowest RAM footprint.

---

## 2. When to use Hermes Agent vs not at all

**Use Hermes Agent when you want:**
- Multi-platform reach (Discord, Slack, GitHub, Gmail, etc.) from day one without custom integrations.
- The built-in Curator skill-learning loop — after careful evaluation (see §3).
- A framework with frequent upstream releases and a large community for integrations.

**Skip Hermes Agent (use OpenClaw instead) when:**
- You only need a Telegram bot for a single operator. OpenClaw covers this with ~300 MB less RAM.
- Your instance has tight memory constraints (< 1.5 GB available for agent services).
- You prefer the simplest possible setup: one npm package, one bot, done.

Both runtimes can run simultaneously if you need both coverage patterns. They do not share state or interfere with each other.

---

## 3. Configuring the skill-learning loop (Curator)

**What Curator does**: Curator is Hermes Agent's autonomous background process that monitors agent performance, identifies skill gaps, and updates or creates new skill modules without manual intervention. It runs as a background thread and can change how the agent responds to future requests.

**Why it is off by default**: Curator mutates agent behavior in ways that are difficult to audit after the fact. An operator who enables Curator should trust Nous Research's upstream skill updates, have Grafana spend monitoring configured, and understand that agent responses may shift over releases. For a single-operator Walter-OS deployment, the default Walter-OS skills (prompt-methodology documents) cover most use cases without any mutation risk.

**How to enable Curator:**
1. Set `HERMES_CURATOR_ENABLED=true` in your `.env`.
2. Restart the service: `docker compose --profile hermes-agent up -d hermes-agent`.
3. Monitor the Grafana dashboard for unusual spend spikes (Curator triggers LLM calls in the background).
4. Set `HERMES_DAILY_COST_CAP_USD` to a non-zero value to prevent runaway spend.

**Recommended monitoring posture**: Add a Grafana alert on the LiteLLM cost dashboard for the `hermes-agent` virtual key. A healthy Curator process adds 5–15% background LLM usage; anything above 50% indicates a runaway loop.

---

## 4. Connecting to Walter-Bridge (LiteLLM)

Hermes Agent is pre-configured to route all LLM traffic through Walter-Bridge (LiteLLM), giving you cost attribution, multi-provider fallback, and a unified audit log.

**Step-by-step:**

1. Open the LiteLLM UI at `https://llm.${WALTER_DOMAIN}`.
2. Go to **Virtual Keys** → **Create Key**.
3. Set the key name to `hermes-agent` and assign it to the appropriate team or budget.
4. Copy the generated key.
5. Open `setup/walter-host/services/hermes-agent/.env` (create from `.env.template` if not done yet).
6. Paste the key as `LITELLM_HERMES_KEY=sk-...`.
7. Confirm `LITELLM_BASE_URL=http://litellm:4000` (default; change only if LiteLLM runs on a non-default port).
8. Start the service: `docker compose --profile hermes-agent up -d`.

**Benefits of routing through LiteLLM:**
- **Cost attribution**: see exactly how much Hermes Agent spends per day in the LiteLLM dashboard.
- **Multi-provider fallback**: if your primary provider is down, LiteLLM automatically retries on the fallback chain.
- **Unified audit log**: all LLM calls from all services (OpenClaw, Hermes Agent, n8n, etc.) appear in one place.

**To bypass LiteLLM** (direct provider): set `HERMES_LLM_PROVIDER=openai` and `OPENAI_API_KEY=sk-...`. You lose the benefits above but gain lower latency. Not recommended for production.

---

## 5. Platform integrations

Hermes Agent supports 20+ platform integrations out of the box. Enable only what you need — each integration adds memory overhead (~50–100 MB each for webhook-based ones).

### Telegram (primary)

Telegram is the recommended primary channel for Walter-OS operators, matching the OpenClaw pattern:

1. Create a new bot via [@BotFather](https://t.me/BotFather). Use a separate bot from your OpenClaw bot to avoid routing conflicts.
2. Copy the bot token and set `HERMES_TELEGRAM_BOT_TOKEN=<token>` in `.env`.
3. Set `HERMES_TELEGRAM_OPERATOR_CHAT_ID=<your-chat-id>` (find via @userinfobot).
4. Restart: `docker compose --profile hermes-agent up -d hermes-agent`.

### Discord (optional)

1. Create a Discord application at [discord.com/developers](https://discord.com/developers/applications).
2. Add a bot to the application; copy the bot token.
3. Set `HERMES_DISCORD_BOT_TOKEN=<token>` and `HERMES_DISCORD_GUILD_ID=<your-server-id>` in `.env`.

### Slack (optional)

1. Create a Slack app at [api.slack.com/apps](https://api.slack.com/apps).
2. Enable Socket Mode. Copy the bot token and signing secret.
3. Set `HERMES_SLACK_BOT_TOKEN=xoxb-...` and `HERMES_SLACK_SIGNING_SECRET=...` in `.env`.

### Other integrations

Hermes Agent supports GitHub, Jira, Linear, Notion, Gmail, Google Calendar, and more. See the upstream docs for the full integration list and token requirements:
[https://hermes-agent.nousresearch.com/docs/integrations](https://hermes-agent.nousresearch.com/docs/integrations)

---

## 6. Resource baselines

| Backend configuration | RAM | Disk | Notes |
|---|---|---|---|
| Local-only (no browser, no Curator) | ~1 GB | ~2 GB | Minimum viable config. Telegram or API only. |
| With browser automation tools | ~3 GB | ~5 GB | `shm_size: 1g` already set in compose.yml. Required for web-scraping and form-filling skills. |
| With Curator enabled | +500 MB RAM (typical) | +200 MB | Curator caches skill artifacts. Monitor Grafana for growth. |
| Full config (browser + Curator + 3+ integrations) | ~4 GB | ~6 GB | Recommended only on hosts with 8 GB+ RAM. |

**Minimum host RAM for Hermes Agent alongside core Walter-OS services**: 6 GB (core stack ~3 GB + Hermes base ~1 GB + 2 GB buffer).
