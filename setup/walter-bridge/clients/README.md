# Walter-Bridge client config templates

This directory ships ready-to-render config templates for three CLI tools that
speak the OpenAI-compatible API. Each template points at **Walter-Bridge**
(LiteLLM served at `https://llm.${WALTER_DOMAIN}/v1`) as the single backend,
so any model alias defined in `setup/litellm/config.yaml` is available to all
three tools without managing separate API keys or base URLs.

## Modules

| CLI | Template | Target path | Notes |
|-----|----------|-------------|-------|
| [claude-code-router](./claude-code-router/) | `config.template.json` | `~/.claude-code-router/config.json` | Routes Claude Code traffic through a proxy layer; supports per-task model selection |
| [gemini-cli](./gemini-cli/) | `settings.template.json` | `~/.gemini/settings.json` | Google's Gemini CLI; uses OpenAI-compatible mode to hit Walter-Bridge |
| [codex-cli](./codex-cli/) | `config.template.toml` | `~/.codex/config.toml` | OpenAI Codex CLI; reads API key from env at runtime (key not stored in config file) |

## When to install each

- **claude-code-router** — install if you run `claude-code-router` as a proxy
  in front of Claude Code and want to route individual request types (default,
  background, longContext) to different Walter-Bridge aliases.

- **gemini-cli** — install if you use `gemini` CLI for agentic tasks and want
  it backed by Walter-Bridge rather than direct Google API keys.

- **codex-cli** — install if you use `codex` CLI (OpenAI's agentic coding tool)
  and want it routed through Walter-Bridge for model flexibility and cost tracking.

You can install all three at once: `walter bridge install all`.

## Prerequisites

Both env vars must be set before rendering:

```
WALTER_DOMAIN=your-homelab-domain.example.com
LITELLM_MASTER_KEY=sk-...
```

Set them in `~/.config/walter-os/overlay/personal.env`. The `walter bridge install`
command sources this file automatically.

## Quick start

```bash
# Install a specific CLI
walter bridge install claude-code-router
walter bridge install gemini-cli
walter bridge install codex-cli

# Install all three at once
walter bridge install all

# Check routing status
walter bridge status
```

## Architecture

```
CLI tool (claude-code-router | gemini-cli | codex-cli)
    |
    | OpenAI-compatible API (Bearer: LITELLM_MASTER_KEY)
    v
Walter-Bridge (LiteLLM)  https://llm.${WALTER_DOMAIN}/v1
    |
    | Routes by model alias
    v
Provider (Anthropic | OpenAI | Google | DeepSeek | local vLLM)
```

The model alias list lives in `setup/litellm/config.yaml`. All three CLIs use
the same aliases; switching providers is a one-line change in that file with no
changes needed to any CLI config.
