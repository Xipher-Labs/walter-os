# codex-cli — Walter-Bridge integration

Routes all `codex` CLI requests through **Walter-Bridge** (LiteLLM at
`https://llm.${WALTER_DOMAIN}/v1`), giving you access to any model configured
in `setup/litellm/config.yaml` — GPT, Claude, Gemini, DeepSeek, local models —
from one source of truth.

## Prerequisites

Both vars must be set in `~/.config/walter-os/overlay/personal.env` (or `.env.local`):

```
WALTER_DOMAIN=your-homelab-domain.example.com
LITELLM_MASTER_KEY=sk-...
```

`LITELLM_MASTER_KEY` must also be exported in your shell so Codex CLI can read it
at runtime (the `env_key = "LITELLM_MASTER_KEY"` field in the config tells Codex
which env var to use for the Bearer token).

## Install

```bash
walter bridge install codex-cli
```

Renders `config.template.toml` into `~/.codex/config.toml` via `envsubst`.
Any existing file is backed up to `config.toml.bak.<timestamp>`.

## Manual install (fallback)

```bash
envsubst < setup/walter-bridge/clients/codex-cli/config.template.toml \
  > ~/.codex/config.toml
```

## Verify

```bash
codex 'echo "ping"'
```

A successful response confirms that Codex CLI is routing through Walter-Bridge.
To verify the specific model used, check the LiteLLM usage dashboard at
`https://llm.${WALTER_DOMAIN}`.

## Switching models

Pass `--model <alias>` to use any alias registered in `setup/litellm/config.yaml`:

```bash
codex --model sonnet 'explain this function'
codex --model gemini-2.5-pro 'review this PR diff'
codex --model deepseek-r1 'reason through this algorithm'
```

## Security note

`config.template.toml` renders the Walter-Bridge `base_url` into
`~/.codex/config.toml`. The actual API key (`LITELLM_MASTER_KEY`) is NOT stored
in the rendered file — it is read from the environment at runtime via `env_key`.
This is more secure than the JSON-based CLIs (which embed the key in the config
file), but the env var must be present in every shell session that runs `codex`.
Add it to `~/.config/walter-os/overlay/personal.env` and source it in your shell
profile.

## Reference

- codex-cli: https://github.com/openai/codex
- Tested against: codex-cli as of 2026-05
- Walter-Bridge config: `setup/litellm/config.yaml`
