# Audit Chain Format

The B-1 foundation library writes tamper-evident audit rows to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/chain-YYYY-MM-DD.jsonl
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

This B-1 foundation detects edits to earlier rows once a later row exists. Hook integration, signed receipts, daily root files, and cross-day verification land in later B-2/B-4 slices.
