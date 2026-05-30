# Hermes Agent

Self-hostable agentic framework by Nous Research (MIT licensed).
Alternative to OpenClaw with 20+ platform integrations and an optional skill-learning loop.

Image: `walter-os/hermes-agent:${HERMES_AGENT_BASE_VERSION}-stt` (defaults to
`walter-os/hermes-agent:v2026.5.7-stt`, built locally from `Dockerfile`, and
extends `nousresearch/hermes-agent:${HERMES_AGENT_BASE_VERSION}` with pinned
`faster-whisper` for local privacy-preserving STT — see `Dockerfile` header for
the rationale).
Dashboard: `https://hermes.${WALTER_DOMAIN}`
API: `http://localhost:8642` (OpenAI-compatible, local-only)

**Upgrading the upstream Hermes version:**
1. Bump `HERMES_AGENT_BASE_VERSION` in `.env`.
2. `docker compose --profile hermes-agent build --no-cache` to rebuild.
3. `docker compose --profile hermes-agent up -d --force-recreate`.

For the decision matrix (Hermes vs OpenClaw vs vanilla LiteLLM-as-agent), see
`docs/operational/agent-runtimes-comparison.md`.

---

## Quickstart

**1. Prerequisites**

- LiteLLM (Walter-Bridge) is running at `https://llm.${WALTER_DOMAIN}`.
- Docker and Docker Compose are installed on the host.
- Caddy reverse proxy is configured with the `hermes.${WALTER_DOMAIN}` stanza
  (see `setup/walter-host/caddy/Caddyfile.template`).

**2. Create a LiteLLM virtual key for Hermes Agent**

Open `https://llm.${WALTER_DOMAIN}` → Virtual Keys → Create Key.
Name it `hermes-agent`. Copy the generated key.

**3. Copy `.env.template` to `.env` and fill in the key**

```bash
cp .env.template .env
# Edit .env and set:
#   LITELLM_HERMES_KEY=sk-<your-key>
```

See `SUGGESTIONS.md §4` for LiteLLM routing details and `SUGGESTIONS.md §5`
for optional platform integrations (Telegram, Discord, Slack, etc.).

**4. Start the service and wait for the healthcheck**

```bash
docker compose --profile hermes-agent up -d
# Wait for healthy status (up to 90 s start period):
docker compose --profile hermes-agent ps
```

The healthcheck polls `http://127.0.0.1:8642/health` every 60 s.
The service is ready when status shows `healthy`.

**5. Open the dashboard or connect via Telegram**

- Dashboard: `https://hermes.${WALTER_DOMAIN}` (requires Caddy configured).
- API (OpenAI-compatible): `http://localhost:8642/v1` (local only by default).
- Telegram: set `HERMES_TELEGRAM_BOT_TOKEN` in `.env` and restart (see `SUGGESTIONS.md §5`).
