# gemini-cli — Walter-Bridge integration

Routes all `gemini-cli` requests through **Walter-Bridge** (LiteLLM at
`https://llm.${WALTER_DOMAIN}/v1`), allowing any model registered in
`setup/litellm/config.yaml` to serve gemini-cli requests. The OpenAI-compatible
mode in gemini-cli means any LiteLLM alias works — not just Gemini models.

Tested against: gemini-cli main as of 2026-05.

## Prerequisites

Both vars must be set in `~/.config/walter-os/overlay/personal.env` (or `.env.local`):

```
WALTER_DOMAIN=your-homelab-domain.example.com
LITELLM_MASTER_KEY=sk-...
```

## Install

```bash
walter bridge install gemini-cli
```

Renders `settings.template.json` into `~/.gemini/settings.json` via `envsubst`.
Any existing file is backed up to `settings.json.bak.<timestamp>`.

## Manual install (fallback)

```bash
envsubst < setup/walter-bridge/clients/gemini-cli/settings.template.json \
  > ~/.gemini/settings.json
```

## Verify

```bash
gemini --model gemini "ping"
```

If the request routes through Walter-Bridge, you will see token usage attributed
to the LiteLLM `gemini` alias in the LiteLLM dashboard at
`https://llm.${WALTER_DOMAIN}`.

## Notes on gemini-cli config schema

gemini-cli reads `~/.gemini/settings.json` for persistent configuration. As of
2026-05 (gemini-cli main), the `selectedAuthType: "openai-compatible"` mode
instructs the CLI to send requests to `apiBaseUrl` with an Authorization header
using `apiKey`. If the gemini-cli project changes its config schema in a future
release, this template may need updating — check the upstream
[settings documentation](https://github.com/google-gemini/gemini-cli) when
upgrading.

## Security note

This config embeds `LITELLM_MASTER_KEY` in `~/.gemini/settings.json`.
That file is readable by any process running as your user — the same trust
boundary as `.env.local`. Ensure your homelab network restricts access to the
LiteLLM endpoint and rotate the master key periodically.

## Reference

- gemini-cli: https://github.com/google-gemini/gemini-cli
- Walter-Bridge config: `setup/litellm/config.yaml`
