# 0020. Repo split: walter-contract vs walter-host — rejected, maintain monorepo

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/walter-contract-walter-host-split.md`

## Context

The operator's strategic plan proposed splitting `walter-os` into two
repositories:
- `xipher-labs/walter-contract` — agent contract layer (AGENTS.md cascade,
  skills, hooks, agents, commands, MCP profiles)
- `xipher-labs/walter-host` — Docker Compose service stack (25+ services)

The audit finding motivating the proposal: the README presents walter-host as
optional ("most adopters never deploy it") but the most interesting feature,
the Walter Council, requires Plane and LiteLLM from the host stack. This
narrative inconsistency reduces credibility.

The spec at `docs/specs/walter-contract-walter-host-split.md` evaluated the
trade-offs in full.

## Decision

**Reject the split. Maintain the monorepo.**

The correct fix for the audit finding is documentation and narrative clarity,
not repo restructuring. Specifically:

1. The README is restructured to lead with the contract layer. The host stack
   documentation is placed no earlier than line 500. A new "Without walter-host"
   section explicitly documents the Council's host dependency as an
   architectural choice with bypass options (hosted Plane SaaS + hosted
   LiteLLM proxy).

2. A `setup/walter-host/README.md` is added as the dedicated entry point for
   host-stack adopters.

3. The monorepo is maintained with a clear directory-level license structure
   (ADR-0018) that achieves the license differentiation goal without a repo split.

4. This decision is revisited at v1.0 stable release. The trigger for
   revisiting: more than one active maintainer contributing to both layers,
   OR release cadences that diverge significantly (contract layer releases
   weekly, host stack releases monthly).

## Consequences

**Positive:**
- No cross-repo coordination overhead for the current one-maintainer stage.
- The four-tier install story (`install.sh` as single entry point) is preserved.
- The OSS Trust roadmap, the review loop, and the skills catalog continue to
   benefit from one CI pipeline and one review cycle.
- Directory-level SPDX headers achieve license differentiation without the
  split.

**Negative:**
- The "intimidating 25-service stack" problem remains visible in the monorepo.
  Mitigated by README restructuring but not eliminated.
- The Council's coupling to the host stack is documented but not architecturally
  separated. A future contributor to the contract layer must understand the
  boundary.

**Revisit trigger (explicit):**
At v1.0 stable release, re-evaluate the split if:
- More than one active maintainer contributes to both layers in the same release
  cycle, creating merge conflicts from parallel work.
- The host stack's release cadence has diverged: contract layer is stable and
  the host stack still has breaking changes frequently.
- The Council is refactored to support pluggable backends (hosted Plane,
  GitHub Issues, etc.) — at that point, the coupling is no longer an issue.

## Alternatives considered

**A — Proceed with the split (rejected)**

The split was the operator's initial proposal. Evaluated and rejected because:

- Cross-repo dependency coordination for one maintainer at v0.4.5-alpha is
  operationally expensive without proportional benefit.
- The `install.sh` single-entry-point install story breaks if the contract and
  host are in separate repos.
- The Council's coupling to Plane/LiteLLM becomes a cross-repo coupling, which
  is harder to document and manage than an in-repo boundary.
- License differentiation is achievable with directory-level SPDX headers.
- The split's primary benefit (separate README landing pages) is achievable
  with `setup/walter-host/README.md` without the operational cost.

**B — Partial split: extract `setup/walter-host/` only (rejected)**

Move `setup/walter-host/` to a separate repo while keeping everything else
in `walter-os`. This achieves the README clarity goal without splitting the
contract layer.

Rejected because:
- The host stack's compose files reference shared patterns from the repo root
  (env conventions, the overlay system). Extraction requires duplicating or
  re-sourcing those references.
- The Walter Council agent definitions (in `agents/`) reference Plane and
  LiteLLM. Those definitions would stay in `walter-os` but reference a service
  stack in a different repo — creating the same cross-repo coupling problem.
- Still requires coordinated releases when the Council API changes alongside
  the host stack configuration.

## Migration

No migration required. The monorepo is maintained as-is, with the following
documentation additions (the "do instead" list from the spec):

1. Restructure README so host stack content begins no earlier than line 500.
2. Add `docs/operational/council-without-walter-host.md`.
3. Add `setup/walter-host/README.md`.
4. Directory-level SPDX licensing per ADR-0018.

## References

- ADR-0018 — licensing strategy (achieves license differentiation in-repo)
- `docs/specs/walter-contract-walter-host-split.md` — full evaluation spec
- `docs/specs/walter-os-oss-readiness-roadmap.md` — roadmap context
