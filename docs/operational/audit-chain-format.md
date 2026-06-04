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
  "prev_chain_root": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
  "row_hash": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "session_id": "session-test",
  "sig": "base64-padded-raw-ed25519-signature",
  "tool": "Bash",
  "ts": "2026-05-31T12:00:00Z"
}
```

`prev_hash` is the lowercase SHA-256 hash of the previous row's exact JSONL bytes, without the trailing newline. The first row in a day uses the literal string `"null"`.
`prev_chain_root` appears only on the first row of a day when the previous day's `root-YYYY-MM-DD.txt` exists. It copies the previous root file's 64-character hex value verbatim; it is not hashed again. Multi-day verification checks this field to prove local day-to-day continuity.
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

Runtime requirements for signed append and verification:

- `jq` for canonical JSON normalization.
- An Ed25519-capable `openssl` for signing and signature verification.
- `python3` with the standard `base64`, `json`, and `pathlib` modules for
  strict base64 serialization/deserialization helpers.

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

Close a missing day root, or verify an existing matching root, with:

```bash
walter-os audit close-day 2026-05-31
```

Verify an inclusive local date range with cross-day root continuity:

```bash
walter-os audit verify-chain --since 2026-05-31 --until 2026-06-01
```

This format protects the local chain with linked rows, per-row self-digests,
per-row signatures, and the daily root. Linked `prev_hash` values detect
accidental or repaired edits inside the chain, `row_hash` detects final-row
edits even if the local root is rewritten, `sig` detects fabricated rows when
the attacker lacks the original session private key, and
`root-YYYY-MM-DD.txt` detects final-row tampering because it must match the
hash of the day's last row.

Optional Rekor anchoring writes a public daily-root receipt to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/root-YYYY-MM-DD.rekor.json
```

The Rekor payload is canonical JSON with the daily `root`, `date`, hashed
`operator`, and `walter_os_version`. Walter-OS signs the payload's SHA-256
digest with the last row's session Ed25519 key, submits that digest/signature as
a Rekor `hashedrekord`, and never includes audit row content or the plaintext
operator id. Upload is disabled by default; it only runs when
`WALTER_AUDIT_REKOR_UPLOAD=1` is set for `walter-os audit close-day`.

Verify a local root against its Rekor entry with:

```bash
walter-os audit verify-chain --check-rekor 2026-05-31
```

Use `--rekor-url <url>` or `WALTER_AUDIT_REKOR_URL` for a private Rekor
instance. The default URL is `https://rekor.sigstore.dev`.
