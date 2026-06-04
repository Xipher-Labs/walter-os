# Signed audit rows implementation plan

## Scope

This PR implements the first #333 slice only: per-row Ed25519 signatures on new
audit-chain rows and signature verification in `walter-os audit verify-chain`.

## Non-goals

- `walter-os audit close-day`
- `verify-chain --since`
- Rekor upload/check
- automatic public-key archive rotation

## Tasks

1. Add failing tests for `sig` emission, signature tamper, missing public key,
   and archive public-key lookup.
2. Reuse the existing A-2 session Ed25519 key material from
   `scripts/walter/lib/session-state.sh` to sign canonical rows.
3. Extend the verifier to validate `sig` after row hash and chain checks.
4. Update audit-chain docs and the changelog.
5. Run Bats, shell syntax, ShellCheck, markdown lint, and diff checks.
