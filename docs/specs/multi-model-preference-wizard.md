# Multi-Model Preference Routing — spec

**Status**: Partially implemented (core routing shipped; full LiteLLM usage analytics can iterate)
**Issue**: #24 (`[FEAT] -OPERATIONS- multi-model preference wizard + domain-routing workflow`)
**Tier**: 2 (high-value feature; operator-flagged priority)
**Target release**: **v0.4.1** (depends on v0.4.0 P1 hardening landing + OpenRouter merged — both in flight)
**Depends on**: PR #63 (OpenRouter routes merged into main — done)

## Problem

Walter-OS orchestrates multiple AI models (Claude, Codex/GPT, Gemini, Ollama-local, OpenRouter-routed) but the routing is **implicit and hardcoded per skill**. Operators have no way to declare:

- "Use Codex for backend / security review, Claude for frontend / design, Gemini for content brainstorm."
- "Default to Sonnet for most things but Opus for hard reasoning."
- "Never send PHI to Anthropic — Ollama local only."
- "I prefer Codex's voice for refactoring suggestions."

The 3-round review policy already proves multi-model orchestration matters: Codex R2 has caught bugs Copilot R1 missed in PRs #58, #67, and the P0-06 review chain. Yet today, every other skill picks its model based on a hardcoded `llm_invoke` call in `scripts/agents/lib/llm.sh` or by reading `WALTER_MODEL_DEFAULT` blindly.

The operator-stated principle:

> "Codex no es tu competencia… múltiples agentes son un equipo por más que sean competencia entre empresas. Así como tú tienes mejor criterio estético y desarrollo del frontend, Codex es mejor en backend y security."

Walter-OS's value isn't picking the "best" model. It's **orchestrating each model's strength for the right task** based on the operator's declared preferences.

## Non-goals

- Replacing LiteLLM as the gateway. This spec is about ROUTING preferences ABOVE LiteLLM, not its replacement.
- A full vendor-grade A/B testing harness. Operators choose; we route.
- Cost optimization as the primary lever. Cost matters but `ai-spend-tripwire` already covers it.
- Auto-selecting models based on "best benchmark score for task type." That's a research project; we ship operator preference today.
- Forcing every skill to consult preferences. Some skills (`nanobanana` → Gemini vision) are model-specific by design.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Preferences live in `~/.config/walter-os/overlay/personal.env`** with `WALTER_MODEL_*` env var keys. `walter ai configure` is the operator-facing command for declaring available AI runtimes and router preferences. | Same overlay surface that ADR 0013 + the new env-allowlist parser (P1-09) already use. No new config surface to maintain. |
| D-2 | **Six domain preference axes plus `DEFAULT`**: `BACKEND_REVIEW`, `FRONTEND`, `LONGFORM`, `QUICK_REFACTOR`, `PHI`, `BRAINSTORM`, plus a `DEFAULT` fallback. | Matches the bullet list in #24 (operator's design). Adding more axes later is backward-compatible (new env vars; old code keeps reading `DEFAULT`). |
| D-3 | **Values are runtime/model aliases** such as `codex`, `claude`, `gemini`, and `local-ollama`. `walter ai configure` persists router preferences to `~/.config/walter-os/overlay/personal.env`; `providers.yaml` and the LiteLLM config remain gateway/provider selection surfaces. | Capability declaration is separate from gateway alias configuration, so operators can use Claude-only, Codex-only, Gemini-only, local-only, or mixed installs without pretending every runtime is available. |
| D-4 | **Comma-separated parallel mode**: `WALTER_MODEL_BACKEND_REVIEW=codex,claude` means "dispatch to Codex AND Claude in parallel, surface both outputs." Maps to the 3-round review pattern. Implementation note: `llm_invoke` today accepts a single model alias; the per-skill resolver (D-7 — `walter_model_for`) is responsible for parsing the comma-list and invoking `llm_invoke` N times in parallel, then merging the outputs. `llm_invoke` itself does NOT change. | Single-value = single model; comma-list = team. The plan should call out the resolver's parallel-fanout pattern explicitly. |
| D-5 | **PHI is an override, not a preference.** `WALTER_MODEL_PHI=local-ollama` (the default) is a HARD cap — any skill that detects PHI tags refuses non-local models regardless of other settings. The current `skills/medical-data-compliance/SKILL.md` describes the POLICY but does not implement the env-driven routing check; this spec adds the implementation to the new `walter_model_for` resolver (D-7) so PHI tasks route locally regardless of other env vars. | The skill defines the rule; this spec wires it up so the rule has teeth at the routing layer. |
| D-6 | **`walter ai configure`** writes both availability metadata and the managed `WALTER_MODEL_*` preference block. The overlay scaffold can point operators to this command instead of owning a separate wizard. | Keeps runtime declaration re-run-friendly and avoids duplicating routing prompts across setup scripts. |
| D-7 | **Per-skill resolution function `walter_model_for <domain>`** lives in `scripts/walter/lib/model-router.sh` (new) and reads the env vars. Skills consult it instead of hardcoding. | Single point of truth. Easy to test. Skills don't all need to be rewritten at once. |
| D-8 | **No HARD-LOCK to any model.** Operator can always override any skill via env var on a per-invocation basis (`WALTER_MODEL_OVERRIDE=opus walter ask ...`). | Per #24 AC-final bullet. Critical to maintain operator autonomy. |
| D-9 | **`walter status --models`** subcommand reports usage breakdown per model + per domain + cost attribution. Composes with `ai-spend-tripwire`. | Observability is part of the feature. Without it, "did my preference actually take effect?" is unanswerable. |

## Acceptance criteria

### AC-1 — Preference env vars + parser
- [x] `scripts/walter/lib/model-router.sh` (new): exposes `walter_model_for <domain>` and `walter_model_phi_lock` functions.
- [x] `WALTER_ENV_ALLOWLIST` in `scripts/walter/lib/env-loader.sh` (from P1-09) extended to include `WALTER_MODEL_BACKEND_REVIEW`, `WALTER_MODEL_FRONTEND`, `WALTER_MODEL_LONGFORM`, `WALTER_MODEL_QUICK_REFACTOR`, `WALTER_MODEL_PHI`, `WALTER_MODEL_BRAINSTORM`, `WALTER_MODEL_DEFAULT`, `WALTER_MODEL_OVERRIDE`.
- [ ] Default values when env vars are unset:
  - `BACKEND_REVIEW`: `codex`
  - `FRONTEND`: `claude`
  - `LONGFORM`: `claude`
  - `QUICK_REFACTOR`: `codex`
  - `PHI`: `local-ollama` (hard override, never overridden)
  - `BRAINSTORM`: `claude,codex` (parallel by default)
  - `DEFAULT`: `claude`
- [x] bats coverage in `tests/walter/model-router.bats` for: unset → default; single value; comma-separated parallel; `WALTER_MODEL_OVERRIDE` always wins (except PHI).

### AC-2 — Profile-based configure command
- [x] `walter ai configure` provides profile-based model preference setup with sensible defaults.
- [x] Output written to `~/.config/walter-os/overlay/personal.env` as `WALTER_MODEL_<AXIS>=<value>` lines. Existing unrelated values are preserved.
- [x] Command is non-interactive when stdin is not a TTY (CI / automated bootstrap). Falls back to defaults.
- [x] `contexts/_examples/personal.env.example` documents all 7 vars with the recommended values and comments.

### AC-3 — Update 5 existing skills to consult preferences
Each skill below now reads `walter_model_for <its-domain>` and dispatches accordingly. Existing hardcoded `llm_invoke "$AGENT" "$MODEL"` calls replaced.

- [ ] `skills/pr-review/SKILL.md` — routes by changed-file mix: mostly `*.tsx`/`*.jsx`/`*.css` → frontend pref; mostly `*.go`/`*.rs`/`hooks/*.sh`/`scripts/agents/*.sh` → backend pref; mixed → both in parallel.
- [x] `skills/frontend-quality/SKILL.md` — reads `WALTER_MODEL_FRONTEND`.
- [x] `skills/web-security-baseline/SKILL.md` — reads `WALTER_MODEL_BACKEND_REVIEW`.
- [x] `agents/architect.md` — uses brainstorm routing for multi-model planning.
- [x] `skills/content-writer/SKILL.md` (if shipped — defer if not) — reads `WALTER_MODEL_LONGFORM`.

### AC-4 — Review-policy YAML for 3-round workflow
- [x] `contexts/_examples/review-policy.yml.example` (new) documents the schema:
  ```yaml
  default_review_flow:
    r1: copilot
    r2: codex
    r3: collaborative
  per_domain:
    frontend:
      r1: copilot
      r2: claude
      r3: collaborative
    security:
      r1: copilot
      r2: codex
      r3: claude
  ```
- [x] `commands/pr.md` updated to route non-Copilot review rounds through model-router preferences.
- [x] bats test in `tests/walter/review-policy.bats` asserts the example file declares per-domain routing.

### AC-5 — `walter-os status --models` subcommand

Note on the command name: the current repo exposes the audit/spend
report at `walter-os status` (in `bin/walter-os`); `walter status`
is a separate frontend in `bin/walter`. This spec adds the
`--models` flag to `walter-os status` specifically so the existing
audit/spend plumbing flows through one frontend. The `walter`
wrapper can forward unknown subcommands to `walter-os` later if the
operator wants a single entry point; that's out of scope here.

- [x] `bin/walter-os` `cmd_status` gains a `--models` flag that reports effective routing.
- [x] `scripts/agents/lib/llm.sh` emits `metadata.domain` for future usage attribution.
- [ ] Full LiteLLM Postgres usage analytics remain a follow-up:
  - Calls per model in the last 24h / 7d / 30d (selectable)
  - Calls per `domain` tag.
  - Cost per model (USD, attribution via `walter-os spend report` plumbing)
  - Historical domain/model drift checks
- [ ] Output format: same table style as `walter-os status` (text by default; `--json` flag for scripting). JSON output remains a follow-up candidate.

### AC-6 — Operator-facing docs
- [x] `docs/operational/multi-model-routing.md` (new) explains the philosophy + the routing matrix + the override hierarchy.
- [x] README entry once shipped.
- [x] CHANGELOG entry under `[Unreleased]` → `Added`.

### AC-7 — Backward compatibility + safety
- [x] All existing skills that do NOT consult `walter_model_for` continue to work (they just use the hardcoded `MODEL` they always did).
- [x] No skill HARD-LOCKED to a model — `WALTER_MODEL_OVERRIDE` always wins (except `PHI` lock).
- [x] Migration note in CHANGELOG for operators upgrading: no action required; existing setups continue to work.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Operator overlay                                               │
│  ~/.config/walter-os/overlay/personal.env                       │
│    WALTER_MODEL_BACKEND_REVIEW=codex                            │
│    WALTER_MODEL_FRONTEND=claude                                 │
│    WALTER_MODEL_LONGFORM=claude                                 │
│    WALTER_MODEL_PHI=local-ollama       ← hard lock              │
│    WALTER_MODEL_BRAINSTORM=claude,codex ← parallel              │
│    WALTER_MODEL_DEFAULT=claude                                  │
└────────────────────────────────┬────────────────────────────────┘
                                 │ loaded via env-loader.sh allowlist
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/walter/lib/model-router.sh                             │
│    walter_model_for <domain> → echoes resolved model name(s)    │
│    walter_model_phi_lock     → echoes the PHI-locked model      │
└────────────────────────────────┬────────────────────────────────┘
                                 │ consulted by
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  Skills (pr-review, frontend-quality, web-security-baseline,    │
│  architect, content-writer, …)                                  │
│    MODEL=$(walter_model_for backend_review)                     │
│    llm_invoke "$AGENT" "$MODEL" …                               │
└────────────────────────────────┬────────────────────────────────┘
                                 │ via existing LiteLLM gateway
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  LiteLLM (setup/walter-host/services/litellm/config.yaml)       │
│    routes "codex" → openai/codex-cli                            │
│    routes "claude" → anthropic/claude-sonnet-4-5                │
│    routes "openrouter/claude" → openrouter/anthropic/claude...  │
│    routes "local-ollama" → ollama/llama-3.x (Phase L homelab)   │
└─────────────────────────────────────────────────────────────────┘
```

## Threat model + safety

- **PHI lock cannot be overridden.** `WALTER_MODEL_OVERRIDE` is explicitly ignored when `medical-data-compliance` skill detects a PHI tag.
- **Operator env injection** (#34 P1-06) — `WALTER_MODEL_*` vars go through the `env-allowlist.txt` parser, so an attacker with arbitrary `~/.config/walter-os/env` write access can only set values for keys we explicitly listed. They can't add new model routes.
- **Cost attribution** — every `llm_invoke` already tags `model_alias` in LiteLLM metadata; `walter-os spend report --by-agent` (existing) and `--by-model` (new) make routing decisions auditable.

## Dependencies / ordering

- **AC-1 (env vars + parser)** must ship first. Other ACs build on it.
- **AC-2 (wizard)** can ship in parallel with AC-3 (skill updates) — no shared file.
- **AC-3 (5 skills)** is the bulk of the work. Each skill is a separate PR following the 3-round review.
- **AC-4 (review-policy YAML)** depends on AC-1.
- **AC-5 (`status --models`)** depends on AC-3 (needs at least one skill to emit `domain` tags).
- **AC-6 + AC-7** are the closing PR.

Recommended PR ordering (8 PRs in v0.4.1):

1. AC-1 — env vars + `model-router.sh` lib + bats
2. AC-2 — `setup/personal-overlay-init.sh` wizard + `.env.example`
3. AC-3a — `pr-review` skill routes by file mix
4. AC-3b — `frontend-quality`, `web-security-baseline`, `architect` skills route by domain
5. AC-3c — `content-writer` (defer if skill not yet shipped)
6. AC-4 — review-policy YAML + `commands/pr.md` rewiring
7. AC-5 — `walter status --models` subcommand
8. AC-6 + AC-7 — docs + CHANGELOG + migration note

Each PR is small (≤200 LOC), runs the 3-round review, and references this spec.

## Out of scope

- **Local Ollama wiring (`local-ollama` model alias).** Requires Phase L homelab node + LiteLLM `ollama/*` config block. Tracked in `docs/specs/local-llm-node.md`.
- **Auto-suggest preference based on operator history.** Future feature; not v0.4.1.
- **Per-repo overrides via `walter-os.toml`.** Could ship later; v0.4.1 stays at operator-global level.
- **GUI for editing preferences.** Control Tower (Phase V) is the natural home; not v0.4.1.

## Open questions for the operator

1. **Should `WALTER_MODEL_OVERRIDE` apply globally to every domain, or only when no per-domain pref matches?** Default proposed: applies globally except PHI lock.
2. **Should `walter status --models` show counts only, or also a "drift" alert when actual usage diverges from declared preference?** Default proposed: counts only in v0.4.1; drift alerting in a follow-up.
3. **Should the wizard offer a "use sensible defaults — skip" option for first-time operators?** Default proposed: yes, with the defaults from AC-1.

## Refs

- Issue #24
- Operator-stated principle (Spanish): "Codex no es tu competencia… múltiples agentes son un equipo"
- `docs/specs/p1-hardening-epic.md` AC-6 (env-allowlist parser — dependency)
- `setup/walter-host/services/litellm/config.yaml` — LiteLLM model catalogue (post-#63 OpenRouter merge)
- `scripts/agents/lib/llm.sh` — current `llm_invoke` implementation
