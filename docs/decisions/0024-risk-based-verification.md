# ADR-0024: Risk-based verification + prototype mode

**Status**: Proposed
**Date**: 2026-05-24
**Deciders**: Operator
**Refines**: the tiny/small/major rigor system (AGENTS.md)
**Part of**: `docs/specs/autonomous-delivery-roadmap.md` (AD-8)

## Context

Walter-OS classifies every task `tiny` / `small` / `major` and requires TDD
(RED → GREEN → REFACTOR) for `small`+ and full SDD/TDD + DoD validator for
`major`. The classification today is **category-based** (LOC thresholds + a
list of auto-escalate triggers like auth/money/PHI). It is not **risk-based**
(probability × blast-radius), and it has no explicit fast lane for
hackathons / prototypes / MVP exploration where speed legitimately matters more
than production-grade coverage.

The handoff proposal asked for a "TDD-light" mode. "Light" is the wrong frame —
it sounds like "less discipline." The right frame is **verification
proportional to risk**.

## Decision

Adopt **risk-based verification** with three explicit modes, selected per repo
via `walter-repo-config.yaml` (`verification:` key; ADR-0026):

1. **`prototype`** — for hackathons, demos, MVP exploration. Required:
   - lint
   - typecheck
   - smoke test
   - critical-path test
   - screenshot validation for UI changes
   Not required: full TDD, exhaustive E2E, mutation testing. This is NOT "no
   tests" — it is "the tests that catch the demo breaking."

2. **`risk_based`** (default) — verification depth scales with the change's
   risk score = probability-of-defect × blast-radius. Low-risk changes
   (docs, internal tooling, non-destructive refactor) get prototype-level
   checks; high-risk changes (auth, money, schema, PHI) get full SDD/TDD +
   security review automatically, regardless of LOC.

3. **`production`** — full SDD/TDD + acceptance + integration + regression +
   migration tests + security checks + rollback plan, for every change. The
   strictest mode; the current `major`-rigor behavior applied universally.

4. **The auto-escalate floor still applies in every mode.** Any change touching
   auth / crypto / money / PHI / production DB migration / hooks / AGENTS.md /
   install.sh escalates to full verification EVEN in `prototype` mode. The
   prototype mode relaxes the *default* depth, not the *floor*.

## Consequences

- **Positive**: hackathon repos move fast without pretending production
  software is being shipped; production repos get uniform rigor; most repos sit
  in `risk_based` and get the right depth automatically.
- **Positive**: composes with capability tiers (ADR-0023) + Walter Score
  (AD-11) — a `prototype`-verified change can never reach a high capability
  tier or a high Walter Score, so it can't policy-auto-merge to a protected
  branch.
- **Negative / cost**: the risk-scoring function (probability × blast-radius)
  needs a concrete, testable definition — the AD-8 spec must pin how risk is
  computed (file globs, change-type classification, dependency-graph reach) so
  it's deterministic, not vibes.
- **Relationship to rigor levels**: tiny/small/major stays as the *task
  classification*; verification mode is the *depth applied*. A `major` task in
  a `prototype` repo still needs a spec (SDD), but its tests can be
  prototype-level UNLESS the auto-escalate floor fires.
