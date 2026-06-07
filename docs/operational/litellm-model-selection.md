# LiteLLM Model Selection Guide

> Covers: routing convention, cost tiers, privacy tiers, and how to add a
> new provider.
>
> Refs: docs/specs/walter-bridge-litellm-expansion.md

---

## Routing convention

Agents invoke models by **alias**, not by provider/model string. LiteLLM
resolves the alias to the concrete model and handles auth.

```bash
# agents call via the gateway — no provider coupling in agent code
curl -s "$LITELLM_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model": "sonnet", "messages": [{"role": "user", "content": "..."}]}'
```

The alias-to-model mapping lives entirely in `setup/litellm/config.yaml`.
Agents never hard-code provider names or model slugs.

If `LITELLM_BASE_URL` is unavailable, `scripts/agents/lib/llm.sh` falls back
to direct Anthropic (`ANTHROPIC_API_KEY`), then enterprise key
(`ANTHROPIC_ENTERPRISE_KEY` when `WALTER_AGENT_CONTEXT=work`).

This guide covers model aliases once an LLM backend exists. To declare which AI
tools the operator actually has available for planning, review, UX/UI, image
generation, research, or local-only compliance, run:

```bash
walter ai configure --profile mixed
walter ai status
```

See [`ai-capability-profiles.md`](ai-capability-profiles.md) for Claude-only,
Codex-only, Gemini-only, local-only, and mixed routing profiles.

---

## Cost tiers

Choose the alias that matches the task's cost/quality trade-off.

### Cheap — fast, low-cost

| Alias | Provider model | Notes |
|---|---|---|
| `haiku` | claude-haiku-3-5 | Fastest Anthropic; good for classification, routing |
| `gpt-4o-mini` | gpt-4o-mini | OpenAI budget option |
| `gpt-3.5-turbo` | gpt-3.5-turbo | Legacy, cheapest OpenAI |
| `gemini-2.5-flash` | gemini-2.5-flash-preview | Google budget option |
| `llama-3.3-70b` | groq/llama-3.3-70b-versatile | Free tier on Groq; very fast |
| `gemma-9b` | groq/gemma2-9b-it | Smallest Groq option |
| `deepseek-chat` | deepseek/deepseek-chat | Extremely cost-effective |
| `command-r` | cohere/command-r | Cohere budget; RAG-tuned |
| `mixtral-8x7b` | groq/mixtral-8x7b-32768 | Long context on Groq |

### Reasoning — high-quality, higher cost

| Alias | Provider model | Notes |
|---|---|---|
| `opus` | claude-opus-4-5 | Highest-quality Anthropic |
| `sonnet` | claude-sonnet-4-5 | Default for most agent tasks |
| `o3-mini` | o3-mini | OpenAI compact reasoning |
| `o1-preview` | o1-preview | OpenAI full reasoning |
| `gpt-4-turbo` | gpt-4-turbo | Older GPT-4, good for structured output |
| `gemini-2.5-pro` | gemini-2.5-pro-preview | Google top-tier |
| `deepseek-reasoner` | deepseek/deepseek-reasoner | DeepSeek chain-of-thought |
| `sonar-pro` | perplexity/sonar-pro | Search-grounded, reasoning quality |
| `grok-3` | xai/grok-3 | xAI flagship |
| `command-r-plus` | cohere/command-r-plus | Best Cohere; RAG + long context |

### Local — zero egress, privacy-safe

| Alias | Provider model | Notes |
|---|---|---|
| `walter-llm-local` | ollama/llama3.1 | Hardcoded to llama3.1. To change, edit `setup/litellm/config.yaml` and restart the LiteLLM container |
| `walter-llm-vllm` | openai/walter-vllm | GPU-accelerated vLLM. The loaded model is configured on the vLLM process, not via LiteLLM |
| `walter-embed` | ollama/nomic-embed-text | Embeddings; required by Phase M RAG |

---

## Privacy tier rules

**PHI-tagged tasks MUST route to `walter-llm-local`.**

The `medical-data-compliance` skill enforces this. Any agent processing data
tagged with `medical/*` or matching PHI patterns must:

1. Use alias `walter-llm-local` (or `walter-llm-vllm` if the local GPU server is up).
2. Never call any external API alias (`sonnet`, `gpt`, `gemini`, etc.).
3. Log the routing decision with `[LOCAL-ROUTED]` prefix so audits can verify.

This applies to any health data in your personal context (medical records, fitness
metrics tagged PHI, etc.) and any patient data in clinical contexts. There are no
exceptions for "just a summary" or "it's anonymized" — if you're not certain it's
fully de-identified, route locally.

Other sensitive-but-not-PHI workloads (legal-privileged notes, financial data)
should prefer `walter-llm-local` but are not hard-blocked on external routes.

---

## How to add a new provider

Three steps:

### 1. Edit `setup/litellm/config.yaml`

Add an entry under the appropriate tier section:

```yaml
  # ===========================================================================
  # Tier N — ProviderName (requires PROVIDER_API_KEY)
  # Docs: https://docs.litellm.ai/docs/providers/providername
  # ===========================================================================
  - model_name: my-alias
    litellm_params:
      model: provider/model-slug
      api_key: os.environ/PROVIDER_API_KEY
```

Rules:
- `model_name` must be unique across the entire `model_list`.
- `api_key` must use `os.environ/` reference — never hardcode.
- For local/Ollama providers without auth, omit `api_key` and set `api_base` instead.
- For **Vertex AI**, omit `api_key` entirely. Auth flows through ADC: set
  `GOOGLE_APPLICATION_CREDENTIALS` to a service-account JSON file path.
  LiteLLM picks it up automatically via the Google auth library.
- Add a header comment block documenting the required env var(s).

### 2. Edit `.env.example`

Add a commented slot in the `=== Additional LiteLLM-supported providers ===`
section:

```bash
# ProviderName (short description)
# PROVIDER_API_KEY=...
```

### 3. Restart LiteLLM

```bash
# Via Docker Compose (typical setup)
docker compose -f setup/docker-compose.litellm.yml restart litellm

# Or, if running standalone
litellm --config setup/litellm/config.yaml --port 4000
```

The new alias is immediately available to all agents after restart. No agent
code changes are required.

---

## Validation

The bats test suite at `tests/litellm/config-validation.bats` validates:

- YAML parses cleanly
- All `model_name` aliases are unique
- No hardcoded API keys (all use `os.environ/`)
- `walter-embed` entry exists
- At least 20 model entries total

Run locally with:

```bash
bats tests/litellm/config-validation.bats
```
