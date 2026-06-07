# AI Capability Profiles

Walter-OS can run with different combinations of AI tools. Operators do not
need Claude, Codex, Copilot, Gemini, and a local LLM all at once.

Use provider configuration for API/backend selection:

```bash
walter providers configure --category llm
```

Use capability profiles for tool availability and routing policy:

```bash
walter ai configure --profile mixed
walter ai validate
walter ai status
```

The capability profile is private operator metadata written to:

```text
~/.config/walter-os/ai-capabilities.yaml
```

It does not store API keys or secrets.

## Path Decision

The active capability file lives under `~/.config/walter-os/` because it is
private operator metadata: it can reveal which AI tools, local LLMs, and review
fallbacks are available on a specific machine. It should not be committed to a
project repository.

The committed example lives at:

```text
contexts/_examples/ai-capabilities.yaml.example
```

It is an example rather than a runtime template because `walter ai configure`
is the source of generated config. Keep the example synchronized with the
generated schema and validate either file with:

```bash
walter ai validate
walter ai validate contexts/_examples/ai-capabilities.yaml.example
```

## Profiles

| Profile | Use when | Default routing |
|---|---|---|
| `claude-only` | The operator has Claude/Claude Code but not Codex or Gemini. | General review, planning, UX/UI, and research route to Claude. Image generation and local-only compliance remain `none`. |
| `codex-only` | The operator has Codex/OpenAI but not Claude. | General review, backend, security, planning, UX/UI, and research route to Codex. Image generation and local-only compliance remain `none`. |
| `gemini-only` | The operator has Gemini and wants one vendor for most AI work. | General review, planning, UX/UI, image generation, and research route to Gemini. Local-only compliance remains `none`. |
| `local-only` | The operator requires local execution for security, compliance, PHI, or offline work. | Every capability routes to Ollama/local. |
| `mixed` | The operator has the full recommended tool mix. | Copilot+Codex for review, Codex for infra/security/backend, Claude for planning/UX/UI, Gemini for images/research, Ollama for local-only compliance. |

## Overrides

Operators can start from a profile and override specific capabilities:

```bash
walter ai configure --profile claude-only \
  --set image_generation=gemini \
  --set research=gemini
```

Supported capabilities:

- `code_review`
- `infra_security_backend`
- `planning`
- `ux_ui`
- `image_generation`
- `research`
- `compliance_local_only`

Supported route values:

- `claude`
- `codex`
- `copilot`
- `gemini`
- `ollama`
- `none`

Comma-separated review routes are allowed, for example:

```bash
walter ai configure --profile mixed --set code_review=copilot,codex
```

## Degraded Review Flows

If Copilot, Codex, or Claude is unavailable, the operator should choose the
closest capability profile instead of pretending the standard three-round review
loop is fully available.

Examples:

- `codex-only`: use Codex for implementation review and note that Copilot/Claude
  review is unavailable.
- `claude-only`: use Claude for planning, implementation review, and docs review;
  skip Codex-specific cross-review until Codex is installed.
- `local-only`: keep reviews local through Ollama/local tooling and avoid
  sending compliance-sensitive or PHI data to external APIs.
- `mixed`: use the full standard flow when all configured tools are available.

Run this before opening or reviewing substantial PRs:

```bash
walter ai validate
walter ai status
```
