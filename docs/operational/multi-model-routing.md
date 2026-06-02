# Multi-Model Routing

Walter-OS routes agent and skill work by task domain, not by a hardcoded
provider. The operator declares preferences in:

```text
~/.config/walter-os/overlay/personal.env
```

The core resolver lives at:

```text
scripts/walter/lib/model-router.sh
```

Use it from shell code with:

```bash
source "$WALTER_OS_HOME/scripts/walter/lib/model-router.sh"
model="$(walter_model_for backend_review)"
```

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
  task domain once callers set `WALTER_MODEL_DOMAIN` through the resolver.
