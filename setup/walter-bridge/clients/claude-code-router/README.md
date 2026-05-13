# claude-code-router — Walter-Bridge integration

Routes all `claude-code-router` requests through **Walter-Bridge** (LiteLLM at
`https://llm.${WALTER_DOMAIN}/v1`), giving you access to any model configured in
`setup/litellm/config.yaml` — Anthropic, OpenAI, Gemini, DeepSeek, and local
models — from a single source of truth.

## Prerequisites

Both vars must be set in `~/.config/walter-os/overlay/personal.env` (or `.env.local`):

```
WALTER_DOMAIN=your-homelab-domain.example.com
LITELLM_MASTER_KEY=sk-...
```

## Install

```bash
walter bridge install claude-code-router
```

Renders `config.template.json` into `~/.claude-code-router/config.json` via
`envsubst`. Any existing file is backed up to `config.json.bak.<timestamp>`.

## Manual install (fallback)

```bash
envsubst < setup/walter-bridge/clients/claude-code-router/config.template.json \
  > ~/.claude-code-router/config.json
```

## Verify

Start `claude-code-router` and test with a quick prompt:

```bash
# Confirm the Router config is loaded and the provider is "walter-bridge"
cat ~/.claude-code-router/config.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['Providers'][0]['name'])"
# Expected: walter-bridge
```

Then send a test message through claude-code-router to confirm end-to-end routing.

## Model aliases

The `Router` section maps task types to Walter-Bridge model aliases:

| Task type    | Model alias            |
|--------------|------------------------|
| default      | walter-bridge,sonnet   |
| background   | walter-bridge,haiku    |
| think        | walter-bridge,sonnet   |
| longContext  | walter-bridge,claude-3-5-sonnet |
| webSearch    | walter-bridge,sonnet   |

To change routing, edit `~/.claude-code-router/config.json` or re-render with
different env vars. All aliases resolve against `setup/litellm/config.yaml`.

## Security note

This config embeds `LITELLM_MASTER_KEY` in `~/.claude-code-router/config.json`.
That file is readable by any process running as your user — the same trust
boundary as `.env.local`. Ensure your homelab network restricts access to the
LiteLLM endpoint and rotate the master key periodically.

## Reference

- claude-code-router: https://github.com/musistudio/claude-code-router
- Tested against: claude-code-router as of 2026-05
- Walter-Bridge config: `setup/litellm/config.yaml`
