# P1 Security Hardening Epic — spec

**Status**: ready for `/write-plan` after operator approval
**Audit refs**: `docs/operational/security-audit-2026-05-11.md` P1-01 through P1-09
**Tracking issue**: #34 (Walter-OS risk assessment epic)
**Target**: **v0.4.0** (rolled into the same release as the founder-skills bundle and the workflow consolidation already in main).
**Prior P0 closure**: 6/6 P0 findings closed (P0-01..P0-05 fixed in `main` ahead of v0.3.0; P0-06 closed by `fix/p0-06-lessons-bounded-framing`). P1-04 and P1-08 are already closed by the same fixes that closed P0-05 and P0-06 respectively. **7 P1 findings remain in scope of this epic.**

## Problem

The 2026-05-11 audit identified 9 P1-severity findings (CVSS 5.0–8.1). Two were closed in earlier PRs (P1-04 via the syncthing-bootstrap extraction in PR #45; P1-08 via the bounded-section framing in PR #64). The other seven cluster into three failure modes that block adoption-readiness:

1. **Unpinned runtime dependencies** (P1-01, P1-02) — `latest` tags on `openclaw` npm + `minio` + Penpot + drawio + Plane + Homepage images. A malicious publish or a CVE-regressed point release lands on the next `docker compose pull` with no human in the loop.

2. **Auth surfaces with single-layer defense** (P1-03) — n8n's built-in auth is off; the only gate is Cloudflare Access. Any CF Tunnel bypass, CF Access misconfig, or cloudflared CVE unmasks an unauthenticated panel with credential vault and code-execution nodes.

3. **Fragile / overridable security-path components** (P1-05, P1-06, P1-07, P1-09) — approval-gate degrades silently when `yq` is missing; the standing-approvals YAML path is operator-overridable via env var; external submodule hooks live outside the `hook-checksums.json` integrity perimeter; `daily-audit-gate.sh` unconditionally sources `~/.config/walter-os/env`. Each one taken alone is "narrow"; together they chain into a pattern where an attacker who can write one file in `$HOME` can disable enforcement.

## Non-goals

- Re-litigating P0-01..P0-06 (closed).
- P2 findings (P2-01..P2-08) — separate epic; cleanup in v0.4.0 or v0.5.0 depending on operator scheduling.
- Adopting runtime sandboxing (#1 OSS trust roadmap) — too big for v0.4.0; lives in v0.5.0+.
- Rewriting `approval-gate.sh` from scratch. Each P1 fix is a surgical patch.
- Forking every upstream service to pin from scratch. We pin to the digest currently in use.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Pin all `:latest` and `:stable` tags to current sha256 digests across all walter-host services.** | Mirrors the PR #53 / #28 pattern already shipped for Penpot + drawio + Plane. Closes P1-01 and P1-02 in one wave. |
| D-2 | **Re-enable `N8N_BASIC_AUTH_ACTIVE: "true"` and require operators to set `N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD` in `secrets.env`.** | Two-layer auth (Cloudflare Access + n8n basic) is the minimum viable defense-in-depth for a panel with Execute Command nodes. |
| D-3 | **Treat `jq` and `yq` as hard dependencies of `approval-gate.sh`.** Block the hook with a clear "install jq / install yq" message when either is missing. `install.sh` preflight already checks `jq`; add `yq`. | Already pattern from P0-03 fix. P1-05 just extends it to `yq`. |
| D-4 | **Hard-code the standing-approvals YAML path** to `$HOME/.config/walter-os/agent-approvals.yml`. Provide a `WALTER_STANDING_APPROVALS_OVERRIDE` opt-in only when `WALTER_AGENT_ALLOW_OVERRIDE=1` is set in the same shell. | Removes the env-var-as-config-pointer footgun. The override flag exists for testing and is explicit. |
| D-5 | **Include `external/**/hooks/scripts/*.sh` in `hook-checksums.json` and the `audit.sh` `check_skill_scripts()` scan.** | Closes the audit-perimeter gap for external submodules. Compatible with the SHA-pinned submodules from P0-05. |
| D-6 | **Stop sourcing `~/.config/walter-os/env` unconditionally.** Replace with allowlist-key/value parser that only accepts `WALTER_OS_HOME`, `WALTER_CONFIG`, `WALTER_DOMAIN`, `WALTER_BRANCH_FLOW`, plus whatever else the operator overlay sources documentation says. | Removes the "any operator-writable file is now arbitrary code" pattern. |

## Acceptance criteria

### AC-1 — Image / package pinning (P1-01, P1-02)
- [ ] `setup/walter-host/services/openclaw/compose.yml` — `npm install -g openclaw@2026.X.Y` pinned to a specific version (latest stable at PR open). No `@latest`.
- [ ] `setup/walter-host/services/plane/compose.yml` — `minio/minio` pinned to `RELEASE.YYYY-MM-DDTHH-MM-SSZ@sha256:…`. Same for all other `:latest` / `:stable` / `makeplane/*:stable` tags in the file.
- [ ] `setup/walter-host/services/{penpot,drawio,homepage,n8n}/compose.yml` — every `image:` line is pinned to a sha256 digest.
- [ ] `tests/compose/pinned-digests.bats` (new) — bats test that greps all `setup/walter-host/services/**/compose.yml` for `:latest`, `:stable`, or missing digests; fails CI if any unpinned image appears.

### AC-2 — n8n auth (P1-03)
- [ ] `setup/walter-host/services/n8n/compose.yml` — `N8N_BASIC_AUTH_ACTIVE: "true"` with `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD` env vars wired through Infisical secrets.
- [ ] Operator-facing docs (`setup/walter-host/services/n8n/README.md`, new) explain the two-layer model: Cloudflare Access (perimeter) + n8n basic (defense in depth).
- [ ] `tests/oss/services-n8n-auth.bats` (new) — asserts the compose file has `N8N_BASIC_AUTH_ACTIVE` set to `"true"` (not `"false"`, not absent).

### AC-3 — approval-gate hard deps (P1-05)
- [ ] `hooks/approval-gate.sh` — when `yq` is absent, emit `{"decision":"block","reason":"approval-gate: yq missing — failing closed for safety. Install yq to proceed."}` and exit 0. Same pattern as the existing jq-missing path (P0-03 fix).
- [ ] `install.sh` preflight — add `yq` to the hard-dependency check alongside `jq`. Fail install with actionable instructions if missing.
- [ ] `tests/hooks/approval-gate.bats` — extend with cases that simulate `yq` missing and assert the block JSON shape.

### AC-4 — standing-approvals path lockdown (P1-06)
- [ ] `hooks/approval-gate.sh` — `STANDING_APPROVALS_FILE` no longer derived from `$WALTER_STANDING_APPROVALS`. Hardcoded to `$HOME/.config/walter-os/agent-approvals.yml`.
- [ ] Override path: `WALTER_STANDING_APPROVALS_OVERRIDE` only read when `WALTER_AGENT_ALLOW_OVERRIDE=1` is set in the same env. The override emits a `WARN` log line every time it's consulted.
- [ ] `tests/hooks/approval-gate.bats` — new case: setting `WALTER_STANDING_APPROVALS=/tmp/evil.yml` without the allow-override flag is ignored (the hardcoded path is used).

### AC-5 — external submodule hook integrity (P1-07)
- [ ] `hook-checksums.json` — extended schema that records sha256 of `external/**/hooks/scripts/*.sh` files at install time.
- [ ] `audit.sh` — `check_skill_scripts()` scope extended to `external/**`. New scan rule: any hook script whose checksum changed since install fires a CRITICAL audit finding.
- [ ] `install.sh` — populates the new checksum entries during `./install.sh --upgrade`.
- [ ] `tests/audit/hook-checksums-external.bats` — touches a file under `external/marchetto-agent-skills/skills/learn-by-mistake/hooks/scripts/`, runs `audit.sh`, asserts CRITICAL.

### AC-6 — `walter-os/env` integrity (P1-09)
- [ ] `hooks/daily-audit-gate.sh` — replace `[[ -f "${WALTER_CONFIG}/env" ]] && source "${WALTER_CONFIG}/env"` with `walter_env_load_allowlist()` that reads `KEY=VALUE` lines, rejects anything not in the allowlist (`WALTER_OS_HOME`, `WALTER_CONFIG`, `WALTER_DOMAIN`, `WALTER_BRANCH_FLOW`, `WALTER_TIMEZONE`), and never executes code from the file.
- [ ] Same parser used by `bin/walter`, `bin/walter-os`, and any other entry point that currently `source`s `$WALTER_CONFIG/env`. Single helper in `scripts/walter/lib/env-loader.sh`.
- [ ] `tests/hooks/env-allowlist.bats` — case 1: legitimate `WALTER_OS_HOME=/foo` is parsed; case 2: `ARBITRARY_VAR=baz` is ignored with a WARN; case 3: `WALTER_OS_HOME='$(rm -rf /)'` is parsed literally as a string, no eval.

### AC-7 — audit ledger + CHANGELOG (cross-cutting)
- [ ] `docs/operational/security-audit-2026-05-11.md` — `Status` line on each closed P1 (P1-01..P1-03, P1-05..P1-07, P1-09) with the PR ref. Summary table updated: 9/9 P1 closed (or 7/7 in scope after subtracting the two already-closed by P0 fixes).
- [ ] `CHANGELOG.md` — `[Unreleased] → Security` entry per AC.

## Out of scope

- P2-01..P2-08 — separate epic.
- Re-litigating P0-05 (submodule SHA pinning already in main).
- The "approval-gate.sh full rewrite" alternative (rejected: surgical patches are cheaper and ship faster).
- Service version upgrades. Pinning preserves the currently-deployed version; upgrades follow on a separate decision.

## Threat model (recap)

| Finding | Adversary capability needed | Blast radius if exploited |
|---|---|---|
| P1-01 | npm publish access to `openclaw` package | Code execution in container with OPENCLAW_GATEWAY_TOKEN + LiteLLM access |
| P1-02 | Operator runs `docker compose pull`; upstream pushes a regressed `:latest` | RCE / auth bypass in MinIO, Penpot, drawio, Plane, Homepage |
| P1-03 | Any CF Access misconfig, CF Tunnel bypass, or cloudflared CVE | Unauthenticated access to n8n credentials vault + Execute Command nodes |
| P1-05 | Local user removes/shadows `yq` | Standing-approvals path silently fails open (chained with P0-03 → full bypass; P0-03 is closed but P1-05 makes the chain re-emergeable) |
| P1-06 | Env-injection via compromised MCP / dotfile manager | Pointing approvals at attacker-controlled YAML → auto-approve every blocked op |
| P1-07 | Tampering with `external/**/hooks/scripts/*.sh` | Hooks execute at SessionStart / PostToolUse / PreCompact under operator credentials |
| P1-09 | Write access to `~/.config/walter-os/env` | Arbitrary shell at every Claude Code session start |

Closing all seven raises the cost-to-compromise from "single file write" to "multi-vector chain that crosses the Cloudflare boundary or compromises a pinned digest" — i.e., the level we want pre-OSS-1.0.

## Dependencies / ordering

- AC-1 and AC-2 can ship in parallel (no shared file).
- AC-3 must ship before or with AC-4 (both touch `approval-gate.sh`; same PR or AC-3 first).
- AC-5 and AC-6 are independent of each other.
- AC-7 is the closing PR — depends on AC-1..AC-6.

Recommended PR ordering:
1. AC-1 (image pinning, mostly mechanical)
2. AC-2 (n8n auth)
3. AC-3 + AC-4 in one PR (approval-gate.sh)
4. AC-5 (hook checksums external/)
5. AC-6 (env allowlist)
6. AC-7 (audit ledger + CHANGELOG sweep)

Each PR follows the standard 3-round review loop (Copilot R1 → Codex R2 → Round 3 only if needed). Each PR closes its specific AC bullets and references this spec.

## Refs

- `docs/operational/security-audit-2026-05-11.md` — full audit
- `docs/specs/p0-06-lessons-sanitization.md` — the P0-06 closure spec for cross-reference
- `docs/decisions/0013-solo-operator-merge-policy.md` — branch-flow rule the PRs follow
- Closes audit finding lines P1-01, P1-02, P1-03, P1-05, P1-06, P1-07, P1-09 in #34
