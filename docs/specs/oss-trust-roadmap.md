# OSS Trust Roadmap — multi-release spec

**Status**: ready for `/write-plan` PER-ITEM (this spec is the umbrella; each item gets its own spec when picked up)
**Issue**: #1 (`OSS Trust Roadmap v0.3+ — runtime sandboxing, audit chain, signed receipts`)
**Target releases**: v0.4.1 → v1.0
**Depends on**: v0.4.0 P0 + P1 closures (all in flight)

## Problem

Walter-OS has solid AGENT-FACING discipline (approval-gate, hooks, audit, env-allowlist, branch-flow guard) but is missing the SYSTEM-LEVEL containment + observability that an audit-grade agent framework needs before v1.0. Anyone running Walter-OS in production today is implicitly trusting:

1. **Hooks don't escape their script-level guards.** The `approval-gate.sh` + `bash-denylist.sh` chains cover known attack patterns but operate at the bash-script layer. A novel prompt-injection that produces an unrecognized command class still gets the operator's full POSIX permissions.
2. **The audit log is operator-truthful.** `~/.config/walter-os/audit-YYYY-MM-DD.md` is a regular file. The operator (or anything running as them) can edit history retroactively. There's no tamper-evident chain.
3. **Releases are reproducible.** `release.yml` ships SBOMs + cosign signatures, but the build itself isn't reproducible. Two runs of the same tag could produce different artifacts and we'd never know.

This umbrella spec lists every gap and assigns a target release. Each item gets a per-spec when picked up. Closing this issue means v1.0 is shippable to security-conscious adopters with a straight face.

## Non-goals

- **Bundling our own sandbox primitives.** We wrap what's per-OS available (nsjail / firejail / macOS `sandbox-exec`), not invent.
- **Becoming a CNA ourselves.** GitHub Security Advisories partnership is the practical floor; full CNA registration is post-v1.0 corporate-process work.
- **Replacing GitHub Actions** for SLSA L3. Actions has GitHub-hosted runners with SLSA-L3 attestation baked in; we use that, not a self-built provenance stack.
- **Solving for cross-OS reproducibility.** Linux + macOS + WSL are the targets; Windows-native is operator-overlay territory.

## Roadmap (5 layers, 16 items total)

### Layer A — Runtime sandboxing (5 items)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| A-1 | **Network egress allowlist** — default deny, agent only reaches approved endpoints | v0.4.1 | 1-2d | `~/.config/walter-os/egress-allowlist.txt` parsed by a new `walter-os network-gate` daemon; wraps tool invocations |
| A-2 | **Filesystem capability tokens** — scoped per session, time-bound, revocable | v0.4.1 | 2-3d | Per-tool fcap-equivalent token; signed by a PER-SESSION ephemeral Ed25519 key (NOT a long-lived operator key — see DEC-2 below and PR #88's per-item spec). |
| A-3 | **Process isolation via nsjail/firejail/sandbox-exec** | v0.5.x | 2-3d | Per-OS wrapper. Wrap hook + skill execution. |
| A-4 | **Time-bounded sessions** — kill on max-time / idle | v0.4.1 | 1d | New `hooks/session-timeout.sh` reading `WALTER_SESSION_MAX_HOURS` |
| A-5 | **Read-only `/tmp` and operator-overlay during runs** — bind-mount the operator's secret-bearing paths read-only by default | v0.5.x | 1-2d | Composes with A-3 |

### Layer B — Audit + observability (3 items)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| B-1 | **Append-only tamper-evident log** (Merkle hash-chain) of every tool invocation | v0.5.x | 2-3d | Each entry is a JSONL row including the prev-row hash; verifier at `walter-os audit verify-chain` |
| B-2 | **Signed receipts per tool invocation** — operator can verify any action after the fact | v0.5.x | 1-2d | Each row signed by the per-session ephemeral key (matches A-2's capability-token signing key) |
| B-3 | **Dedicated telemetry → Grafana/Loki** (not stdout) | v0.6.0 | 1-2d | Promtail config + Grafana dashboard JSON; ships under `setup/walter-host/services/observability/` |

### Layer C — Supply chain (3 items)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| C-1 | **SLSA Level 3 provenance** — extend `release.yml` to emit + sign provenance attestations | v1.0 | 4-6h | GitHub Actions hosted runner already meets SLSA-L3; we just need the `actions/attest-build-provenance` step |
| C-2 | **Reproducible builds** for bash/JS/Python release artifacts | v1.0 | days, multi-language | Assess scope per-language; bash scripts are trivially reproducible, JS bundles need lockfile + tooling pinning. Combined with C-1 in PR #95's spec. |
| C-3 | **Pre-commit framework integration** for gitleaks (alongside the raw git hook) | v0.4.1 | 2-4h | `.pre-commit-config.yaml` ships; operator chooses |

### Layer D — Community / governance (1 item)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| D-1 | **GitHub Security Advisories** partner registration | v0.4.1 | 1-2h (mostly process) | Pre-req for any CVE assignment; documented in SECURITY.md |

### Layer E — Follow-ups from v0.2.x / v0.3.x PRs (4 items)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| E-1 | **OpenSSF Passing Badge** filing | v0.4.1 | 2-4h | Pre-req for Silver |
| E-2 | **OpenSSF Silver Badge** filing | v0.6.0 | 2-4h | After Passing + Layer A items close |
| E-3 | **`@types/*` allowlist for `minimumReleaseAge`** | v0.4.1 | 2h | Deferred from PR #60; needs `check-release-age.py` (already shipped) |
| E-4 | **`walter-os justify revoke` CLI** | v0.4.1 | 2-4h | Deferred from PR #60; pairs with walter-debt-tracker spec (PR #77) |

**16 items total.** All v1.0-blocking items target v0.4.1 → v0.6.0 (the next two minor releases). C-1 + C-2 close at v1.0.

## Cross-cutting decisions (DEC-1..DEC-4)

Renamed from `D-1..D-4` (in earlier drafts) to **`DEC-1..DEC-4`** to avoid
clashing with the roadmap-item ID `D-1` (Layer D's "GitHub Security Advisories"
item). Per-item specs that reference these design choices use the DEC-N
prefix. Roadmap items use their layer-letter prefix (A-1, B-2, C-1, D-1, E-2).

### DEC-1 — Sandbox primitives: WRAP, don't build

Wrap per-OS primitives:
- **Linux**: nsjail (preferred — fine-grained capabilities) or firejail (operator-friendlier)
- **macOS**: `sandbox-exec` (built-in, profile-based)
- **WSL**: nsjail under WSL2

Walter-OS ships a `scripts/walter/lib/sandbox.sh` shim that exposes a uniform `walter_sandbox_run <profile> <cmd>` regardless of host. Profile names map to per-OS config files.

**Rejected**: building a custom seccomp-bpf filter. Too much surface; the per-OS primitives are mature.

### DEC-2 — Capability-token format: PASETO v4 design, raw Ed25519 wire

PASETO (Platform-Agnostic SEcurity TOkens) v4 is the **design inspiration** —
per-session ephemeral Ed25519, no algorithm-confusion surface, signed
claims-over-JSON. JWT is the rejected alternative (alg=none, key-confusion
history). UUID + audit-log is the other rejected alternative (unsigned,
no public-key binding).

Implementation note: capability tokens emit FULL PASETO v4 public tokens
(payload + footer + signature). The audit-chain rows (B-1 + B-2) emit
raw Ed25519 signatures over RFC 8785 JCS, NOT PASETO tokens — the
"detached signature" form is undefined in the PASETO spec and would be
ambiguous across language implementations. See `docs/specs/audit-chain-merkle-and-receipts.md`
for the JCS canonicalization details.

The per-session ephemeral key (Ed25519) is generated at session start, stored at `~/.config/walter-os/state/session-<uuid>.key`, deleted on session end (or after max idle). Capability tokens (A-2) are PASETO-v4-signed claims about (operator, session, scope, expiry); audit-chain rows (B-1 + B-2) are raw Ed25519 signatures over the JCS-canonicalized row payload.

### DEC-3 — Tamper-evident log: hybrid local + Rekor for public attestation

- **Local Merkle hash-chain** over `~/.config/walter-os/audit/<date>.jsonl` files. Each row's last field is `prev_hash = sha256(prev_row_normalized)`. `walter-os audit verify-chain` walks the chain end-to-end.
- **Optional Sigstore Rekor upload** of daily-summary hashes (NOT per-row content; just the daily root hash + timestamp). Operator can opt in via `WALTER_AUDIT_REKOR_UPLOAD=1`. Public attestation that THIS operator was running THIS audit chain at THIS time. No log content leaves the machine.

**Rejected**: full per-row Rekor upload. Privacy + cost; daily root hash is enough for tamper detection.

### DEC-4 — Reproducible builds: scope to release-security pipeline

The full multi-language reproducible-build matrix is too much work for v1.0. Instead:

- **In-scope**: `release.yml` artifacts (source archives, SBOM, checksums, cosign bundle) must produce byte-identical output on two runs of the same tag. Requires pinning every tool version + ordering inputs deterministically.
- **Out-of-scope**: User-runnable build outputs (e.g. control-tower Next.js bundles, walter-host service images). Those follow their own reproducibility roadmap.

`release.yml` already does most of the work; what remains is documenting + testing.

## Acceptance criteria (umbrella)

This issue closes when **all 16 items above** have shipped or been explicitly deferred to a post-v1.0 release with a tracking sub-issue.

Per-item ACs live in each item's own spec, filed when picked up. Recommended order:

1. **v0.4.1 must-haves**: A-1, A-2, A-4, C-3, D-1, E-1, E-3, E-4 (network egress + capability tokens + session timeout + pre-commit framework + Security Advisories + Passing Badge + the two carryover follow-ups). These are the "ship in v0.4.1 or this roadmap is too slow" items.
2. **v0.5.x flow**: A-3 (sandbox), A-5 (RO mounts), B-1 (Merkle log), B-2 (signed receipts).
3. **v0.6.0 polish**: B-3 (telemetry), E-2 (Silver Badge).
4. **v1.0 capstone**: C-1 (SLSA L3), C-2 (reproducible builds).

## Architecture sketch (v0.4.1 milestone)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Session start                                                      │
│  $ claude code           (or codex, or walter-os agents run-once)   │
│                                                                     │
│  hooks/session-start.sh:                                            │
│    1. Generate Ed25519 keypair → ~/.config/walter-os/state/         │
│         session-<uuid>.key (mode 0600)                              │
│    2. Mint PASETO v4 capability token (op=ops-bot, scope=*,         │
│         expires=now+8h)                                             │
│    3. Init audit chain row 0 (prev_hash=null)                       │
│    4. Spawn walter-os network-gate daemon (egress allowlist)        │
│    5. (Linux) launch under nsjail; (macOS) under sandbox-exec       │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Per tool invocation                                                │
│                                                                     │
│  approval-gate.sh / bash-denylist.sh / new capability-check.sh:     │
│    - Approve / block per existing rules                             │
│    - If approved: append signed JSONL row to today's audit chain    │
│      (prev_hash + sha256(row) + Ed25519 sig)                        │
│    - Forward network calls through walter-os network-gate (deny     │
│      if dst not in allowlist)                                       │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Session end (max-time OR explicit close)                           │
│                                                                     │
│  hooks/session-end.sh:                                              │
│    1. Compute daily root hash; optionally upload to Sigstore Rekor  │
│    2. Delete session-<uuid>.key (revoke all caps minted from it)    │
│    3. Stop network-gate daemon                                      │
│    4. Stop nsjail/sandbox-exec wrapper                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Threat model

The roadmap mitigates each of the listed gaps:

| Gap | Mitigation | Item |
|---|---|---|
| Prompt-injection → unrecognized command class → operator-full POSIX permissions | nsjail/sandbox-exec wrapper; egress allowlist; capability tokens | A-1, A-2, A-3 |
| Compromised local process tampers with audit log | Merkle chain detects retroactive edits; Rekor opt-in attests to chain root publicly | B-1, B-2 |
| Tampered release artifact (build-time MITM) | SLSA-L3 provenance from GH Actions runner; reproducible builds for our pipeline | C-1, C-2 |
| Bug-bounty researcher wants to report; no CVE channel | GH Security Advisories partner | D-1 |
| Long-running session forgotten / left idle | Time-bounded sessions kill on idle | A-4 |

## Open questions for the operator

1. **Sandbox profile defaults**: should `nsjail` default to "deny everything except explicit allowlist" or "deny network + raw filesystem outside repo, allow everything else"? Proposal: latter (less footgun for first-time adopters); operators harden via override.
2. **Rekor upload default**: opt-in (proposal — `WALTER_AUDIT_REKOR_UPLOAD=1` required) or opt-out? Default proposed: opt-in. Sigstore Rekor is public; not every operator wants their session timestamps published.
3. **Per-session keypair lifetime**: 8 hours (proposal — fits a single workday), 24 hours, or operator-configurable via `WALTER_SESSION_KEY_TTL`? Default proposed: 8 hours with operator override.
4. **Reproducible-builds language scope for C-2**: bash + JS only (proposal — covers `release.yml` + `apps/control-tower`)? Or include Python (`scripts/walter/lib/*.py`)? Default proposed: bash + JS for v1.0; Python in v1.x.

## Out of scope for this umbrella

- **Hardware-token integration** (YubiKey for capability-token signing). Layer 6+ aspiration; not on the 16-item list.
- **Multi-operator orchestration** (different operators with different capability sets sharing a Walter-OS install). Single-operator-per-install remains the model.
- **Cross-VM session tracking** (an operator running Walter-OS on Mac AND on Walter-VM AND on a hackathon Linode and wanting one unified audit chain). Per-host audit chain is the v1.0 floor.
- **Anonymized telemetry to Xipher Labs.** Out of scope — no opt-in telemetry; operator owns their data. Telemetry under B-3 is operator's OWN Grafana, not centralized.

## Recommended order of per-item specs

Specs filed in this order (each its own follow-up PR):

1. **v0.4.1 spec batch** — A-1, A-2, A-4, C-3, D-1, E-1, E-3, E-4 (8 specs, can be parallel)
2. **v0.5.x batch** — A-3, A-5, B-1, B-2 (4 specs)
3. **v0.6.0 batch** — B-3, E-2 (2 specs)
4. **v1.0 batch** — C-1, C-2 (2 specs)

Each per-item spec follows the template established by `docs/specs/p1-hardening-epic.md`: problem, non-goals, decisions, ACs, threat model, dependencies, refs.

## Refs

- Issue #1
- `docs/specs/p1-hardening-epic.md` (the v0.4.0 audit P1 closure — this roadmap picks up where P1 leaves off)
- `docs/operational/security-audit-2026-05-11.md` (the audit this roadmap aspires to close all of)
- `docs/security/verification.md` (existing cosign verification — C-1 extends it)
- Sigstore Rekor: <https://docs.sigstore.dev/rekor/overview/>
- nsjail: <https://github.com/google/nsjail>
- macOS sandbox-exec: <https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf>
- PASETO v4: <https://paseto.io/>
- SLSA: <https://slsa.dev/spec/v1.0/levels>
- OpenSSF Best Practices Badge: <https://www.bestpractices.dev/>
