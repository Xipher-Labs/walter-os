# Audit Chain Close-Day and Range Verification Plan

## Scope

Implement the local AC-4 slice of issue #333:

- `walter-os audit close-day [date]`
- `prev_chain_root` on the first row of a day when the previous daily root exists
- `walter-os audit verify-chain --since <date> [--until <date>]`

Rekor anchoring remains out of scope for this slice.

## Acceptance

- A clean day can be closed after verification and writes `root-YYYY-MM-DD.txt`
  as `sha256(last_row)`.
- Closing an already-rooted day verifies the existing root and refuses to
  overwrite a mismatch.
- The first row of day N includes the previous day's root verbatim when present.
- `verify-chain --since` verifies days in inclusive date order.
- Cross-day root mismatches fail with the affected date.

## Verification

- `bats tests/walter/audit-chain-append.bats tests/walter/audit-chain-verify.bats`
- `bats tests/walter/audit-chain-verify-from-loki.bats tests/hooks/audit-chain-hook-integration.bats`
- `bash -n bin/walter-os scripts/walter/lib/audit-chain.sh`
- `shellcheck -e SC1091,SC2155 bin/walter-os scripts/walter/lib/audit-chain.sh tests/walter/audit-chain-verify.bats`
- `./tests/lint-cross-references.sh`
- `npx --yes markdownlint-cli2 CHANGELOG.md docs/operational/audit-chain-format.md docs/specs/audit-chain-merkle-and-receipts.md docs/specs/audit-chain-close-day.plan.md`
