# RUNBOOK — gemini-sub-router

Operational runbook for the Google Gemini CLI → LiteLLM HTTP bridge on Walter-VM.
Mirrors the chatgpt-codex-router pattern but uses `gemini -p --output-format=json`.
Requires an active Google AI Pro (Gemini Advanced) subscription.

## First-time auth

```bash
# Container is running but health returns 503 if credentials are missing
docker compose up -d
docker exec -it gemini-sub-router gemini auth login
# Complete the browser OAuth flow
# Verify:
curl http://localhost:1458/health
# → {"status":"ok","auth":"ok"}
```

## Verify auth

```bash
curl http://localhost:1458/health
docker exec gemini-sub-router gemini --version
```

## View logs

```bash
docker logs gemini-sub-router --tail 50 -f
```

## Manual smoke test

```bash
curl -sS -X POST http://localhost:1458/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/gemini-2.5-pro","messages":[{"role":"user","content":"Reply: BRIDGE_OK"}]}'
```

## Start / stop / restart

```bash
cd /opt/walter-vm/services/gemini-sub-router
docker compose restart   # auth volume persists across restarts
docker compose down
docker compose up -d
```

## Network verification

```bash
docker network inspect litellm_default | grep gemini
# Should show gemini-sub-router in the container list
```

## Token refresh

OAuth creds live in the bind-mounted `/home/walter/.gemini` directory.
The Gemini CLI refreshes them automatically. If auth fails:

```bash
docker exec -it gemini-sub-router gemini auth login
```

## Refs

- See subscription-router-pattern/SUGGESTIONS.md for pattern-level tradeoffs
- Gemini CLI docs: https://github.com/google-gemini/gemini-cli
