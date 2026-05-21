---
name: founder-skills-index
description: Catalogue of the founder-skills bundle (v0.4.0 epic #4). Use when the operator asks "what founder skills do I have", when picking which skill to apply for a given founder task, or as the entry point for a new contributor learning the bundle. Lists each skill in the bundle, what it does, when to use it, and how the skills compose for common workflows.
---

# Founder-skills index

The v0.4.0 founder-skills bundle (epic #4) is six skills that
together cover the artifacts every founder produces in the first
12 months of a company. Each skill is a guide (not a runnable
script), each owns one artifact category, and each composes with
the others.

## Skills in the bundle

| Skill | Owns | Triggers on |
|---|---|---|
| `track-pending` (#10) | The `walter-pending.md` ledger of deferred work | "track this", "defer this", "out of scope", "follow-up" |
| `legal-doc-review` (#5) | The reading guide for contracts you don't send to a lawyer | "review this NDA", "vendor T&Cs", "MSA review", "term sheet" |
| `terms-policy-generator` (#6) | Draft Terms / Privacy / Cookies from a YAML spec | "draft terms of service", "privacy policy", "cookies policy" |
| `financial-plan-builder` (#7) | 12-month cash projection from a YAML config | "runway", "projection", "burn", "cash plan", "financial model" |
| `hiring-toolkit` (#8) | Job description + interview rubric + offer letter from a role spec | "hiring", "open a role", "JD", "interview rubric", "offer letter" |
| `founder-skills` (this file, #25) | The index + cross-skill workflows | "what founder skills", "how do these skills compose" |

## Composition — common founder workflows

### Workflow 1 — Open a new role

1. **`financial-plan-builder`** — add the new role to `hiring_plan`
   in `finances/plan.yml`; re-run to confirm the runway impact is
   acceptable.
2. **`hiring-toolkit`** — write `hiring/<role>/spec.yml`; generate
   the JD + rubric + offer-letter template.
3. **`legal-doc-review`** — once per jurisdiction, review the
   generated offer-letter template with counsel before first use.
4. **`track-pending`** — file a TP entry for any role-specific
   customization that should make it back into the template
   (e.g., "this take-home worked, codify it").

### Workflow 2 — Launch a public-facing service

1. **`terms-policy-generator`** — draft Terms / Privacy / Cookies
   from `legal/<project>/spec.yml`.
2. **`legal-doc-review`** — review the generated drafts with
   counsel.
3. **`landing-page-fast`** (existing skill) — build the marketing
   site that links to the published policy URLs.
4. **`oss-readiness`** (existing skill) — pre-launch audit.
5. **`track-pending`** — file TP entries for any deferred items
   (e.g., "add a Brazil-specific LGPD section after first BR
   customer").

### Workflow 3 — Review a customer MSA before signing

1. **`legal-doc-review`** — triage the MSA into PROBLEM / QUESTION /
   OK sections.
2. **`financial-plan-builder`** — if the deal materially changes
   cash flow (large enterprise contract), model it in
   `finances/plan.yml`.
3. **`track-pending`** — file TP entries for any QUESTION items
   that need counterparty follow-up.

### Workflow 4 — Quarterly planning

1. **`financial-plan-builder`** — refresh the 12-month projection
   with actuals from the last quarter.
2. **`saas-metrics-dashboard`** (existing skill) — backward-looking
   metrics: MRR, ARR, churn, LTV/CAC.
3. **`vc-evaluator`** (existing skill) — if a raise is on the
   horizon, rehearse investor pushback against the projection.
4. **`track-pending`** — review the deferred ledger; resolve or
   re-defer everything that crossed its `defer-until` trigger.

### Workflow 5 — End-of-quarter board update

1. **`financial-plan-builder`** — `summary.md` is the financial
   section of the board update.
2. **`saas-metrics-dashboard`** — produces the metrics section.
3. **`content-writer`** (existing skill) — draft the narrative
   sections between the metrics + financials.
4. **`track-pending`** — surface the high-severity TP entries the
   board should see.

## How to apply this skill

Whenever the operator asks "what founder skills do I have" or "how
do these skills compose", this skill is the entry point. It does
not produce artifacts itself — it points at the right sibling
skill for the task at hand.

For a fresh contributor reading the bundle for the first time, the
recommended read order is:

1. `track-pending` — establishes the convention used by the others.
2. `financial-plan-builder` — the numbers underpin every other
   decision.
3. `hiring-toolkit` — costs flow back into the financial plan.
4. `legal-doc-review` + `terms-policy-generator` — the legal pair
   (consume / produce).
5. This file (the index) — composition patterns.

## Hard rules

- **Each skill in the bundle is a guide, not a runnable script.**
  Same shape as `postgres-cli` / `syncthing-cli` / `readme-craft`.
- **Each skill emits drafts, not finals.** Operator (and counsel
  for the legal pair) review before publication / signing.
- **Each skill cross-references the others** in the bundle, so
  the operator can navigate the bundle from any starting point.
- **No skill in the bundle assumes a specific jurisdiction**.
  `terms-policy-generator` and `hiring-toolkit` adapt to the
  configured jurisdiction; `legal-doc-review` and
  `financial-plan-builder` are jurisdiction-neutral.

## Validation

`tests/oss/founder-skills.bats` and
`tests/oss/founder-skills-extension.bats` validate that:

- Each skill file has valid frontmatter (`name`, `description`).
- The depersonalization grep passes for every skill in the bundle.
- Cross-references between the skills resolve (no broken paths).
- The bundle index lists every skill in the bundle.

## References

- Walter-OS execution plan Phase 4.
- Epic #4 — founder-skills extension roadmap.
- Existing skills referenced in the workflows: `landing-page-fast`,
  `oss-readiness`, `saas-metrics-dashboard`, `vc-evaluator`,
  `content-writer`.
