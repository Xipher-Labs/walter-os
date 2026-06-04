# Tamper-evident audit chain + signed receipts (OSS Trust B-1 + B-2) — combined spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: OSS Trust roadmap Layer B items B-1 + B-2 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83) (post-merge in-tree path: `docs/specs/oss-trust-roadmap.md`).
**Target release**: v0.5.x (after A-2 capability tokens lands — re-uses the per-session Ed25519 key)
**Depends on**:
- A-2 capability tokens — [PR #88](https://github.com/Xipher-Labs/walter-os/pull/88) (post-merge: `docs/specs/capability-tokens.md`) — provides the signing key.
- A-4 time-bounded sessions — [PR #87](https://github.com/Xipher-Labs/walter-os/pull/87) (post-merge: `docs/specs/time-bounded-sessions.md`) — defines the session lifecycle.

**Naming note (Copilot R1)**: this spec's filename uses "Merkle" but the design is a **linear hash chain**, NOT a Merkle tree. Each row's `prev_hash = sha256(previous_row)` is sequential — there are no sibling hashes and no inclusion proofs. We kept "Merkle" in the filename because the parent OSS Trust roadmap (B-1) named it that way originally, and renaming the file mid-flight would invalidate inbound links. Future readers should treat the file name as historical shorthand for "tamper-evident hash chain"; the body uses the precise "hash chain" terminology throughout.

## Problem

Walter-OS's audit trail today is a regular markdown / jsonl file at `~/.config/walter-os/audit-YYYY-MM-DD.md`. Anything running as the operator can:
- Edit history retroactively (`sed -i 's/blocked/allowed/' audit-2026-05-21.md`)
- Truncate the file
- Replace the file with a fabricated one

A security-conscious adopter cannot trust the audit trail to faithfully record what an agent did. The **hash chain** (linear, sequential — not a Merkle tree; see the naming note above) + signed receipts close this gap: every tool invocation is a row whose `prev_hash` chains to the previous, and a per-session signature over the row makes silent edits provable.

## Non-goals

- Real-time audit telemetry to a remote server (that's B-3 — Grafana/Loki, separate spec).
- Per-row Sigstore Rekor upload (privacy + cost). Daily root hash to Rekor is opt-in only.
- Replacing the existing `~/.config/walter-os/audit-YYYY-MM-DD.md` operator-readable summary. The summary stays; the chain is the SOURCE OF TRUTH it derives from.
- Migrating existing pre-v0.5.x audit files into the chain. Retroactive proof is out of scope; the chain starts at the v0.5.x deploy.

## Decisions (proposed)

### B-1 (hash chain — linear; called "Merkle" in the roadmap for historical reasons, see naming note above)

| # | Decision | Why |
|---|---|---|
| D-1 | **Per-day JSONL chain file**: `~/.config/walter-os/audit/chain-YYYY-MM-DD.jsonl`. Each row's last field is `prev_hash = sha256(row_normalized)` of the previous row in the SAME file. First row's `prev_hash = "null"`. | Per-day partitioning keeps file sizes manageable; chain integrity remains intact within a day. |
| D-2 | **Daily root hash file**: `~/.config/walter-os/audit/root-YYYY-MM-DD.txt` containing the 64-character lowercase hex digest of `sha256(last_row)` (the last row's full bytes), no trailing newline, no surrounding whitespace, UTF-8 encoded. Operator can pin this somewhere external if they want long-term tamper detection. | Deterministic file content makes cross-day chaining unambiguous (see D-2 cross-day note below). Operator-portable. |
|   | **Cross-day chaining**: day N's first chain row carries `prev_chain_root = <day N-1's root-YYYY-MM-DD.txt content, verbatim hex string>` — NOT a re-hash of the file. The text inside `root-YYYY-MM-DD.txt` IS the prev-day's root hash; copying it into day N's first row is what links the days. Verifier confirms `day-N-first-row.prev_chain_root == read_file("root-YYYY-MM-(DD-1).txt")`. This avoids the double-hash / file-encoding-sensitivity confusion the earlier draft created. | Single string equality check; no implicit re-hashing of the file. |
| D-3 | **Row normalization**: JSON serialized with sorted keys + LF line ending + no trailing whitespace. Hashed UTF-8 bytes. Documented in `docs/operational/audit-chain-format.md`. | Deterministic hashing across operators; verifier doesn't have to reinvent. |
| D-4 | **Atomic append**: writer takes `flock(LOCK_EX)` on a sidecar `.lock` file (NOT the JSONL itself — addresses the rotation-race that Codex flagged for issue #3 P2-2). Inside the lock, opens the JSONL by path (not by held fd), reads the last line, computes new row's prev_hash, appends. | Robust under concurrent appenders + log rotation. |
| D-5 | **`walter-os audit verify-chain [<date>]`** walks the chain end-to-end and reports the first row whose `prev_hash` doesn't match the previous row. Default verifies today; with `<date>` verifies that day. | Operator-runnable proof of integrity. |

### B-2 (Signed receipts per tool invocation)

| # | Decision | Why |
|---|---|---|
| D-6 | **Each row is signed** with the per-session Ed25519 key from A-2. The `sig` field carries the raw 64-byte Ed25519 signature, **base64-encoded per RFC 4648 §4 (standard base64, NOT base64url): the alphabet is `A-Z a-z 0-9 + /`, padding `=` is REQUIRED so a 64-byte signature always serializes to exactly 88 characters, and the output MUST NOT contain line breaks**. Computed over the canonical JSON serialization of the row with the `sig` field removed (RFC 8785 JCS — JSON Canonicalization Scheme: keys sorted, no whitespace, UTF-8). NOTE: "detached signature" is NOT a term defined by the PASETO v4 spec; we use raw Ed25519 directly so the wire format is unambiguous across language implementations. PASETO v4 is referenced only as the design inspiration for the per-session-key model. | Reuses the cap-token signing key. No new key infrastructure. RFC 8785 JCS makes the signed bytes deterministic across implementations; RFC 4648 §4 + required padding makes the wire encoding round-trip-stable across Python (`base64.b64encode`), Node (`Buffer.from(..., 'base64')`), Bash (`base64`), and Go (`base64.StdEncoding`). |
| D-7 | **Verifier resolves the per-row signer**: `(session_id, sig)` → look up `~/.config/walter-os/state/session-<session_id>.pub` (the public half of the session key, persisted at session start). | Public key persists; private key dies at session end. After session end, you can still VERIFY past rows; you cannot mint new ones. |
| D-8 | **Public key rotation**: when a new session starts, the previous session's public key is moved to `~/.config/walter-os/state/keys-archive/session-<uuid>.pub`. Verifier checks both `state/` and `state/keys-archive/`. | Never delete public keys (you'd lose ability to verify old rows). Keys archive is bounded by `WALTER_AUDIT_KEYS_ARCHIVE_DAYS` (default 365). |
| D-9 | **Sigstore Rekor (opt-in)**: when `WALTER_AUDIT_REKOR_UPLOAD=1`, the daily root hash (NOT row content) + timestamp + operator-id are uploaded to Sigstore Rekor at session end. Public attestation that THIS operator was running THIS chain at THIS time. | Operator-opt-in public timestamping. Per OSS Trust roadmap D-3 decision. |

## Acceptance criteria

### AC-1 — Row schema + writer

- [ ] Row schema documented in `docs/operational/audit-chain-format.md`:
  ```json
  {
    "ts": "2026-05-21T03:14:22.123Z",
    "session_id": "<uuid>",
    "operator": "<from $USER>",
    "event": "tool_invocation",
    "tool": "Bash",
    "input_summary": "<first 200 chars, redacted via agent-secret-redactor>",
    "decision": "allow" | "block",
    "decision_source": "approval-gate" | "bash-denylist" | "branch-flow-guard" | "capability-check" | "network-gate" | "operator-confirm" | "pre-commit-tests" | "wiki-validator-hook",
    "decision_reason": "<gate-emitted reason or empty>",
    "prev_hash": "<hex sha256 of prev row, or 'null' for first>",
    "sig": "<base64 raw Ed25519 signature over JCS(row minus sig field)>"
  }
  ```
- [ ] `scripts/walter/lib/audit-chain.sh` (new) — exposes `walter_audit_append <tool> <input> <decision> <source> <reason>` and `walter_audit_normalize_row`.
- [ ] Atomic append per D-4 (flock sidecar; re-open JSONL by path inside the lock).
- [ ] bats coverage in `tests/walter/audit-chain-append.bats`:
  - First append creates the file + sets `prev_hash: "null"`
  - Second append chains to the first
  - Concurrent appenders serialize via flock
  - Rotation race (background mv of the JSONL during append) lands in the post-rotation file

### AC-2 — Hook integration

- [ ] Every existing PreToolUse hook (`approval-gate.sh`, `bash-denylist.sh`, `network-gate.sh`, `branch-flow-guard.sh`, `pre-commit-tests.sh`, `wiki-validator-hook.sh`, `capability-check.sh` when present) appends one row per decision to the chain (allow OR block).
  - Dependency-failure block paths before JSON tooling is available are explicitly scoped: if `jq` itself is missing, hooks fail closed and attempt a best-effort audit row. The jq-free writer may create the first dependency-failure row in an empty chain, but it must not extend an existing chain it cannot verify without `jq`. Dependency failures after `jq` is available use the normal strict append path.
- [ ] Existing `~/.config/walter-os/audit-YYYY-MM-DD.md` summary doc is now a DERIVED view from the chain — regenerated by a new `walter-os audit summarize-day` subcommand.
- [ ] bats coverage in `tests/hooks/audit-chain-hook-integration.bats`: representative allow/block decisions for each integrated hook append exactly one row per hook decision, not zero, not multiple.

### AC-3 — Signing

- [x] Each row's `sig` field is a raw Ed25519 signature (base64-encoded; 64 bytes raw before encoding) over the RFC 8785 JCS canonicalization of the row with the `sig` field removed. The signing key is the per-session Ed25519 private key from A-2. "PASETO v4" is referenced as the design inspiration only — we do NOT emit PASETO tokens because "detached signature" isn't a defined term in the PASETO spec and would lead to incompatible implementations across languages.
- [x] Verifier in `walter-os audit verify-chain`:
  - Loads the session's public key (from `state/` or `state/keys-archive/`)
  - Recomputes `prev_hash` per row; mismatch → integrity error
  - Verifies `sig` per row; mismatch → signature error
  - Exits 0 if all rows pass; non-zero with row-number if not
- [x] bats coverage in `tests/walter/audit-chain-verify.bats`:
  - Clean chain → exit 0
  - Tampered single row → exit 1 with row number
  - Tampered prev_hash → exit 1
  - Missing public key → exit 2 with "cannot verify session-<uuid>"

### AC-4 — Daily root + cross-day chaining

- [ ] `walter-os audit close-day [<date>]` (or auto-run via cron from `walter-os audit verify-chain`) writes `root-YYYY-MM-DD.txt` = `sha256(last_row)` of the day's chain.
- [ ] Day N's first row includes `prev_chain_root = <contents of root-YYYY-MM-(DD-1).txt, verbatim hex string>` (NOT `sha256(...)` of the file — re-hashing introduces file-encoding sensitivity that D-2 explicitly rules out). Missing `prev_chain_root` only valid on day 0 of the deployment.
- [ ] `walter-os audit verify-chain --since <date>` walks multiple days' chains in order.

### AC-5 — Sigstore Rekor opt-in

- [ ] When `WALTER_AUDIT_REKOR_UPLOAD=1`, `walter-os audit close-day` uploads:
  ```json
  {
    "root": "<hex>",
    "date": "YYYY-MM-DD",
    "operator": "<hash-of-user-id, NOT plaintext>",
    "walter_os_version": "<from VERSION>"
  }
  ```
  signed with the LAST session's Ed25519 key. Receives a Rekor entry-id; stored in `root-YYYY-MM-DD.rekor.json`.
- [ ] `walter-os audit verify-chain --check-rekor` confirms the local root matches what's in Rekor.
- [ ] If `WALTER_AUDIT_REKOR_UPLOAD=0` (default), no network call.

### AC-6 — Operator-facing docs + CHANGELOG

- [ ] `docs/operational/audit-chain.md` (new):
  - Row schema + normalization rules
  - How to verify (`walter-os audit verify-chain`)
  - How to opt into Rekor
  - "What does this NOT protect against" (compromised session key during the session itself)
- [ ] CHANGELOG entry under `[Unreleased] → Added (audit integrity)`.

### AC-7 — Migration / coexistence

- [ ] Pre-v0.5.x `audit-YYYY-MM-DD.md` files left untouched (not migrated).
- [ ] New `audit/chain-YYYY-MM-DD.jsonl` files start fresh on first session under v0.5.x.
- [ ] `walter-os audit summarize-day <date>` works for both pre-chain markdown days (passes through) AND chain days (regenerates from JSONL).

## Threat model

| Attack | Mitigation |
|---|---|
| Operator-user (or compromised-as-operator) edits past rows | `prev_hash` chain detects insertion / modification / deletion of any row |
| Operator-user replaces the entire JSONL with fabricated data | `sig` field is signed by the per-SESSION key; attacker without the session private key cannot produce valid sigs for new rows. Public key persists, so verification fails post-hoc. |
| Compromised session forges rows DURING its own session | Real risk; session-level compromise = full control. Mitigation is upstream (A-2 capability tokens, A-3 sandbox); the audit chain detects POST-HOC tampering, not concurrent compromise. |
| Operator deletes the entire chain | Detectable via Rekor (D-9) if opt-in. Without Rekor: not detectable by Walter-OS alone; operator's external backup discipline is the floor. |
| Public-key tampering (replace session pub key with attacker's) | Public keys stored in `state/` + `state/keys-archive/`; tampering is detectable IF operator backs up these dirs externally. Future: archive keys to Rekor too. |
| Time-of-check vs time-of-use (concurrent rotation during append) | flock + path re-open (D-4) closes this; bats test confirms. |

## Out of scope

- Telemetry to a remote server (B-3, separate spec).
- Hardware-bound signing keys (A-2 future work).
- Multi-machine chain unification (operator's Mac + Walter-VM + hackathon Linode). Per-host chain is the v0.5.x floor.
- Migrating pre-v0.5.x markdown audit files into the chain.

## Recommended PR ordering

1. AC-1 — `audit-chain.sh` lib + atomic append + bats (foundation; ~250 LOC including tests)
2. AC-3 — signing + `verify-chain` subcommand (uses A-2 key infrastructure)
3. AC-2 — hook integration (touches every PreToolUse hook lightly)
4. AC-4 — daily root + cross-day chaining
5. AC-5 — Sigstore Rekor opt-in
6. AC-6 + AC-7 — docs + CHANGELOG + migration coexistence (closing PR)

Each ≤300 LOC. 3-round review.

## Open questions for the operator

1. **`prev_hash` for day-0 row**: literal string `"null"` (proposal) or empty string `""`? Proposal: `"null"` — visually distinct in `cat chain.jsonl`.
2. **Public-key archive TTL**: 365 days (proposal — covers a year-back verify), unlimited, or operator-configurable? Proposal: 365d default, operator-overridable via `WALTER_AUDIT_KEYS_ARCHIVE_DAYS`.
3. **Rekor upload identity scope**: hash-of-user-id (proposal — pseudonymous), plaintext operator (visible in Rekor), or static "walter-os-operator" string (no operator distinction)? Proposal: hashed.
4. **`audit-chain.jsonl` vs `chain.jsonl`** naming inside the `audit/` directory: redundant prefix or clear? Proposal: drop prefix (`audit/chain-YYYY-MM-DD.jsonl`).

## Refs

- Parent: `docs/specs/oss-trust-roadmap.md` Layer B B-1 + B-2
- Sibling: `docs/specs/capability-tokens.md` (A-2 — signing key source)
- Sibling: `docs/specs/time-bounded-sessions.md` (A-4 — session lifecycle defines key rotation)
- PASETO v4 (design inspiration only; we emit raw Ed25519, not PASETO tokens): <https://github.com/paseto-standard/paseto-spec>
- RFC 8785 JCS (canonicalization scheme for the signed bytes): <https://datatracker.ietf.org/doc/html/rfc8785>
- Sigstore Rekor: <https://docs.sigstore.dev/rekor/overview/>
- Issue #3 P2-2 (rotation-race finding — AC-1 addresses)
