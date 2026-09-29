# Spec: codex-router-secondary-account

**Status**: implemented (codifies a change hot-applied on 2026-09-28)
**Rigor**: small (IaC reconciliation; no auth/crypto/money code paths)

## Problem

On 2026-09-27 (~23:00 UTC) the ChatGPT account behind `chatgpt-codex-router`
hit its weekly usage limit (reset 2026-10-03). Every Codex-backed LiteLLM group
had a single deployment on that router, so every Codex call returned 502.

On 2026-09-28 the operator hot-applied a fix on both hosts (`walter-core`,
`walter-aux`): a second router, `chatgpt-codex-router-solx`, running the same
bridge against a second account's Codex home (`~/.codex-solx`), plus a twin
LiteLLM deployment for every deployment on the first router. On `walter-aux`
the LiteLLM cooldown settings already present on `walter-core` were also added.
The host configs carry literal router keys and are not in git, so the next
redeploy from the repo would drop the fix.

## Decisions

- The second router is a **compose override**
  (`chatgpt-codex-router/docker-compose.solx.yml`), not a second service in the
  base file, so single-account installs keep working without a second key.
  Enabled with `COMPOSE_FILE=docker-compose.yml:docker-compose.solx.yml`.
- The container name stays `chatgpt-codex-router-solx` because LiteLLM reaches
  it by Docker DNS name and the live hosts already use it.
- Its key is a **separate secret**, `CCR_SOLX_APIKEY`, injected into the
  container as `CCR_APIKEY` and referenced by LiteLLM as
  `os.environ/CCR_SOLX_APIKEY`. No literal keys in the repo.
- Host debug port `127.0.0.1:1459` (matches the live hosts; inside the
  `1450-1499` AI-router range).
- LiteLLM `router_settings` gets `allowed_fails: 3`, `cooldown_time: 300` and
  an `allowed_fails_policy` that ignores content-policy/bad-request errors, so
  an exhausted account leaves rotation instead of failing every Nth request.
- The watchdog probes each account router directly and **alerts only**:
  restarting a router does not fix a usage limit, and the gateway probe cannot
  see one exhausted account while the other still serves.

## Acceptance criteria

- AC-1: `docker-compose.solx.yml` defines `chatgpt-codex-router-solx` with its
  own fail-loud key, the second Codex home, `127.0.0.1:1459:1456`, the LiteLLM
  network, router resource limits and startup probes; base + override render.
- AC-2: `ports.tsv` registers `chatgpt-codex-router-solx` on 1459.
- AC-3: every deployment on `chatgpt-codex-router` in the walter-host LiteLLM
  config has a same-name, same-model twin on `chatgpt-codex-router-solx` using
  `os.environ/CCR_SOLX_APIKEY`; no literal `api_key`; LiteLLM compose passes
  `CCR_SOLX_APIKEY` through.
- AC-4: `router_settings` contains the cooldown settings above.
- AC-5: `ai-stack-watchdog.sh` probes both routers directly, skips absent
  containers, never restarts on that probe, and keeps the router key inside the
  container.
- AC-6: the router RUNBOOK documents enabling the second account, checking
  which account a router uses, and diagnosing account exhaustion; the env
  template documents `CCR_SOLX_APIKEY`.

Tests: `tests/services/chatgpt-codex-router-secondary.bats`.

## Non-goals

- Reconciling unrelated drift between the repo and the live hosts (listed in
  the PR instead).
- Deploying, restarting or editing anything on the hosts.
- Project-specific LiteLLM groups that exist only on the live hosts.
