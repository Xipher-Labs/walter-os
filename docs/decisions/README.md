# docs/decisions — Architecture Decision Records

ADRs record decisions that are hard to reverse or have significant trade-off
surface. Each file follows the format: context, decision, consequences,
alternatives considered.

| ADR | Title | Status |
|---|---|---|
| [`0008-control-tower-stack.md`](0008-control-tower-stack.md) | Control Tower Stack — Next.js 16 App Router + SSE for the Walter Council browser dashboard | Proposed |
| [`0009-agent-trust-tiers.md`](0009-agent-trust-tiers.md) | Agent Trust Tiers — per-agent `low`/`medium`/`high` tiers that determine `approval-gate.sh` auto-allow behavior | Proposed |
| [`0010-oss-license.md`](0010-oss-license.md) | OSS License — AGPLv3 (Xipher Labs) | Accepted |
| [`0011-depersonalization-strategy.md`](0011-depersonalization-strategy.md) | Depersonalization Strategy — Dual-Layer Overlay | Proposed |
| [`0012-oss-security-hardening-primitives.md`](0012-oss-security-hardening-primitives.md) | OSS Security Hardening Primitives — v0.1 | Proposed |

## Adding a new ADR

1. Copy the structure from an existing ADR.
2. Number sequentially: next is `0013-...`.
3. Status starts as `Proposed`; update to `Accepted` when the implementing PR merges.
4. Add a row to this table in the same PR.
