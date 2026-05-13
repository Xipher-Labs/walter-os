# RUNBOOK — claude-sub-router

Operational runbook for the Claude Code CLI → LiteLLM HTTP bridge on Walter-VM.
Mirrors the chatgpt-codex-router pattern but uses `claude -p --output-format=json`.

## First-time auth

```bash
# Container is running but health returns 503 if credentials are missing
docker compose up -d
docker exec -it claude-sub-router claude login
# Complete the browser OAuth flow (Claude Code OAuth)
# Verify:
curl http://localhost:1457/health
# → {"status":"ok","auth":"ok"}
```

## Verify auth

```bash
curl http://localhost:1457/health
docker exec claude-sub-router claude --version
```

## View logs

```bash
docker logs claude-sub-router --tail 50 -f
```

## Manual smoke test

```bash
curl -sS -X POST http://localhost:1457/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/sonnet","messages":[{"role":"user","content":"Reply: BRIDGE_OK"}]}'
```

## Start / stop / restart

```bash
cd /opt/walter-vm/services/claude-sub-router
docker compose restart   # auth volume persists across restarts
docker compose down
docker compose up -d
```

## Network verification

```bash
docker network inspect litellm_default | grep claude
# Should show claude-sub-router in the container list
```

## Token refresh

The Claude Code CLI refreshes OAuth tokens automatically when the container
accesses the bind-mounted `/home/walter/.claude` directory. If tokens expire:

```bash
docker exec -it claude-sub-router claude login
```

## Refs

- See subscription-router-pattern/SUGGESTIONS.md for pattern-level tradeoffs
- Claude Code CLI docs: https://github.com/anthropics/claude-code
