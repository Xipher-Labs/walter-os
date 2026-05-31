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
  "session_id": "session-test",
  "tool": "Bash",
  "ts": "2026-05-31T12:00:00Z"
}
```

`prev_hash` is the lowercase SHA-256 hash of the previous row's exact JSONL bytes, without the trailing newline. The first row in a day uses the literal string `"null"`.

Append operations take a sidecar lock at `audit/.chain.lock`, reopen the active `chain-YYYY-MM-DD.jsonl` path inside the lock, read the last row, compute the next `prev_hash`, and append one line.

This slice does not wire the writer into PreToolUse hooks yet. Until the follow-up hook-integration PR lands, rows are produced only by callers that explicitly invoke `walter_audit_append`.

Verify a day with:

```bash
walter-os audit verify-chain 2026-05-31
```

This B-1 foundation protects the local chain with linked rows plus the daily root. Linked `prev_hash` values detect accidental or repaired edits inside the chain, and `root-YYYY-MM-DD.txt` detects final-row tampering because it must match the hash of the day's last row. An attacker who can rewrite both `chain-YYYY-MM-DD.jsonl` and the local `root-YYYY-MM-DD.txt` can still fabricate a consistent local history. Signed receipts and external anchoring remain future stronger non-repudiation layers.
