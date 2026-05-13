# gemini-sub-router — Operator Customization Guide

For pattern-level tradeoffs (when to use, cost model, legal/ToS, performance),
see: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`.

## What ships by default

OpenAI-compatible HTTP router wrapping the Gemini CLI (`@google/gemini-cli`).
- Port: `127.0.0.1:1458`
- Auth: bind-mount `/home/${OPERATOR_USER}/.gemini` for OAuth creds.
- No API key required beyond OAuth.
- Supported models: whatever the Gemini CLI exposes (see `MODEL_MAP` in `server.js`).

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | ~80 MB | Node.js + Express |
| RAM (request) | ~150-250 MB | Gemini CLI subprocess |
| Disk | minimal | CLI auth in host home dir |

## Common customizations

- **Add model aliases**: Update `MODEL_MAP` in `server.js` as Gemini releases new models.
- **Disable terminal colors**: Already set `NO_COLOR=1` and `TERM=dumb` in Dockerfile
  to prevent ANSI escape codes in subprocess output.
- **Timeout**: Adjust `setTimeout` in `invokeGemini()` for long context requests.

## LiteLLM integration

```yaml
# In litellm-config.yaml:
model_list:
  - model_name: gemini-2.5-pro
    litellm_params:
      model: openai/gemini-2.5-pro
      api_base: http://gemini-sub-router:1458/v1
      api_key: placeholder  # router does not require an API key
```

## References

- RUNBOOK.md: operational procedures
- Pattern guide: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`
- Gemini CLI: https://github.com/google-gemini/gemini-cli
