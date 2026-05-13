# Subscription Router Pattern — Operator Customization Guide

This directory documents the shared pattern for subscription LLM routers.
For service-specific configuration, see each router's own `SUGGESTIONS.md`:

- `chatgpt-codex-router/` — Codex CLI (ChatGPT subscription) on port 1456
- `claude-sub-router/` — Claude Code CLI (Claude Max subscription) on port 1457
- `gemini-sub-router/` — Gemini CLI (Google AI Pro subscription) on port 1458

## What the pattern provides

Each subscription router exposes an OpenAI-compatible HTTP API (`/v1/chat/completions`)
backed by a subscription CLI tool rather than a pay-per-token API. This allows
LiteLLM to route to these routers exactly like commercial providers, while the
actual tokens are served by the operator's active subscriptions.

**Economic model**: If your combined monthly usage would exceed the fixed cost
of the subscription, the router saves money. For high-volume operators, the
savings compound across all downstream tools that query LiteLLM.

## Architecture

```
LiteLLM (router) → subscription router (HTTP, localhost)
                       ↓
                   CLI subprocess (node child_process.spawn)
                       ↓
                   subscription service (Anthropic/OpenAI/Google cloud)
```

All routers:
- Run on `127.0.0.1` only (no external exposure, no Caddy vhost needed).
- Join the `litellm_default` Docker network for LiteLLM internal routing.
- Bind-mount host CLI credentials (`~/.codex`, `~/.claude`, `~/.gemini`).
- Implement `/health`, `/v1/models`, `/v1/chat/completions`.
- Structured JSON logging (NDJSON to stdout).

## RAM / disk baseline

| Resource | Baseline (per router) | Notes |
|---|---|---|
| RAM (idle) | ~60-100 MB | Node.js + Express |
| RAM (under load) | ~100-200 MB | Spawns CLI subprocess per request |
| Disk | minimal | No persistent state; CLI auth in host home dir |
| CPU | low (idle), high during CLI execution | CLI subprocess is the bottleneck |

Three routers combined: ~200-300 MB RAM idle.

## Common customizations

- **Add model aliases**: Update the `MODEL_MAP` in `server.js` to expose
  additional model slugs without changing LiteLLM config.

- **Add authentication**: The routers accept any request by default (or use
  `CCR_APIKEY` for codex-router). For external exposure, add an API key check
  middleware before the chat completions route.

- **Increase request timeout**: Default is 120 seconds per request.
  Adjust in `server.js` `invokeXxx()` function.

- **Add streaming**: Current v1 rejects `stream: true`. Implement SSE
  streaming by tailing CLI stdout and forwarding NDJSON events.

## When to skip this pattern

- **Low volume**: If you send <100K tokens/month, pay-per-token via LiteLLM's
  native provider support is simpler and often cheaper.
- **Team use**: Subscription accounts are personal. For team deployments,
  use API keys with proper billing isolation.
- **Reliability-critical paths**: CLI-based routers introduce subprocess
  latency (cold start ~1-2s). For latency-sensitive applications, use direct
  API keys.
- **Rate limits**: Subscription accounts have rate limits that differ from
  API accounts. Check the provider's subscription plan limits before routing
  production workloads through these.

## Legal / ToS considerations

Subscription accounts are generally personal-use only. Before routing team
or commercial workloads through a subscription account, verify the terms of
service for each provider:

- OpenAI/ChatGPT: https://openai.com/policies/terms-of-use
- Anthropic/Claude: https://www.anthropic.com/legal/consumer-terms
- Google/Gemini: https://ai.google.dev/gemini-api/terms

This pattern is documented for single-operator personal use.

## Tradeoffs

- **Cost predictability**: Fixed monthly subscription vs variable per-token cost.
- **Performance**: CLI subprocess adds ~500ms-2s latency vs direct API (~100-500ms).
- **Maintenance**: Subscriptions require periodic CLI version updates (`upgrade.sh`).
  Pay-per-token API is always at the latest version.
- **Isolation**: A single subscription account serves all requests — no
  per-tenant billing isolation.

## References

- Codex CLI: https://github.com/openai/codex
- Claude Code CLI: https://github.com/anthropics/claude-code
- Gemini CLI: https://github.com/google-gemini/gemini-cli
- LiteLLM custom providers: https://docs.litellm.ai/docs/providers/custom_openai_proxy
