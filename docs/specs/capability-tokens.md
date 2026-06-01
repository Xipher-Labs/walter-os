# Filesystem capability tokens (OSS Trust A-2) — spec

**Status**: implementation in progress; see `oss-trust-runtime-implementation.plan.md`
**Parent**: OSS Trust roadmap Layer A item A-2 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83) (post-merge in-tree path: `docs/specs/oss-trust-roadmap.md`).
**Target release**: v0.5.0
**Depends on**:
- P1-09 env-allowlist parser — [PR #69](https://github.com/Xipher-Labs/walter-os/pull/69) (already merged into `main` for v0.4.0; the in-tree implementation lives at `scripts/walter/lib/env-loader.sh`).
- A-4 time-bounded sessions — [PR #87](https://github.com/Xipher-Labs/walter-os/pull/87) (post-merge: `docs/specs/time-bounded-sessions.md`). A-2 binds capability TTLs to the session TTL from A-4; A-4 must merge before A-2 implements.

## Problem

Today, when an agent invokes a tool, the tool inherits the full POSIX permissions of the operator's user. A `Bash` call to `cat ~/.ssh/id_ed25519` succeeds because the operator can read it; nothing in Walter-OS asks "should THIS tool, in THIS session, be allowed to read THIS path right now?"

The fix is per-tool capability tokens: short-lived, scoped, signed assertions about (operator, session, tool, allowed paths) that the hook chain checks before letting a sensitive operation proceed.

This is NOT a sandbox (that's A-3 — process isolation via nsjail/sandbox-exec). This is a CAP-LIKE policy layer ABOVE the existing approval-gate, so even when the gate would approve, the cap token must also vouch for it.

## Non-goals

- Replacing POSIX permissions. We compose; we don't replace.
- Per-syscall granularity. Tools are coarse-grained (Bash, Edit, Write, etc.); capabilities target tool-level allowed-paths + allowed-network.
- Hardware-token integration (YubiKey). Future work; v0.5.0 uses on-disk per-session Ed25519 key.
- Multi-operator capability delegation. Single operator per install.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Token format: PASETO v4 (public)**. Per-session Ed25519 keypair signs claims. | Capability-token format is PASETO v4 (per the OSS Trust roadmap `DEC-2` cross-cutting decision in `docs/specs/oss-trust-roadmap.md`). PASETO v4 closes the JWT alg-confusion / kid-confusion footguns by design. |
| D-2 | **Per-session keypair lifetime = session TTL** (from A-4 spec). Key generated when `session-state.sh` starts a new lazy session, deleted at session end. Capability tokens minted from this key. | Tying cap TTL to session TTL means session-end revokes everything. No long-lived secrets on disk. The A-4 implementation does not have a standalone `session-start.sh`; session creation happens inside `walter_session_touch`. |
| D-3 | **Token claims schema (PASETO v4 footer + payload)** — see `Token claims schema` block immediately below this table. | Minimum viable claim set. Operator can extend. |
| D-4 | **Minting via `walter-os cap mint <tool> --paths <glob>... --network <host>... --patterns <regex>... --duration <N>[smh]`**. File tools normally use `--paths`; Bash network tools use `--network`; Bash command-shape grants use `--patterns`. Duration accepts a Go-style suffixed number — `30s`, `45m`, `4h`, `8h` — and parses to an absolute expiry. The CLI rejects bare integers (`--duration 4` → error: "specify unit, e.g. 4h or 4m"). The YAML examples elsewhere in this spec (`duration: 4h` / `8h`) use the SAME syntax. Tokens land in `~/.config/walter-os/state/caps-<session>/cap-<nonce>.paseto`. | Operator-controlled. Default agents don't mint; they consume tokens minted by the operator out-of-band from the operator's own terminal, outside the Claude/Codex PreToolUse hook chain. Consistent duration syntax between CLI and YAML avoids the "minutes vs hours" implementer confusion. |
| D-5 | **Enforcement via `hooks/capability-check.sh`** PreToolUse hook. Reads the relevant tool call (path + command), looks up the latest valid token for that tool in the session, verifies the cap covers the requested operation. | Same chain as the other gates. |
| D-6 | **Fail-secure for capability high-tier operations.** If no valid token exists for an `Edit`/`Write`/`Bash` op AND the operation matches `capability-check.sh`'s hook-local high-tier classifier, the hook BLOCKS. That classifier covers protected paths, network-capable Bash commands, `gh pr review --approve`, and capability-system artifacts. Lower tiers fall through (cap is mandatory only for high-tier ops; low-tier ops are governed by the existing approval-gate alone). | Layered defense. v0.5.0 doesn't try to gate everything; only the dangerous tier, and the hook keeps a conservative classifier until approval-gate and capability-check share one policy library. |
| D-7 | **Operator-overridable per-skill defaults**. `~/.config/walter-os/overlay/skill-capabilities.yml` declares which skills auto-mint a default capability at session start (e.g. `nuclei-cli` auto-mints `tool=Bash, scope.patterns=[nuclei.*]`). | Skills the operator trusts get auto-caps; novel commands require explicit minting. |
| D-8 | **No transitive delegation in v0.5.0.** A subagent cannot mint a token from its parent's token. Operator is always in the loop. Enforcement: `walter-os cap mint` checks `WALTER_AGENT_CONTEXT` (set by `agents/run.sh` when a subagent invocation is active) and refuses with `error: cap minting blocked inside subagent context (caller=$WALTER_AGENT_CONTEXT). Operator must mint caps in the top-level session.` This blocks the "subagent runs `walter-os cap mint` via the Bash tool" escape vector. AC-2 below tests this path with a bats case. Approval-gate.sh's `CATEGORY_MIN_TIER` also classifies `walter-os cap mint` as `high` tier from the outset, and the approval gate treats capability-token minting as terminal for agent tool calls: Plane labels, standing approvals, and consensus mode cannot turn an agent-initiated mint into an allow. The operator approval path is deliberately out-of-band: run `walter-os cap mint ...` directly in the operator terminal, then let agents consume the resulting session token. | Capability-system 101: simple before clever. The subagent-mint guard plus approval-gate terminal block enforce "operator-in-the-loop" at code, not just policy. |

### Token claims schema (D-3 reference)

Embedded outside the decisions table because GitHub's Markdown
renderer mangles multi-line fenced code blocks inside table cells.

```json
{
  "iss": "walter-os",
  "sub": "<operator>",
  "session_id": "<uuid>",
  "tool": "Bash | Edit | Write | ...",
  "scope": {
    "paths": ["<glob>", "..."],
    "network": ["<host>", "..."],
    "patterns": ["<bash-regex>", "..."]
  },
  "iat": "<ISO-8601>",
  "exp": "<ISO-8601 ≤ session end>",
  "nonce": "<uuid>"
}
```

## Acceptance criteria

### AC-1 — PASETO v4 helper + key generation
- [x] `scripts/walter/lib/capability-token.sh` (new) — signs and verifies
  PASETO v4.public-compatible tokens using OpenSSL Ed25519, PAE
  canonicalization, Python stdlib base64/struct helpers, and `jq -S` JSON
  normalization. The originally proposed `paseto-cli` package is not currently
  available from PyPI, so Walter-OS keeps the PASETO v4.public wire format
  without adding an unavailable runtime dependency.
- [x] `install.sh --check` verifies `python3`, `jq`, and an ED25519-capable
  OpenSSL are present for token operations.
- [x] `scripts/walter/lib/session-state.sh` generates an Ed25519 keypair when a new session starts; stores the private key at `~/.config/walter-os/state/session-<uuid>.key` (mode 0600), stores the public key beside it, and initializes `caps-<session>/` (mode 0700).
- [x] `bats` coverage in `tests/walter/capability-token.bats` — sign + verify produces same claims.

### AC-2 — `walter-os cap` CLI
- [x] `walter-os cap mint <tool> --paths <glob>... --network <host>... --duration <N>[smh] [--patterns <regex>...]` — emits a PASETO v4 token to stdout AND writes to `~/.config/walter-os/state/caps-<session>/cap-<nonce>.paseto`. Duration syntax matches D-4 above (Go-style suffixed number; bare integers rejected).
- [x] `walter-os cap list` — prints active tokens for the current session.
- [x] `walter-os cap revoke <nonce>` — deletes the token file; subsequent tool calls won't find it.
- [x] `walter-os cap verify <token-file>` — sanity-check a token (operator debugging).
- [x] bats coverage in `tests/walter/cap-cli.bats`.

### AC-3 — `hooks/capability-check.sh` PreToolUse hook
- [x] Hook runs in the PreToolUse chain after `approval-gate.sh`.
- [x] For `Edit`/`Write`: extracts `file_path`; checks every cap in the session's `caps-<session>/` dir for `tool` matching AND `scope.paths` glob matching.
- [x] For `Bash`: extracts `command`; checks every cap for `tool=Bash` AND (a) `scope.patterns` regex matching OR (b) network destination in `scope.network` (parsed from curl/git/etc. like A-1 egress hook does).
- [x] Capability high-tier classification is hook-local, not a direct lookup into `approval-gate.sh`'s `CATEGORY_MIN_TIER`: protected paths, network-capable Bash commands, `gh pr review --approve`, and capability-system artifacts are always high-tier for capability enforcement.
- [x] If a high-tier op has NO matching cap → block with `"capability-check: no valid token for <tool> on <target>; mint with: walter-os cap mint <tool> ..."`.
- [x] If an op is outside `capability-check.sh`'s high-tier classifier → passthrough allow (existing approval-gate remains the policy check).
- [x] bats coverage in `tests/hooks/capability-check.bats`:
  - High-tier op with no cap → block
  - High-tier op with matching cap → allow
  - High-tier op with EXPIRED cap → block
  - Low-tier op with no cap → allow (cap is opt-in for low-tier)
  - Two-factor bypass (`WALTER_CAP_BYPASS=1` + `--allow-no-cap`) → allow with WARN

### AC-4 — Default skill capabilities
- [x] `contexts/_examples/skill-capabilities.example.yml`:
  ```yaml
  # When these skills are autoloaded at session start, walter-os
  # auto-mints a default capability so the skill works without operator
  # intervention. Operator removes / tightens / extends as needed.
  
  skills:
    nuclei-cli:
      tool: Bash
      scope:
        patterns: ["nuclei[[:space:]].*"]
        network: ["*"]  # nuclei talks to operator-specified targets
      duration: 4h
    
    hcloud-cli:
      tool: Bash
      scope:
        patterns: ["^hcloud[[:space:]].*"]
        network: ["api.hetzner.cloud"]
      duration: 8h
  ```
- [x] `scripts/walter/lib/skill-cap-loader.sh` reads the YAML at session start and mints matching tokens.

### AC-5 — Daily-audit integration
- [ ] `daily-supply-chain-audit` adds `check_cap_state()`:
  - Orphaned `caps-<session>/` dirs (session ended but caps remain) → `info` finding `cap-cleanup-stale`
  - Token mode != 0600 → `high` finding (operator-side perms issue)
  - PASETO key file mode != 0600 → `crit` finding (signing-key exposure)

### AC-6 — Operator-facing docs + CHANGELOG
- [ ] `docs/operational/capability-tokens.md` (new):
  - Philosophy (layered above approval-gate, mandatory for high-tier ops)
  - Common workflow: skill auto-caps; operator-mints when needed
  - Troubleshooting (token expired, signature invalid, hook can't find cap)
  - PASETO v4 primer (what an operator needs to know)
- [ ] CHANGELOG entry under `[Unreleased] → Added (default-deny security floor)`.

## Threat model

| Attack | Mitigation |
|---|---|
| Prompt-injection generates `Bash: cat ~/.ssh/id_rsa` | Sensitive path → tier `high` → no matching cap → blocked. Operator never minted "Bash on ~/.ssh/*". |
| Long-lived JWT-style token stolen from disk | PASETO v4 (no `alg=none` confusion). Plus session-lifetime expiry. |
| Operator mints a wildcard cap and forgets it | Daily-audit `check_cap_state()` doesn't flag wide scope, but cap dies at session end (max 8h per A-4). |
| Subagent escalates by re-signing its parent's token | D-8: no transitive delegation in v0.5.0. The subagent uses the same session key; minting requires `walter-os cap mint`, which is operator-gated. |
| Filesystem race: operator revokes cap WHILE hook is reading it | Hook reads with `flock` **when available** (Linux always; macOS only if the operator installed `util-linux` via Homebrew). On platforms without `flock`, the hook falls back to an open-and-read with a same-inode check at end-of-read (compare `stat -f%i` / `stat -c%i` of the path before and after the read; mismatch = file was unlinked + recreated mid-read, retry the read). This same-inode-check fallback is INTRODUCED BY this spec — the earlier draft said other walter-os scripts already use it, but `hooks/daily-audit-gate.sh` and agent metrics don't actually implement that pattern today; this hook is the first place it lands and it gets pulled into a shared helper in `scripts/walter/lib/atomic-read.sh` so future hooks (audit-chain, etc.) can reuse it. The race window is microseconds either way; deletion is a file unlink, observable on the next PreToolUse invocation. |
| Capability bypass via deleting `caps-<session>/` dir | Hook fails-CLOSED on missing dir for high-tier ops. |

## Out of scope

- Capability delegation (sub-tokens). Future work.
- Hardware-bound signing (YubiKey). Future work.
- Per-syscall caps (eBPF / seccomp). That's A-3 (sandbox), separate spec.
- UI for cap inspection (Control Tower would be the home). v0.5.0 is CLI.

## Recommended PR ordering

1. AC-1 — PASETO-compatible helper + key generation (foundation)
2. AC-2 — `walter-os cap` CLI (uses AC-1)
3. AC-3 — `hooks/capability-check.sh` (uses AC-1)
4. AC-4 — default skill caps + YAML schema
5. AC-5 — daily-audit `check_cap_state()`
6. AC-6 — docs + CHANGELOG

Each ≤300 LOC. 3-round review.

## Open questions for the operator

1. **PASETO v4 vs Biscuit**: Biscuit (eclipse-biscuit) is a newer capability-token format with native delegation + Datalog-like attenuation. PASETO is simpler + more mature. Proposal: PASETO v4 for v0.5.0; revisit Biscuit if delegation becomes a real need.
2. **Default skill cap network scope = `["*"]`**: too loose? Should `nuclei-cli` cap require an explicit target list at session start? Proposal: `["*"]` for v0.5.0 (otherwise operator has to update the YAML every time); tighten in v0.6.0.
3. **High-tier-only enforcement (proposal) vs all-tier enforcement**: should low-tier ops also require a cap once any cap exists for the session? Proposal: high-tier-only; low-tier remains governed by approval-gate alone. Lower friction for the operator who doesn't want to mint caps for every `Read` call.

## Refs

- Parent: `docs/specs/oss-trust-roadmap.md` A-2
- Sibling: `docs/specs/time-bounded-sessions.md` A-4 (cap TTL bound to session TTL)
- Pattern: `hooks/approval-gate.sh` `CATEGORY_MIN_TIER` (high-tier classifier this layer respects)
- PASETO v4 spec: <https://github.com/paseto-standard/paseto-spec/blob/master/docs/01-Protocol-Versions/Version4.md>
- PASETO v4 helper implementation note: `paseto-cli` was proposed in the
  original draft, but is not available from PyPI in the implementation
  environment. The runtime helper therefore implements the PASETO v4.public
  signing shape locally with OpenSSL Ed25519 and PAE canonicalization.
