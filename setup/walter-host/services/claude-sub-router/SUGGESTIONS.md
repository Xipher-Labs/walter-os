# claude-sub-router — Operator Customization Guide

For pattern-level tradeoffs (when to use, cost model, legal/ToS, performance),
see: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`.

## What ships by default

OpenAI-compatible HTTP router wrapping the Claude Code CLI (`@anthropic-ai/claude-code`).
- Port: `127.0.0.1:1457`
- Auth: bind-mount `/home/${OPERATOR_USER}/.claude` for OAuth tokens.
- No API key required beyond OAuth (the CLI handles auth).
- Supported models: `sonnet`, `opus`, `haiku`, `claude-sonnet-4-6`, `claude-opus-4-5` (see `MODEL_MAP`).

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | ~80 MB | Node.js + Express |
| RAM (request) | ~150-250 MB | Claude Code CLI subprocess |
| Disk | minimal | CLI auth in host home dir |

## Common customizations

- **Add model aliases**: Update `MODEL_MAP` in `server.js` when new Claude snapshots release.
- **Timeout**: Claude responses can take up to 120s; adjust the `setTimeout` in `invokeClaude()`.

## LiteLLM integration

```yaml
# In litellm-config.yaml:
model_list:
  - model_name: claude-sonnet-latest
    litellm_params:
      model: openai/sonnet
      api_base: http://claude-sub-router:1457/v1
      api_key: placeholder  # router does not require an API key
```

## References

- RUNBOOK.md: operational procedures
- Pattern guide: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`
- Claude Code CLI: https://github.com/anthropics/claude-code
