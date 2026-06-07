# Audit Chain Operations

Walter-OS writes tool-decision audit rows to:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/chain-YYYY-MM-DD.jsonl
```

When `jq` is available, rows are normalized as `jq -cS` JSON before local
verification. Minimal environments without `jq` can still append audit rows via
the fallback writer, but verification and close-day operations require `jq`.
The important integrity fields are:

- `prev_hash`: SHA-256 of the previous row's exact JSON bytes, or `"null"` for the first row of the day.
- `prev_chain_root`: previous day's root hash, present on the first row when the previous root exists.
- `row_hash`: SHA-256 of the row after deleting `row_hash` and `sig`.
- `sig`: Ed25519 signature over the canonical row after deleting only `sig`.
- `session_id`: session key id used to find the public key for verification.

The detailed schema and normalization rules live in
`docs/operational/audit-chain-format.md`.

## Verify Local Integrity

Verify one day:

```bash
walter-os audit verify-chain 2026-05-31
```

Close a day by writing or re-verifying its local root:

```bash
walter-os audit close-day 2026-05-31
```

Verify linked local days:

```bash
walter-os audit verify-chain --since 2026-05-31 --until 2026-06-01
```

## Opt Into Rekor

Rekor upload is off by default. Enable it only for the close-day command that
should publish the root:

```bash
WALTER_AUDIT_REKOR_UPLOAD=1 walter-os audit close-day 2026-05-31
```

Rekor anchoring only accepts past UTC audit dates. This prevents publishing a
root for a day that can still receive later audit rows.

Walter-OS also prepares bounded pending Rekor material whenever it updates a
daily root while the final row's session private key is still available. That
material lives beside the audit chain in `walter_audit_dir()`:

```text
${WALTER_AUDIT_DIR:-${WALTER_CONFIG:-$HOME/.config/walter-os}/audit}/root-YYYY-MM-DD.rekor.pending.json
```

It contains only the canonical root payload, payload digest, signature, public
key, session id, and metadata needed for upload. It does not contain the session
private key. If a scheduled next-day close job runs after session cleanup, the
same `close-day --rekor-url ... <date>` command can consume matching pending
material and upload the root without recreating the private key.

To use a private Rekor instance:

```bash
WALTER_AUDIT_REKOR_UPLOAD=1 \
  walter-os audit close-day --rekor-url https://rekor.example 2026-05-31
```

The local anchoring payload contains only:

```json
{
  "date": "YYYY-MM-DD",
  "operator": "<sha256-hashed operator id>",
  "root": "<daily-root-hex>",
  "walter_os_version": "<VERSION>"
}
```

Walter-OS hashes that payload, signs the SHA-256 digest with the last audit
row's session Ed25519 key, and submits the digest/signature/public key as a
Rekor `hashedrekord`. The JSON payload itself stays in the local receipt with
the Rekor entry id and response at:

```text
${WALTER_CONFIG:-$HOME/.config/walter-os}/audit/root-YYYY-MM-DD.rekor.json
```

Verify the local root against the Rekor entry:

```bash
walter-os audit verify-chain --check-rekor 2026-05-31
```

Use `--rekor-url <url>` or `WALTER_AUDIT_REKOR_URL` when verifying against a
private Rekor instance.

## Limits

This protects against local row edits, repaired local hash chains, fabricated
rows without the original session key, and deletion or replacement of a local
chain when the local receipt/root metadata or an external backup is retained.

This does not protect against a compromised session private key during the
session itself, a compromised host that signs malicious-but-valid rows, or a
missing external backup of local state and archived public keys. A Rekor
`hashedrekord` entry alone proves the payload digest was timestamped; it does
not recover the original `date`/`root` payload if the local receipt is lost.
