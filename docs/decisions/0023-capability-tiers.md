# ADR-0023: Capability tiers (evidence-based agent capability)

**Status**: Proposed
**Date**: 2026-05-24
**Deciders**: Operator
**Extends**: ADR-0009 (per-agent trust tiers)
**Part of**: `docs/specs/autonomous-delivery-roadmap.md` (AD-7)

## Context

ADR-0009 introduced per-agent **trust tiers** (low/medium/high) that gate which
`approval-gate.sh` categories each agent can auto-approve. The framing —
"trust" — implies an agent *earns* discretion the way a human colleague does,
and that we *grant more trust over time*. The Autonomous Delivery roadmap
explicitly rejects "trust the agent more over time and reduce safety
automatically" (handoff §19) as an anti-pattern.

As Walter-OS moves toward higher autonomy, the question "how much can this
agent do in this repo?" should be answered by **objective evidence about the
repo + the change**, not by a subjective trust score that drifts upward.

## Decision

Introduce **capability tiers** as the evidence-based successor to trust tiers.

1. **Capability is computed, not granted.** An agent's effective capability in
   a given repo is `min(repo_ceiling, evidence_tier(change))` where:
   - `repo_ceiling` = `capability_tier_ceiling` from `walter-repo-config.yaml`
     (operator-set per repo; ADR-0026).
   - `evidence_tier(change)` is derived from objective signals:
     CI reliability, test coverage, sandboxing present (#122 A-3),
     rollback strategy present, branch protections, network egress allowlist
     configured, historical PR quality, and the change's own risk class.

2. **Tier levels** (names, not numbers-as-trust):
   - `0 — read_only` — read, search, comment. No writes.
   - `1 — assisted` — create branch, implement, run tests, open PR. Human
     merges.
   - `2 — supervised_autonomy` — all of tier 1 + deploy preview. Human
     approves merge to default branch + production deploy.
   - `3 — bounded_autonomy` — all of tier 2 + policy-based auto-merge to
     non-protected branches when gates pass. Production deploy + secrets +
     schema migrations ALWAYS require human approval.

3. **The hard-limit floor is below all tiers.** No capability tier — not even
   tier 3 — can perform the `approval-gate.sh` "blocked for ALL tiers" actions.
   Capability tiers gate the *discretionary* surface only.

4. **Backwards compatibility.** The existing `trust-tiers.yml` (reviewer=high,
   triage/researcher/coder=medium, liaison/janitor=low) maps to capability
   tiers as a starting point; the roadmap's AD-7 implements the evidence-based
   computation. Until AD-7 ships, capability tier == the static trust tier.

## Consequences

- **Positive**: autonomy graduation is defensible + auditable ("this repo
  reached tier 3 because it has CI + coverage + sandboxing + rollback", not
  "the agent seemed reliable"). Aligns with the bounded-blast-radius
  positioning.
- **Positive**: the per-repo `capability_tier_ceiling` lets the operator cap a
  risky repo at tier 1 regardless of evidence.
- **Negative / cost**: computing `evidence_tier` requires the repo to expose
  the signals (CI status, coverage report, sandbox config). Repos that don't
  surface them stay at low tiers — which is the safe default, but may surprise
  operators expecting more autonomy.
- **Migration**: ADR-0009's "trust tier" vocabulary is superseded in docs +
  CLI output; the YAML key may stay `trust-tiers.yml` for one release with a
  deprecation note, then rename to `capability-tiers.yml`.
