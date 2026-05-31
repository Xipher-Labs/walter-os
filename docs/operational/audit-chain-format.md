# Audit Chain Format

The B-1 foundation library writes tamper-evident audit rows to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/chain-YYYY-MM-DD.jsonl
```

It also writes the local daily root to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/root-YYYY-MM-DD.txt
```

Each line is canonical JSON (`jq -cS`) with these unsigned B-1 foundation fields:

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
  "tool": "Bash",
  "ts": "2026-05-31T12:00:00Z"
}
```

`prev_hash` is the lowercase SHA-256 hash of the previous row's exact JSONL bytes, without the trailing newline. The first row in a day uses the literal string `"null"`.
`row_hash` is the lowercase SHA-256 hash of the same canonical JSON object after deleting `row_hash`; the verifier rejects rows where this self-digest is missing or stale.

Append operations take a sidecar lock at `audit/.chain.lock`, reopen the active `chain-YYYY-MM-DD.jsonl` path inside the lock, read the last row, compute the next `prev_hash`, and append one line.

Hook-integration rows currently use these `decision_source` values:

- `approval-gate`
- `bash-denylist`
- `network-gate`
- `branch-flow-guard`
- `pre-commit-tests`

Audit append failures fail closed for hook decisions. If a hook cannot append its row, it emits a block decision instead of allowing an unaudited tool invocation.

Verify a day with:

```bash
walter-os audit verify-chain 2026-05-31
```

This B-1 foundation protects the local chain with linked rows, per-row self-digests, and the daily root. Linked `prev_hash` values detect accidental or repaired edits inside the chain, `row_hash` detects final-row edits even if the local root is rewritten, and `root-YYYY-MM-DD.txt` detects final-row tampering because it must match the hash of the day's last row. An attacker who can rewrite the full `chain-YYYY-MM-DD.jsonl` history can still fabricate a consistent local history. Signed receipts and external anchoring remain future stronger non-repudiation layers.
