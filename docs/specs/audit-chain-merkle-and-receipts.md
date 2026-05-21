# Tamper-evident audit chain + signed receipts (OSS Trust B-1 + B-2) — combined spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: `docs/specs/oss-trust-roadmap.md` Layer B items B-1 + B-2
**Target release**: v0.5.x (after A-2 capability tokens lands — re-uses the per-session Ed25519 key)
**Depends on**: `docs/specs/capability-tokens.md` (A-2 — provides the signing key) and `docs/specs/time-bounded-sessions.md` (A-4 — defines the session lifecycle)

## Problem

Walter-OS's audit trail today is a regular markdown / jsonl file at `~/.config/walter-os/audit-YYYY-MM-DD.md`. Anything running as the operator can:
- Edit history retroactively (`sed -i 's/blocked/allowed/' audit-2026-05-21.md`)
- Truncate the file
- Replace the file with a fabricated one

A security-conscious adopter cannot trust the audit trail to faithfully record what an agent did. The Merkle hash chain + signed receipts close this gap: every tool invocation is a row whose `prev_hash` chains to the previous, and a per-session signature over the row makes silent edits provable.

## Non-goals

- Real-time audit telemetry to a remote server (that's B-3 — Grafana/Loki, separate spec).
- Per-row Sigstore Rekor upload (privacy + cost). Daily root hash to Rekor is opt-in only.
- Replacing the existing `~/.config/walter-os/audit-YYYY-MM-DD.md` operator-readable summary. The summary stays; the chain is the SOURCE OF TRUTH it derives from.
- Migrating existing pre-v0.5.x audit files into the chain. Retroactive proof is out of scope; the chain starts at the v0.5.x deploy.

## Decisions (proposed)

### B-1 (Merkle hash chain)

| # | Decision | Why |
|---|---|---|
| D-1 | **Per-day JSONL chain file**: `~/.config/walter-os/audit/chain-YYYY-MM-DD.jsonl`. Each row's last field is `prev_hash = sha256(row_normalized)` of the previous row in the SAME file. First row's `prev_hash = "null"`. | Per-day partitioning keeps file sizes manageable; chain integrity remains intact within a day. |
| D-2 | **Daily root hash file**: `~/.config/walter-os/audit/root-YYYY-MM-DD.txt` containing `sha256(last_row)` of the day's chain. Operator can pin this somewhere external if they want long-term tamper detection. | Single fixed file for cross-day chaining: day N's `prev_chain_root = sha256(root-YYYY-MM-(DD-1).txt)`. |
| D-3 | **Row normalization**: JSON serialized with sorted keys + LF line ending + no trailing whitespace. Hashed UTF-8 bytes. Documented in `docs/operational/audit-chain-format.md`. | Deterministic hashing across operators; verifier doesn't have to reinvent. |
| D-4 | **Atomic append**: writer takes `flock(LOCK_EX)` on a sidecar `.lock` file (NOT the JSONL itself — addresses the rotation-race that Codex flagged for issue #3 P2-2). Inside the lock, opens the JSONL by path (not by held fd), reads the last line, computes new row's prev_hash, appends. | Robust under concurrent appenders + log rotation. |
| D-5 | **`walter-os audit verify-chain [<date>]`** walks the chain end-to-end and reports the first row whose `prev_hash` doesn't match the previous row. Default verifies today; with `<date>` verifies that day. | Operator-runnable proof of integrity. |

### B-2 (Signed receipts per tool invocation)

| # | Decision | Why |
|---|---|---|
| D-6 | **Each row is signed** with the per-session Ed25519 key from A-2. Signature in the row's `sig` field (base64 PASETO v4 detached signature over `row_minus_sig_field_normalized`). | Reuses the cap-token signing key. No new key infrastructure. |
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
    "decision_source": "approval-gate" | "bash-denylist" | "capability-check" | "network-gate" | "operator-confirm",
    "decision_reason": "<gate-emitted reason or empty>",
    "prev_hash": "<hex sha256 of prev row, or 'null' for first>",
    "sig": "<base64 PASETO v4 detached sig of row sans sig field>"
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
- [ ] Every existing PreToolUse hook (`approval-gate.sh`, `bash-denylist.sh`, `network-gate.sh`, `capability-check.sh`) appends one row per decision to the chain (allow OR block).
- [ ] Existing `~/.config/walter-os/audit-YYYY-MM-DD.md` summary doc is now a DERIVED view from the chain — regenerated by a new `walter-os audit summarize-day` subcommand.
- [ ] bats coverage in `tests/hooks/audit-chain-hook-integration.bats`: a sample Bash invocation that hits approval-gate gets exactly ONE row appended, not zero, not multiple.

### AC-3 — Signing
- [ ] Each row's `sig` field is a PASETO v4 detached signature (using the per-session Ed25519 key from A-2) over `row_normalized_minus_sig`.
- [ ] Verifier in `walter-os audit verify-chain`:
  - Loads the session's public key (from `state/` or `state/keys-archive/`)
  - Recomputes `prev_hash` per row; mismatch → integrity error
  - Verifies `sig` per row; mismatch → signature error
  - Exits 0 if all rows pass; non-zero with row-number if not
- [ ] bats coverage in `tests/walter/audit-chain-verify.bats`:
  - Clean chain → exit 0
  - Tampered single row → exit 1 with row number
  - Tampered prev_hash → exit 1
  - Missing public key → exit 2 with "cannot verify session-<uuid>"

### AC-4 — Daily root + cross-day chaining
- [ ] `walter-os audit close-day [<date>]` (or auto-run via cron from `walter-os audit verify-chain`) writes `root-YYYY-MM-DD.txt` = `sha256(last_row)` of the day's chain.
- [ ] Day N's first row includes `prev_chain_root = sha256(root-YYYY-MM-(DD-1).txt)`; missing prev_chain_root only valid on day 0 of the deployment.
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
- PASETO v4 detached signature: <https://github.com/paseto-standard/paseto-spec>
- Sigstore Rekor: <https://docs.sigstore.dev/rekor/overview/>
- Issue #3 P2-2 (rotation-race finding — AC-1 addresses)
