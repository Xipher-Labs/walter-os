# Walter-Bridge — LiteLLM model coverage expansion

> **Status**: APPROVED for v0.2.0-walter-oss (operator override — orchestrator-produced spec)
> **Owner**: the operator
> **Created**: 2026-05-11

---

## Problem

`setup/litellm/config.yaml` currently exposes only 5 model aliases (Anthropic Sonnet/Opus/Haiku, OpenAI GPT, Google Gemini). LiteLLM supports 100+ providers — Walter-OS OSS users should get a comprehensive provider matrix out-of-the-box, with each provider gracefully disabled when its env var is unset.

## Non-goals

- Auto-detecting which providers the operator has API keys for (the wizard W-4 handles that)
- Per-agent model routing logic (lives in `scripts/agents/lib/llm.sh`, not in this spec)
- Cost attribution beyond what LiteLLM already provides
- Multi-tenant model routing (defer v0.3.0)

## Decisions

### Stack architecture
- All routing through LiteLLM gateway (`setup/litellm/config.yaml`)
- Each model entry has 3 fields: `model_name` (short alias), `litellm_params.model` (canonical provider/model), `litellm_params.api_key` (env-var ref)
- Providers grouped by header comments documenting required env vars
- Master key via `LITELLM_MASTER_KEY` env var (no hardcoded secrets)

### Provider tiers

**Tier 1 — common public APIs** (always documented):
- Anthropic, OpenAI, Google Gemini, Groq, DeepSeek, Mistral, Cohere

**Tier 2 — enterprise / specialized**:
- Azure OpenAI, AWS Bedrock, Google Vertex AI, xAI Grok, Perplexity, Together AI, DeepInfra, Replicate

**Tier 3 — local**:
- Ollama, vLLM, walter-embed (nomic-embed-text via Ollama for Phase M)

## Acceptance criteria

- [AC-1] `setup/litellm/config.yaml` contains ≥20 model entries (was 5) covering all 3 tiers
- [AC-2] Every model entry uses `os.environ/<PROVIDER>_API_KEY` (no hardcoded keys)
- [AC-3] Provider sections grouped + header comments document required env vars
- [AC-4] `walter-embed` alias points to `ollama/nomic-embed-text` (Phase M requirement)
- [AC-5] `.env.example` has commented env-var slots for every provider added
- [AC-6] `.env.example` references `https://docs.litellm.ai/docs/providers` for full provider list
- [AC-7] Bats test `tests/litellm/config-validation.bats` verifies:
  - YAML parses cleanly
  - All `model_name` aliases are unique
  - No hardcoded API keys (greps for `api_key:` literal values without `os.environ/`)
  - `walter-embed` entry exists
- [AC-8] New `docs/operational/litellm-model-selection.md` documents:
  - Default routing convention (agent invokes by alias)
  - Cost tiers (cheap / reasoning / local)
  - Privacy tier (PHI → walter-llm-local mandatory)

## Test plan

- YAML parse via `python3 -c "import yaml; yaml.safe_load(open('setup/litellm/config.yaml'))"`
- Alias uniqueness check via `yq '[.model_list[].model_name] | length == ([.model_list[].model_name] | unique | length)'`
- Hardcoded-key scan: `grep -nE '^\s*api_key:\s*["\047]?(?!os\.environ)' setup/litellm/config.yaml` must return no matches
- walter-embed presence: `yq '.model_list[].model_name | select(. == "walter-embed")'`

## Files affected

- `setup/litellm/config.yaml` (expand)
- `.env.example` (add provider slots)
- `tests/litellm/config-validation.bats` (new)
- `docs/operational/litellm-model-selection.md` (new)
