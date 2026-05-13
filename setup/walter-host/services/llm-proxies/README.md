# LLM subscription proxies

Two containers expose **personal Claude Pro / ChatGPT Plus subscriptions** as
OpenAI-compatible HTTP endpoints. LiteLLM uses them as **fallback** when
API-key virtual key budgets exhaust — keeps automation running without
extra spend.

```
Workflow asks for `sonnet`:
   1. LiteLLM routes to Anthropic API (api_key, primary)
       └── if budget cap hit: 429 / 402
   2. LiteLLM falls back to claude-code-router (subscription, no per-token charge)
       └── if proxy down / OAuth expired: error
   3. LiteLLM falls back to gemini-2.5-pro (cheap last resort)
```

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │ Operator's Claude.ai / ChatGPT.com  │
                    │ subscriptions (browser session)     │
                    └──────────────┬──────────────────────┘
                                   │ OAuth tokens / cookies
                                   ▼
              ┌──────────────────────────────────────────┐
              │  claude-code-router (port 3456)          │
              │  chatgpt-proxy / pandora-next (port 8080)│
              │  exposes OpenAI-compatible /v1/chat/...  │
              └──────────────┬───────────────────────────┘
                             │ litellm_net (internal Docker)
                             ▼
                    ┌─────────────────────┐
                    │ LiteLLM (4000)      │
                    │ fallback chain      │
                    └──────────┬──────────┘
                               │
                               ▼
              n8n / OpenClaw / agent calls
```

NOT exposed via cloudflared. Internal-only. No CF Access app for them —
they live on Docker's internal network with no public endpoint.

## ToS reality

Anthropic's ToS for Claude Pro: subscription is for personal use, not
programmatic third-party serving. Walter-OS only serves the operator's
own automation (n8n workflows the operator owns, OpenClaw bot the
operator chats with). Operator's risk decision; Walter-OS hosts the
plumbing.

OpenAI similar terms for ChatGPT Plus.

If at any point the proxies stop working (Anthropic / OpenAI detects
+ rate-limits), LiteLLM gracefully falls back to API keys. No automation
breaks — just costs revert to per-token.

## Setup (one-time per machine)

### 1. Bring up containers

```bash
ssh walter-vm 'cd /opt/walter-vm/services/llm-proxies && docker compose up -d'
```

### 2. claude-code-router OAuth bootstrap

```bash
# On first boot, claude-code-router has no OAuth session.
# Bootstrap via interactive container exec:
ssh walter-vm
docker exec -it claude-code-router bash
ccr login                # opens device-flow URL → operator pastes into browser
# (browser → claude.ai → "Authorize Claude Code Router"? → approve)
# Token saved to /data/auth.json (persisted via volume)
exit
docker restart claude-code-router
```

Verify:
```bash
docker exec claude-code-router curl -s http://127.0.0.1:3456/v1/models | jq
# Should list claude-sonnet-4-5, claude-opus-4-5, etc.
```

### 3. ChatGPT proxy (pandora-next) token

pandora-next uses **session token** extracted from your chatgpt.com browser tab:

1. Log in to https://chat.openai.com
2. Browser DevTools → Application → Cookies → find `__Secure-next-auth.session-token`
3. Copy the value (long opaque string).

Then on the VM:

```bash
ssh walter-vm
docker exec -it chatgpt-proxy bash
echo '{"tokens": [{"token": "<paste-here>", "shared": false}]}' > /data/tokens.json
exit
docker restart chatgpt-proxy
```

Verify:
```bash
docker exec chatgpt-proxy curl -s http://127.0.0.1:8080/v1/models | jq
# Should list gpt-4, gpt-4o, etc.
```

### 4. Update LiteLLM config

The LiteLLM config update is committed in this repo at
`setup/walter-host/services/litellm/config.yaml`. Apply:

```bash
ssh walter-vm
sudo cp /opt/walter-vm/services/litellm/config.yaml{,.bak}
# (after pulling fresh from walter-os repo)
docker restart litellm
```

LiteLLM dashboard at https://llm.${WALTER_DOMAIN} → Models → should now show
`claude-sub` and `gpt-sub` as routed model_names.

## When subscriptions get rate-limited

**claude-code-router**: tokens last ~30 days from browser auth. When
expired, `ccr login` again. claude.ai sometimes flags unusual access
patterns + asks for re-verification. Just re-login.

**pandora-next**: session token lasts ~14-30 days. Rotate by repeating
the cookie extraction.

Both: Anthropic / OpenAI may rate-limit your subscription if abused. Set
LiteLLM's fallback chain so the next tier (cheap API) takes over
seamlessly.

## Hard rules

- **Never expose these proxies externally.** They're internal-only by
  design. No Cloudflare app, no published port, no DNS record.
- **Subscription proxies are FALLBACK, not primary.** Primary = API key
  with budget cap. The subscription path is for "after budget exhausted"
  not "let me save money by skipping budget".
- **One operator, one subscription.** Don't share the proxy with anyone.
  That's the line where ToS gets unambiguously violated.
- **Monitor in Telegram**: if proxy 503/401 → walter-vm-watchdog will
  catch it eventually. Add specific Kuma monitor for both proxies
  (HTTP /v1/models check).

## Troubleshooting

### Container restart loop
```bash
docker logs --tail 50 claude-code-router
# Common: missing /data/auth.json → run `ccr login` interactively first.
```

### LiteLLM doesn't see the proxy as a model
```bash
docker exec litellm curl -s http://claude-code-router:3456/v1/models
# Should return JSON. If timeout: check both containers are on litellm_net.
docker network inspect litellm_default | grep -A5 Containers
```

### Pandora-next "tokens.json invalid"
```bash
docker exec chatgpt-proxy cat /data/tokens.json | jq
# Must be valid JSON: {"tokens": [{"token": "<value>", "shared": false}]}
```

## What this does NOT cover

- Anthropic Claude Code's NEW OAuth flow (when Anthropic publishes a
  proper API for Claude subscription, this whole skill becomes
  unnecessary — switch to the official thing).
- Bedrock / Vertex AI proxies (separate concern, has its own LiteLLM
  provider blocks).
- Local LLMs (LM Studio, Ollama) — those are configured directly in
  LiteLLM, not via subscription proxies.

## References

- https://github.com/musistudio/claude-code-router
- https://github.com/pengzhile/pandora-next
- https://docs.litellm.ai/docs/proxy/reliability — fallbacks docs
