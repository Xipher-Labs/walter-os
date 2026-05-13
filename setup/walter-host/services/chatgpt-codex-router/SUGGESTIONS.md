# chatgpt-codex-router — Operator Customization Guide

For pattern-level tradeoffs (when to use, cost model, legal/ToS, performance),
see: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`.

## What ships by default

OpenAI-compatible HTTP router wrapping the Codex CLI (`@openai/codex`).
- Port: `127.0.0.1:1456`
- Auth: bind-mount `/home/${OPERATOR_USER}/.codex` for OAuth tokens.
- Default API key: `CCR_APIKEY` env var (set in `.env.template`).
- Supported models: `gpt-5`, `gpt-5-mini`, `o4-mini` (see `MODEL_MAP` in `server.js`).

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | ~80 MB | Node.js + Express |
| RAM (request) | ~150-250 MB | Codex CLI subprocess |
| Disk | minimal | CLI auth in host home dir |

## Common customizations

- **Add model aliases**: Update `MODEL_MAP` in `server.js` for new Codex model slugs.
- **Change API key**: Set `CCR_APIKEY` in `.env` to match LiteLLM's configured key.
- **Adjust timeout**: Codex CLI can take up to 120s for long completions; adjust
  the `setTimeout` in `invokeCodex()`.

## LiteLLM integration

```yaml
# In litellm-config.yaml:
model_list:
  - model_name: gpt-5
    litellm_params:
      model: openai/gpt-5
      api_base: http://chatgpt-codex-router:1456/v1
      api_key: ${CCR_APIKEY}
```

## References

- RUNBOOK.md: operational procedures
- Pattern guide: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`
- Codex CLI: https://github.com/openai/codex
