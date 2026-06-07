# Capability Tokens

Walter-OS capability tokens are short-lived, session-scoped assertions that
bound what a tool may do during sensitive operations. They layer above the
approval gate: approval decides whether an operation may proceed at all, while
capability tokens prove the current session has the narrow filesystem or command
scope required for high-tier work.

Runtime state lives under `~/.config/walter-os/state/`:

- `session-<session>.json` records the active session and capability paths.
- `session-<session>.key` is the private signing key and must be mode `0600`.
- `caps-<session>/cap-<nonce>.paseto` stores minted capability tokens and each
  token file must be mode `0600`.

The daily supply-chain audit checks this state for stale `caps-*` directories,
malformed session JSON, loose token-file permissions, and exposed signing-key
permissions. Stale token directories are informational cleanup findings. Token
files with broader permissions are high severity. Private signing keys with
broader permissions are critical because they can sign new capability tokens for
the session.

When a finding appears, prefer ending the stale session or revoking and re-minting
the capability. For simple permission drift, `chmod 600` on the named key or
token file is acceptable after confirming the file belongs to the current
session.
