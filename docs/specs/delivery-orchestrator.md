# Delivery Orchestrator Agent

**Issue**: #226
**Roadmap**: AD-1 in `docs/specs/autonomous-delivery-roadmap.md`
**ADR**: `docs/decisions/0025-delivery-orchestrator-agent.md`

## Problem

Walter-OS has the building blocks for autonomous delivery: Council lanes,
subagents, feature-state, semantic gates, PR scoring, preview evidence, and
release checks. The missing AD-1 piece is a coordinator that sequences those
parts without becoming a super-agent with broad authority.

The Delivery Orchestrator needs a precise role model so `/full-cycle` and
future delivery automation can route work consistently. It must also make the
safety boundary obvious: coordination does not grant code-writing, self-review,
merge, deploy, secret, or production authority.

## Decision

Add `agents/delivery-orchestrator.md` as the first AD-1 contract slice. The
agent maps the Product, Architect, Builder, Tester, Security, Reviewer, and
Release roles onto existing Walter Council lanes and subagents. It owns stage
sequencing and evidence checks, while `.walter/features/<id>/state.yaml` remains
the persistent pipeline state.

## Acceptance Criteria

- [AC-1] Role map: the agent maps Product, Architect, Builder, Tester,
  Security, Reviewer, and Release to the existing triage, researcher, coder,
  reviewer, janitor, liaison, and specialized subagent surfaces.
- [AC-2] No execution authority: the agent contract explicitly says it does
  not write code, review its own diffs, merge PRs, or deploy.
- [AC-3] Fail-closed gates: missing, ambiguous, unreadable, or contradictory
  gate evidence blocks progression and escalates to a human.
- [AC-4] Feature-state ownership: the agent uses
  `.walter/features/<id>/state.yaml` and `walter-os feature-state` commands as
  the pipeline state owner.
- [AC-5] Tests validate the agent frontmatter, role map, safety boundary,
  fail-closed gate language, and active spec index entry.

## Non-Goals

- No new runtime scheduler.
- No auto-merge, production deploy, preview deploy, or credential minting.
- No changes to existing Council lane behavior.
- No replacement for the `architect`, `implementer`, `reviewer`,
  `security-auditor`, or `tech-writer` subagents.

## Related

- `docs/specs/autonomous-delivery-roadmap.md`
- `docs/specs/feature-state-ledger.md`
- `docs/decisions/0025-delivery-orchestrator-agent.md`
