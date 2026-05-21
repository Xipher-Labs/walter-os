# P2 Security Hardening Epic — spec

**Status**: ready for `/write-plan` after operator approval
**Audit refs**: `docs/operational/security-audit-2026-05-11.md` P2-01 through P2-08
**Target release**: **v0.5.0** (after v0.4.0 P1 epic closes)
**Depends on**: v0.4.0 P1 closures merged. The companion P1 epic spec is in PR #65 (`docs/specs/p1-hardening-epic.md`) and may not yet be on `main` when this spec is read.

## Problem

The 2026-05-11 audit identified 8 P2-severity findings (CVSS 3.0–6.0). Lower-impact than P0/P1, but they form the residual tax on the "shippable to security-conscious adopters" bar. Mostly:

- **Pattern hardening**: small classes of edge-case bypass in existing gates (P2-01 eval, P2-04 stderr-injection, P2-08 SQL pattern variants).
- **Network surface review**: `:0.0.0.0` binds that should be either localhost-only or documented (P2-02, P2-03).
- **Outbound LLM leakage**: a Grafana plugin that talks to Grafana Cloud's LLM by default (P2-05).
- **Coverage gaps in existing redactors**: missing Hetzner / Infisical / Vercel / Cloudflare token patterns (P2-06).
- **Audit no-ops** that should be actual logic (P2-07).

Closing all 8 lifts Walter-OS from "audit-clean for v0.4.0" to "audit-clean across all severity tiers". Useful before any external audit / OpenSSF Silver Badge filing.

## Non-goals

- Re-litigating P0 / P1. Those are closed.
- Reproducing third-party CVEs (Syncthing TLS, Wireguard key management). We scope our exposure to *operator-controllable* config.
- Full OWASP-grade SQL injection coverage. The `approval-gate.sh` SQL pattern is defense-in-depth, not the primary control (the operator-supplied agent-approvals.yml is the primary control).

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **P2-01 `bootstrap.sh` eval**: replace `eval "$@"` with `run_args` (same pattern as `install.sh`). | Eliminates the eval path entirely. Same fix as P0-04. |
| D-2 | **P2-02 Syncthing :22000**: keep `0.0.0.0` (required for device-to-device sync) but DOCUMENT it explicitly in the security posture doc + add Cloudflare-Access-equivalent gating note. | Functional requirement; we document the trust boundary, not change it. |
| D-3 | **P2-03 Wireguard :51820/udp**: same as P2-02 — keep binding; harden documentation around `.env` file mode 600 + key rotation runbook. | Functional requirement. |
| D-4 | **P2-04 `detect-error.sh` stderr injection**: wrap stderr in `<TOOL_STDERR>…</TOOL_STDERR>` and stdout in `<TOOL_STDOUT>…</TOOL_STDOUT>` bounded markers (two-marker scheme so the operator can tell them apart in logs and the submodule's regex can target each independently). Same UNTRUSTED-DATA framing prefix as P0-06. | Same mitigation class as the lessons.md fix. The submodule already houses the fix; just extend to the third hook script. AC-3 below pins the two-marker scheme. |
| D-5 | **P2-05 Grafana Assistant plugin**: REMOVE from default install. Operator opts in via `WALTER_GRAFANA_ASSISTANT=1` env var. | Outbound LLM leakage from the observability layer (which has metric / log / alert content) is too easy to enable accidentally. Operator must opt in. |
| D-6 | **P2-06 redactor gaps**: extend `scripts/agent-secret-redactor.sh` to cover Hetzner (operator-config required: see AC-5), Infisical (`st\.v3\.[A-Za-z0-9_-]+` — prefix-anchored, low FP risk), Vercel (`vc_[A-Za-z0-9_-]+` — prefix-anchored, low FP risk), Cloudflare (operator-config: see AC-5), and `LITELLM_MASTER_KEY` (operator-defined pattern via `WALTER_LITELLM_MASTER_KEY_PATTERN` env var — see AC-5 for the canonical config-key name; do NOT read raw from `personal.env`). | Each missing token class is one bats test + one regex. **Avoid generic high-entropy regexes** like `^[a-f0-9]{64}$` (matches every sha256 digest the operator prints) or `^[A-Za-z0-9_-]{40,60}$` (matches half the legitimate base64 output) — they cause false-positive redactions that hide real diagnostic content. Use prefix-anchored or operator-config patterns instead. |
| D-7 | **P2-07 tool-definition drift**: implement `check_tool_definitions()` properly. Snapshot per-MCP tool defs to `~/.config/walter-os/mcp-snapshots/<server>-<date>.json`; diff against yesterday's snapshot; CRITICAL finding on change. | Closes the explicit Phase-2 TODO. Same pattern as the new `check_external_hooks()` from P1-07. |
| D-8 | **P2-08 SQL pattern variants**: extend the `approval-gate.sh` SQL regex to cover `DELETE\nFROM`, `delete from` (lowercase), and `DELETE/*…*/FROM` (comment-separator). | Three lines of regex + three bats tests. |

## Acceptance criteria

### AC-1 — P2-01 bootstrap.sh eval elimination
- [ ] `setup/bootstrap.sh` `run()` rewritten to use `run_args` (positional args, no `eval`).
- [ ] `run_args` helper hoisted to shared lib at `scripts/walter/lib/run-args.sh` (sourced by both `bootstrap.sh` and `install.sh`).
- [ ] `tests/install/bootstrap-no-eval.bats` (new) — greps `setup/bootstrap.sh` for `eval[[:space:]]` and asserts zero matches.

### AC-2 — P2-02/P2-03 network-surface documentation
- [ ] `docs/operational/network-exposure.md` (new) — lists every walter-host service with its port-binding policy:
  - **`0.0.0.0` (required)**: Syncthing 22000, Wireguard 51820/udp — with rationale + Cloudflare-Access NOT a replacement explanation
  - **`127.0.0.1` only**: every other service (n8n, plane, litellm, infisical, etc.)
  - **Behind Cloudflare Tunnel**: services accessible via `https://*.${WALTER_DOMAIN}`
- [ ] `tests/oss/network-exposure-doc.bats` — asserts every `compose.yml` port mapping is referenced in `network-exposure.md` (no undocumented `0.0.0.0` binds).

### AC-3 — P2-04 stderr/stdout bounded framing
- [ ] Submodule `Xipher-Labs/marchetto-agent-skills-fork` gains a sibling commit to the d1ad0e7 P0-06 fix: `detect-error.sh` wraps `stderr` / `stdout` content in `<TOOL_STDERR>…</TOOL_STDERR>` + `<TOOL_STDOUT>…</TOOL_STDOUT>` markers with the same "UNTRUSTED DATA" framing prefix.
- [ ] `external/marchetto-agent-skills` submodule pin bumped to the new SHA.
- [ ] `tests/hooks/learn-by-mistake-bounded-framing.bats` extended with 2 cases for `detect-error.sh`.

### AC-4 — P2-05 Grafana Assistant opt-in only
- [ ] `setup/walter-host/services/observability/compose.yml` — remove `GF_INSTALL_PLUGINS: "grafana-assistant-app"` from the default config.
- [ ] Add operator override: when `WALTER_GRAFANA_ASSISTANT=1` is set in `personal.env`, compose-override re-adds the plugin.
- [ ] `setup/walter-host/services/observability/README.md` (new section) explains the trade-off + Grafana-Cloud-LLM-leakage threat model.
- [ ] `tests/oss/services-grafana-no-assistant-by-default.bats` — asserts the plugin is NOT in the default compose.

### AC-5 — P2-06 redactor coverage
- [ ] `scripts/agent-secret-redactor.sh` adds patterns for:
  - Hetzner: operator-config pattern via `WALTER_HETZNER_TOKEN_PATTERN`
    env var (the raw "64-char hex" pattern would catch every sha256
    digest the operator prints — too noisy as a default). If unset,
    redactor leaves the token class unscanned.
  - Infisical: `st\.v3\.[A-Za-z0-9_-]{20,}` (prefix-anchored, low
    false-positive risk).
  - Vercel: `vc_[A-Za-z0-9_-]{20,}` (prefix-anchored).
  - Cloudflare: operator-config pattern via `WALTER_CLOUDFLARE_TOKEN_PATTERN`.
    Same rationale as Hetzner — `^[A-Za-z0-9_-]{40,60}$` would redact
    most legitimate base64 output (Postgres password hashes, JWT
    fragments, kubectl certs).
  - `LITELLM_MASTER_KEY` (length ≥ 32): pattern read from
    `WALTER_LITELLM_MASTER_KEY_PATTERN` env var (operator-defined regex,
    canonical config-key name — D-6 says the same; do NOT use a raw
    `LITELLM_MASTER_KEY` regex unless this env var is set).
- [ ] `tests/scripts/agent-secret-redactor.bats` extended with 5 cases
  (one per new pattern, plus 2 false-positive guards: a printed sha256
  digest should NOT be redacted when no `WALTER_HETZNER_TOKEN_PATTERN`
  is configured, and a JWT-shaped base64 segment should NOT be redacted
  by the Cloudflare scan when no `WALTER_CLOUDFLARE_TOKEN_PATTERN` is
  configured).

### AC-6 — P2-07 tool-definition drift detection
- [ ] `skills/daily-supply-chain-audit/scripts/audit.sh` `check_tool_definitions()` implemented:
  - For each MCP in `~/.claude/settings.json` `mcpServers`, query its tool list (`tools/list` JSON-RPC method via the existing `mcp-scanner` integration OR a direct stdio probe).
  - Hash the tool-name set + tool-description set → store to `~/.config/walter-os/mcp-snapshots/<server>-<date>.json`.
  - Diff vs yesterday's snapshot. CRITICAL finding `mcp-tool-shadowing` on any change.
- [ ] `walter-os baseline-mcp-tools` CLI subcommand for re-snapshotting after an intentional MCP version bump (same pattern as `baseline-external-hooks`).
- [ ] `tests/audit/mcp-tool-drift.bats` (new) — mock an MCP, snapshot, modify the tool list, assert CRITICAL finding.

### AC-7 — P2-08 SQL pattern variants
- [ ] `hooks/approval-gate.sh` `BLOCK_BASH_PATTERNS` SQL `DELETE FROM` regex extended to handle:
  - `DELETE[[:space:]\n]+FROM` (any whitespace including newline)
  - `delete from` (lowercase) — change to case-insensitive class `[Dd]`
  - `DELETE[[:space:]]*/\*.*\*/[[:space:]]*FROM` (SQL comment separator)
- [ ] `tests/hooks/approval-gate.bats` extended with 3 cases (newline, lowercase, comment-separator) covering each variant.

### AC-8 — Audit ledger + CHANGELOG
- [ ] `docs/operational/security-audit-2026-05-11.md` Status lines on P2-01..P2-08 with PR refs.
- [ ] Summary table: 6/6 P0, 9/9 P1, **8/8 P2** closed.
- [ ] `CHANGELOG.md` `[Unreleased]` (becoming `[0.5.0]`) → Security entries per AC.

## Recommended PR ordering

1. AC-5 — redactor coverage (smallest, self-contained, fast win)
2. AC-7 — SQL pattern variants (small, self-contained)
3. AC-1 — bootstrap.sh eval elimination + shared `run-args.sh` lib
4. AC-3 — submodule fork: stderr/stdout framing + submodule SHA bump
5. AC-4 — Grafana Assistant opt-in
6. AC-2 — network-exposure documentation
7. AC-6 — tool-definition drift detection (largest; pairs with `walter-os baseline-mcp-tools`)
8. AC-8 — audit ledger + CHANGELOG sweep (closing PR)

## Threat model recap

| Finding | Adversary capability needed | Blast radius if exploited |
|---|---|---|
| P2-01 | Compromise of `bootstrap.sh` env in a way `install.sh` doesn't already protect | Shell injection during install |
| P2-02 | Syncthing TLS vulnerability + direct internet access | Device handshake bypass; sync any folder |
| P2-03 | Wireguard pre-shared-key leak | Unauthorized VPN access |
| P2-04 | Agent runs a command whose stderr contains adversarial markup | systemMessage injection at PostToolUse |
| P2-05 | Operator runs Grafana Assistant query containing internal data | Leakage to Grafana Cloud LLM (metric / log / alert content) |
| P2-06 | Agent inadvertently echoes a Hetzner/Infisical/Vercel/Cloudflare token | Token lands in Plane comment / audit log unredacted |
| P2-07 | Compromised MCP swaps tool names with another MCP | Tool-shadowing → agent calls wrong tool with privileged scope |
| P2-08 | Agent generates `DELETE\nFROM users` (newline variant) | Bypass approval-gate, mass-deletion |

Closing all 8 brings cost-to-compromise across the residual tier up to "multi-step + lateral-movement" same as the P1 closure.

## Out of scope

- Reproducing Syncthing / Wireguard upstream CVEs (P2-02, P2-03). We harden our config + docs, not their code.
- Full SQL injection coverage. Walter-OS's primary SQL gate is operator-supplied agent-approvals.yml; the regex is defense-in-depth.
- Telemetry opt-out for Grafana Cloud (P2-05). Removing the plugin entirely from default is the floor; opt-in flag is the ceiling.

## Open questions for the operator

1. **P2-02/P2-03 documentation vs hardening**: ship the network-exposure doc only (proposal), or ALSO add an iptables/`ufw` rule generator that restricts `0.0.0.0` binds to specific source IPs? Proposal: doc only for v0.5.0; iptables wrapper as a v0.6.0 follow-up if operator wants tighter control.
2. **P2-05 Grafana Assistant removal**: hard-remove from default (proposal) or keep with a warning banner? Proposal: hard-remove; opt-in is the right default for outbound-LLM tooling.
3. **P2-07 MCP tool-list probe method**: use the `mcp-scanner` integration (existing dep) OR direct stdio JSON-RPC (no new dep)? Proposal: direct stdio (smaller surface, no new dep), with fallback to mcp-scanner if stdio probe fails.

## Refs

- Issue #34 (Walter-OS risk assessment epic — this closes its P2 lines)
- `docs/operational/security-audit-2026-05-11.md` P2-01..P2-08
- `docs/specs/p1-hardening-epic.md` (the v0.4.0 P1 epic this follows)
- `docs/specs/p0-06-lessons-sanitization.md` (the bounded-section framing pattern AC-3 reuses)
- `docs/specs/oss-trust-roadmap.md` (the umbrella this P2 work composes with)
