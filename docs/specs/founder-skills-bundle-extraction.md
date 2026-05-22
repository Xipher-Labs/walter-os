# Founder-Skills Bundle: Extract or Stay In-Tree?

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-08

## Problem

Walter-OS ships a founder-skills bundle: `track-pending`,
`terms-policy-generator`, `legal-doc-review`, `financial-plan-builder`,
`hiring-toolkit`, and the `skills/founder-skills/INDEX.md` skill that
orchestrates the bundle. The README's "What's new since v0.3.0" section
highlights this as a significant addition.

The operator's strategic plan identifies this bundle as a potential product
in its own right: "If you extract it as a separate repo with a decent landing
page, you could have independent traction." At the same time, keeping it in
the walter-os tree has advantages: it gets the same CI, the same review loop,
and the same distribution channel.

This spec evaluates the options and makes a recommendation. It does NOT
implement either option.

## Options evaluated

### Option A: Extract to `xipher-labs/founder-skills`

A separate repository with its own README, its own landing page focus, and
its own release cadence. The skills are imported into walter-os as a git
submodule or as a dependency declared in the skills catalog.

**Pros:**
- Clean separation lets the bundle be marketed to operators who don't want
  the full Walter-OS framework — just the legal, financial, and hiring AI workflows.
- The repo's README can be focused on founder use cases (no agent contract
  jargon, no talk of hooks or MCP servers).
- Stars and issues are separate from walter-os, giving an independent measure
  of traction.
- The bundle can be licensed differently (e.g., MIT) to maximize adoption
  without affecting walter-os's AGPL license.

**Cons:**
- Adds a cross-repo dependency to maintain. When walter-os's skill format
  changes, the extracted bundle also needs updating.
- Increases operational overhead: two CI pipelines, two release processes, two
  sets of issues.
- The bundle's value is partly in its integration with the rest of walter-os
  (using `track-pending` with Plane, `legal-doc-review` with the wiki, etc.).
  Separate extraction weakens this integration story.
- At v0.4.5-alpha with one maintainer, extraction is premature — it doubles
  maintenance surface before the base repo is stable.

### Option B: Stay in-tree, improve discoverability

The bundle stays in `skills/founder-skills/`. The marketing surface is
improved: a `docs/founder-skills.md` landing-style document, a dedicated
section in the README, and a mention in the README hero section as a "complete
GTM toolkit for technical founders."

**Pros:**
- Zero additional operational overhead.
- The bundle continues to benefit from walter-os CI, review loop, and
  distribution.
- Integration with other walter-os capabilities is natural and documented.
- Adopters get the bundle automatically as part of Tier I → II install.

**Cons:**
- Harder to market independently. A founder who finds the bundle via a search
  for "AI legal document review" will land on the walter-os README, not on
  a focused founder-skills page.
- The bundle's presence in a "full AI agent framework" repo may feel
  overwhelming to non-technical founders who just want the legal/financial
  tools.

## Recommendation: Option B — stay in-tree with improved discoverability

**Do not extract.** At v0.4.5-alpha, the maintenance cost of a separate repo
is not justified by the traction differential. The discoverability gap is real
but solvable in-tree:

1. Add a `docs/founder-skills-guide.md` that serves as a focused landing
   document: what each skill does, the workflow for a typical founder use case,
   and a 5-minute setup path. This document can be linked from external
   marketing channels.
2. Add a "Founder-skills" section to the README with a dedicated callout
   before the full skills catalog table.
3. Add `skills/founder-skills/` as a named section in `skills/INDEX.md` with
   a one-line summary for each skill.

**Revisit extraction criteria:** Extract if and when:
- The bundle has >500 GitHub stars attributed to it (via issue feedback or
  attribution data), OR
- More than 20% of walter-os adopters use only the founder-skills subset
  without needing the rest of the framework, OR
- A non-technical founder audience requests a simpler entry path that
  walter-os's framework complexity actively prevents.

## Acceptance Criteria

- [AC-1] This spec records the decision to maintain in-tree with the
  extraction criteria above, so the decision can be revisited objectively.
- [AC-2] `docs/founder-skills-guide.md` exists as a focused, jargon-light
  document covering: what the bundle is, the five skills with one-paragraph
  each, and a quick-start path (Tier I install → paste the INDEX skill →
  run the first skill).
- [AC-3] The README has a "Founder-skills bundle" callout section (not buried
  in the skills catalog table) that links to `docs/founder-skills-guide.md`.
- [AC-4] `skills/INDEX.md` has a dedicated "Founder-skills" subsection that
  lists all five skills with one-line descriptions.

## Non-goals

- Building a landing page for the bundle. That is marketing work outside this
  repo's scope.
- Extracting the bundle. This spec explicitly recommends against it for now.
- Changing the bundle's license. That is ADR-0018 scope.

## Open questions

- Q1: Should `docs/founder-skills-guide.md` be written for a technical or
  non-technical audience? Recommendation: technical-leaning but accessible —
  the core walter-os audience is a technical founder. Non-technical founders
  are IdeaOS's audience, not walter-os's.

## References

- `skills/founder-skills/INDEX.md` — the bundle entry point
- `skills/founder-skills/` — all skill files
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-8
