# Capability Tokens

Walter-OS capability tokens are short-lived, session-scoped assertions that
bound what a tool may do during sensitive operations. They layer above the
approval gate: approval decides whether an operation may proceed at all, while
capability tokens prove the current session has the narrow filesystem or command
scope required for high-tier work.

Runtime state lives under `~/.config/walter-os/state/`:

- `session-<session>.json` records the active session and capability paths.
- `session-<session>.key` is the private signing key and must be mode `0600`.
- `session-<session>.pub` is the public verification key.
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

## Common Workflow

Most sessions should not need manual capability work. Trusted skill defaults are
loaded from the operator overlay and mint narrow, time-boxed capabilities at
session start. When an agent needs a high-tier operation outside those defaults,
mint the capability from the operator terminal, not from inside the agent:

```bash
walter-os cap mint Bash --patterns '^[[:space:]]*nuclei([[:space:]]|$)' --duration 4h
walter-os cap list
walter-os cap revoke <nonce>
```

If session state becomes stale or malformed, restart the session from the
operator terminal:

```bash
walter-os session restart [repo-path]
```

## Troubleshooting

`cap-cleanup-stale` means a `caps-*` directory no longer has a matching active
session state file. Confirm no agent session is using it, then remove the stale
directory.

`cap-state-malformed` means the session JSON is invalid, incomplete, or points at
paths that do not match its `session_id`. Restart the session. If the state file
was edited manually, remove it and let Walter-OS recreate it.

`cap-state-missing` means the session JSON points at a missing key or token
directory. Restart the session, then re-mint any capability still needed.

`cap-token-perms` means a token file is broader than mode `0600`. Fix it with
`chmod 600 <token-file>` or revoke and re-mint the token.

`cap-key-perms` means the private signing key is broader than mode `0600`. Treat
this as critical: end the session, remove stale capability material, restart the
session, and re-mint only the capabilities still required.

## PASETO v4 Primer

Walter-OS uses PASETO v4 public-style tokens for capability assertions. The
session private key signs claims such as tool, session, allowed paths, allowed
network hosts, command patterns, issue time, expiry, and nonce. The public key
lets hooks verify those claims without trusting mutable local text files.

For operators, the important properties are:

- Tokens are scoped to one session and expire.
- Tokens are signed; editing the token invalidates it.
- The private session key can sign new tokens, so it must stay mode `0600`.
- Capabilities do not replace the approval gate or OS permissions; they add a
  narrow proof that the current high-tier operation is within the minted scope.
