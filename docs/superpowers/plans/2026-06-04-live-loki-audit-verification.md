# Live Loki Audit Verification Implementation Plan

**Issue:** #332
**Parent:** #122
**Base PR:** #320 (`codex/issue-122-audit-loki-verify`)

## Goal

Extend `walter-os audit verify-chain --from-loki` beyond exported
`query_range` fixtures so operators can query their own Loki endpoint
directly, then verify the returned audit-chain rows with the existing local
hash-chain verifier.

## Scope

- Add live Loki querying to the existing `--from-loki` command.
- Accept a Loki URL from `--loki-url <url>` or `WALTER_AUDIT_LOKI_URL`.
- Support optional bearer auth via `WALTER_AUDIT_LOKI_TOKEN`.
- Bound network calls with timeout and limit controls.
- Keep fixture mode intact for offline tests and reviews.
- Document the operator workflow and token-handling expectations.

## Non-Goals

- Do not add Promtail, Grafana, or Loki provisioning changes in this PR.
- Do not add signed receipts or external root anchoring; #333 tracks that.
- Do not require live credentials in tests.

## Tasks

- [x] Add RED tests for live URL requirements, auth failures,
  unreachable Loki, malformed live responses, and token-safe output.
- [x] Implement live `query_range` calls with `curl`, date-to-range
  conversion, URL validation, timeout/limit validation, and shared response
  verification with fixture mode.
- [x] Update CLI parsing for `--loki-url` and mutual exclusion with
  `--mock-loki`.
- [x] Update docs and changelog to remove the fixture-only framing.
- [x] Run verification:
  `bats tests/walter/audit-chain-verify-from-loki.bats tests/walter/audit-chain-verify.bats tests/agents/audit-telemetry-dashboard.bats`;
  `bash -n bin/walter-os scripts/walter/lib/audit-chain.sh`;
  `shellcheck`;
  markdown/cross-reference lint; `git diff --check`.
- [ ] Commit, push, open a stacked PR, and request Copilot review.

## Verification Notes

The live tests replace `curl` with a temporary mock binary. The mock records
arguments so the tests can assert that the Loki endpoint, selector, and bearer
header are sent without requiring a real Loki service or leaking the bearer
token into command output.
