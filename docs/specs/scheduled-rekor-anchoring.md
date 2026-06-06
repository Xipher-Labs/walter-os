# Scheduled Rekor anchoring

## Problem

The live Rekor anchoring flow signs the daily root digest during
`walter-os audit close-day --rekor-url ...`. That works only while the final
audit row's session private key still exists. Walter-OS intentionally removes
session private keys at session end, so a next-day scheduled close job cannot
anchor yesterday's final root without either weakening key cleanup or failing.

## Decisions

- Create bounded pending Rekor material whenever a day's root is written while
  the final row's session private key is still available.
- Store only canonical payload, payload digest, Ed25519 signature, public key,
  final session id, and root metadata. Never persist the private key.
- Refresh pending material whenever the root changes.
- Let `walter-os audit close-day --rekor-url ... <date>` consume matching
  pending material when the private key is no longer available.
- Keep online signing as the fallback when no matching pending material exists
  and the private key is still available.

## Acceptance Criteria

- A next-day scheduled `walter-os audit close-day --rekor-url ... <yesterday>`
  can upload without the final session private key present.
- No session private key persistence is introduced.
- Pending material is refreshed when the day's root changes.
- Stale pending material is rejected before network upload.
- `verify-chain --check-rekor` still binds the anchor to the expected final
  root and public key.

## Plan

1. Add failing Bats coverage for pending material generation, scheduled upload
   after private-key cleanup, and stale material rejection.
2. Add pending material path/read/write helpers in
   `scripts/walter/lib/audit-chain.sh`.
3. Refresh pending material after successful root writes while the private key
   is available.
4. Update Rekor upload to use matching pending material when live signing is no
   longer possible.
5. Run the Rekor, audit-chain, hook integration, ShellCheck, syntax, and diff
   checks used by the parent Rekor PR.
