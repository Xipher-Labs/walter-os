# Multi-Model Routing

Walter-OS routes agent and skill work by task domain, not by a hardcoded
provider. The operator declares preferences in:

```text
~/.config/walter-os/overlay/personal.env
```

Generate the standard preferences from the declared AI capability profile:

```bash
walter ai configure --profile mixed
```

That command writes both `~/.config/walter-os/ai-capabilities.yaml` and the
managed `WALTER_MODEL_*` block in `~/.config/walter-os/overlay/personal.env`.
Manual edits are still supported for advanced operators.

For the `mixed` profile, `WALTER_MODEL_PHI` is written as `ollama` because the
capability profile declares the local Ollama runtime. The unset resolver default
remains `local-ollama`; both values are treated as local-only by
`walter_model_for phi`.

The core resolver lives at:

```text
scripts/walter/lib/model-router.sh
```

Use it from shell code with:

```bash
source "$WALTER_OS_HOME/scripts/walter/lib/model-router.sh"
model=""
walter_model_resolve backend_review model
```

`walter_model_resolve` assigns the primary route and preserves
`WALTER_MODEL_DOMAIN` for the next `llm_invoke` call. Use `walter_model_for`
when a caller intentionally needs the full comma-separated route for its own
parallel fan-out logic.

Walter Council persona files under `agents/*.md` declare a `model_domain`
frontmatter field. That field is the authoritative Walter routing signal for
`scripts/agents/run.sh`. The adjacent `model` field remains as host/tool-loader
compatibility metadata for clients that still expect a concrete model name in
agent frontmatter.

## Domains

| Domain | Env var | Default | Intended use |
|---|---|---:|---|
| `backend_review` | `WALTER_MODEL_BACKEND_REVIEW` | `codex` | Backend, security, infrastructure, data correctness |
| `frontend` | `WALTER_MODEL_FRONTEND` | `claude` | UX, UI, visual critique, accessibility writing |
| `longform` | `WALTER_MODEL_LONGFORM` | `claude` | Docs, essays, proposals, narrative content |
| `quick_refactor` | `WALTER_MODEL_QUICK_REFACTOR` | `codex` | Small code edits and mechanical refactors |
| `phi` | `WALTER_MODEL_PHI` | `local-ollama` | PHI, medical, privileged, or compliance-sensitive data |
| `brainstorm` | `WALTER_MODEL_BRAINSTORM` | `claude,codex` | Planning, strategy, second opinions, research synthesis |
| `default` | `WALTER_MODEL_DEFAULT` | `claude` | Anything without a stronger domain |

Values are LiteLLM-style aliases. A comma-separated value means the caller may
run the models in parallel and synthesize both outputs:

```bash
WALTER_MODEL_BRAINSTORM=claude,codex,gemini
```

`WALTER_MODEL_OVERRIDE` can force a model for one invocation:

```bash
WALTER_MODEL_OVERRIDE=gemini walter-os status --models
```

The PHI route is the exception. `walter_model_for phi` ignores
`WALTER_MODEL_OVERRIDE` and refuses non-local values.

## Runtime Execution

`walter_model_for` resolves the preferred runtime alias for a domain. Execution
still depends on a configured gateway or direct runtime:

- With `LITELLM_BASE_URL` and `LITELLM_API_KEY`, `scripts/agents/lib/llm.sh`
  sends the resolved alias to LiteLLM. The alias must exist as a `model_name`
  in the operator's LiteLLM config. LiteLLM owns provider credentials,
  telemetry, budget caps, and alias-to-provider mapping.
- Without LiteLLM, `llm.sh` supports only Anthropic-compatible direct fallback
  through `ANTHROPIC_API_KEY` or `ANTHROPIC_ENTERPRISE_KEY`.
- If a route resolves to `cheap`, `claude-sub`, `codex`, `codex-sub`,
  `gemini-sub`, `local-ollama`, or another LiteLLM-only/non-Anthropic alias
  without LiteLLM or a matching direct runtime, `llm.sh` fails closed instead
  of sending the request to Anthropic.

This means `WALTER_MODEL_*` values declare preference, not proof of executable
credentials. Use `walter ai status` to inspect declared/detected availability
before running long-lived workflows.

## Status

Show the effective routing table:

```bash
walter-os status --models
```

If the Walter Council Prometheus textfile is present, the command also prints
token counters by model from `walter_council_tokens_total`.

## Security Notes

- `WALTER_MODEL_*` keys are included in the env allowlist parser.
- Invalid values are ignored and the resolver falls back to the domain default.
- PHI routing is fail-closed to `local-ollama` when misconfigured.
- The LLM helper emits `metadata.domain` so LiteLLM usage can be attributed by
  task domain when callers use `walter_model_resolve <domain> <out-var>`.
