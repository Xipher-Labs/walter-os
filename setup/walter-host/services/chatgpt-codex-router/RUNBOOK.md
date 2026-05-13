# RUNBOOK — chatgpt-codex-router

Operational runbook for the Codex CLI → LiteLLM HTTP bridge on Walter-VM.
See also: your project-specific runbook (add your path here).

## First-time auth

```bash
# Container is running but health returns 503 if auth.json is missing
docker compose up -d
docker exec -it chatgpt-codex-router codex login
# Complete the browser OAuth flow
# Verify:
curl http://localhost:1456/health
# → {"status":"ok","codex_output":"Logged in using ChatGPT"}
```

## Verify auth

```bash
curl http://localhost:1456/health
docker exec chatgpt-codex-router codex login status
```

## View logs

```bash
docker logs chatgpt-codex-router --tail 50 -f
```

## Manual smoke test

```bash
curl -sS -X POST http://localhost:1456/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/gpt-5","messages":[{"role":"user","content":"Reply: BRIDGE_OK"}]}'
```

## Start / stop / restart

```bash
cd /opt/walter-vm/services/chatgpt-codex-router
docker compose restart   # auth volume persists
docker compose down
docker compose up -d
```

## Upgrade procedure (manual)

```bash
bash /opt/walter-vm/services/chatgpt-codex-router/upgrade.sh
# Auto-runs weekly at 0 4 * * 1 (Monday 04:00)
# Logs: /var/log/codex-upgrade.log
```

## Network verification

```bash
docker network inspect litellm_default | grep chatgpt
# Should show chatgpt-codex-router in the container list
```

## Telegram alerts

The upgrade script sends alerts to your Telegram ops bot (configure TELEGRAM_BOT_TOKEN and TELEGRAM_OPS_CHAT_ID).
Requires TELEGRAM_BOT_TOKEN and TELEGRAM_OPS_CHAT_ID in env.
Source: Infisical walter-os/prod or /opt/walter-vm/services/.env
