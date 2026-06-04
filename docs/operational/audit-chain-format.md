# Audit Chain Format

The audit-chain library writes signed, tamper-evident audit rows to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/chain-YYYY-MM-DD.jsonl
```

It also writes the local daily root to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/root-YYYY-MM-DD.txt
```

Each line is canonical JSON (`jq -cS`) with these fields:

```json
{
  "decision": "allow",
  "decision_reason": "standing approval",
  "decision_source": "approval-gate",
  "event": "tool_invocation",
  "input_summary": "cat README.md",
  "operator": "alice",
  "prev_hash": "null",
  "row_hash": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "session_id": "session-test",
  "sig": "base64-padded-raw-ed25519-signature",
  "tool": "Bash",
  "ts": "2026-05-31T12:00:00Z"
}
```

`prev_hash` is the lowercase SHA-256 hash of the previous row's exact JSONL bytes, without the trailing newline. The first row in a day uses the literal string `"null"`.
`row_hash` is the lowercase SHA-256 hash of the same canonical JSON object after deleting `row_hash` and `sig`; the verifier rejects rows where this self-digest is missing or stale.
`sig` is the raw Ed25519 signature over the canonical JSON row after deleting only `sig`, encoded with standard padded RFC 4648 base64. A valid 64-byte Ed25519 signature serializes to exactly 88 characters and ends in `==`.

Signatures use the current A-2 session key at:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/state/session-<session_id>.key
```

Verification reads the matching public key from either:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/state/session-<session_id>.pub
${WALTER_CONFIG:-$HOME/.config/walter-os}/state/keys-archive/session-<session_id>.pub
```

Append operations take a sidecar lock at `audit/.chain.lock`, reopen the active `chain-YYYY-MM-DD.jsonl` path inside the lock, read the last row, compute the next `prev_hash`, and append one line.

Hook-integration rows currently use these `decision_source` values:

- `approval-gate`
- `bash-denylist`
- `network-gate`
- `branch-flow-guard`
- `pre-commit-tests`
- `wiki-validator-hook`

Audit append failures fail closed for allow decisions and ordinary policy decisions. Dependency-failure block paths before JSON tooling is available are narrower: when `jq` itself is missing, hooks return the actionable `jq missing` block and attempt a best-effort audit row first. That best-effort path can create the first dependency-failure row in an empty chain, but it is allowed to skip the row when the existing chain cannot be verified without `jq`. Dependency failures after `jq` is available, such as approval-gate's `yq missing` branch, use the normal strict append path and refuse unaudited append failures.

Verify a day with:

```bash
walter-os audit verify-chain 2026-05-31
```

This format protects the local chain with linked rows, per-row self-digests, per-row signatures, and the daily root. Linked `prev_hash` values detect accidental or repaired edits inside the chain, `row_hash` detects final-row edits even if the local root is rewritten, `sig` detects fabricated rows when the attacker lacks the original session private key, and `root-YYYY-MM-DD.txt` detects final-row tampering because it must match the hash of the day's last row. External anchoring remains a future stronger non-repudiation layer.
