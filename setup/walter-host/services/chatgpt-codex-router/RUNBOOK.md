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

## Multiple ChatGPT accounts

`docker-compose.solx.yml` adds a second router, `chatgpt-codex-router-solx`,
that runs the same image against a second Codex home (`~/.codex-solx` by
default, override with `CODEX_SOLX_HOME`). LiteLLM declares every
`chatgpt-codex-router` deployment twice, once per router, under the same
`model_name`, so each group load-balances across both accounts. When one
account fails repeatedly (usage limit, expired login), LiteLLM's
`allowed_fails` / `cooldown_time` take that deployment out of rotation and
the other account serves.

| Router | Codex home (host) | Host debug port | Key env (router / LiteLLM) |
|---|---|---|---|
| `chatgpt-codex-router` | `~/.codex` | `127.0.0.1:1456` | `CCR_APIKEY` |
| `chatgpt-codex-router-solx` | `~/.codex-solx` | `127.0.0.1:1459` | `CCR_SOLX_APIKEY` (injected into the container as `CCR_APIKEY`) |

Enable it in the router's `.env`:

```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.solx.yml
CCR_SOLX_APIKEY=<openssl rand -hex 32>
```

LiteLLM must receive the same `CCR_SOLX_APIKEY` value. On a host that loads
LiteLLM secrets through the Infisical sidecar, store it next to `CCR_APIKEY`
in workspace `walter-vm-internal`, env `prod`, path `/litellm`; on a host with
a local `litellm.env`, add it there. Then log the new router in once:

```bash
docker exec -it chatgpt-codex-router-solx codex login
```

Never mount the same Codex home into both routers: they would race on token
refresh and both drop to the same account.

## Check which account a router uses

The account is in the `id_token` claims of `auth.json`. This prints only the
email and plan, never the tokens:

```bash
for r in chatgpt-codex-router chatgpt-codex-router-solx; do
  printf '%s: ' "$r"
  docker exec "$r" node -e '
    const a = require(process.env.HOME + "/.codex/auth.json");
    const p = JSON.parse(Buffer.from(a.tokens.id_token.split(".")[1], "base64url").toString());
    const o = p["https://api.openai.com/auth"] || {};
    console.log(p.email, o.chatgpt_plan_type || "?");'
done
```

## Diagnose account exhaustion

Symptom: Codex-backed LiteLLM groups return 502, and the router log shows only
`codex_error` with no reason. The router hides the CLI's message, so run the
CLI directly inside the suspect container:

```bash
docker exec chatgpt-codex-router sh -c \
  'cd /tmp && codex exec --skip-git-repo-check -m gpt-6-luna "pong"'
```

A usage-limit message there (with its reset date) means the account is
exhausted; restarting the router does not help. Actions:

1. Confirm the other router still answers (same command against
   `chatgpt-codex-router-solx`) and that LiteLLM has that group's second
   deployment (`docker exec litellm cat /app/config.yaml`).
2. If a group has only one deployment, add the twin on the other router and
   restart LiteLLM, or wait for the reset.
3. `ai-stack-watchdog.sh` probes each router directly and alerts (without
   restarting) when one account stops answering.

A `401`/login message instead means the auth expired: re-run
`docker exec -it <router> codex login`.
