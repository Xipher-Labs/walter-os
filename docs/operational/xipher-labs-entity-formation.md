# Xipher Labs Legal Entity — Formation Runbook

**Status**: Active runbook
**Related ADR**: [docs/decisions/0022-xipher-labs-legal-entity.md](../decisions/0022-xipher-labs-legal-entity.md)
**Related issues**: #156
**Owner**: Operator (external action)

This runbook tracks the steps required to constitute Xipher Labs as a
legal entity. Per ADR-0022, this is a **hard gate** before any external PR
is merged: contributor grants (via CLA, ADR-0019) and commercial licensing
(ADR-0018) only have unambiguous legal standing once the entity holds the
copyright.

## Why this matters

The repo currently attributes copyright to "Xipher Labs" as a trade name. As
long as no legal entity exists, the operator personally is the copyright
holder of record. That posture is workable for solo development (the
operator can grant + relicense unilaterally), but it breaks down as soon as:

- An external contributor PR lands — their grant goes to "Xipher Labs", which
  legally means the operator personally; if the operator ever exits the
  project, the grants are stranded.
- A commercial license is signed — the contract counterparty needs an entity
  to contract with.
- IdeaOS (the commercial SaaS) launches — it needs a corporate vehicle to
  invoice, hold IP, and limit liability.

## Phases

Phase progress is tracked in this file. The operator updates the status
checkboxes as each phase completes.

### Phase 0 — Prerequisites (operator decisions) — COMPLETE

- [x] Jurisdiction chosen: **Argentina**.
- [x] Entity name + form chosen: **Xipher Labs S.R.L.** (Sociedad de
  Responsabilidad Limitada). The operator picked S.R.L. over the
  ADR-0022-recommended S.A.S. for legal/tax reasons specific to their
  situation. The "S.R.L." form is well-established, partner-friendly, and
  works for the Walter-OS / IdeaOS dual-product plan.
- [x] Registered address chosen (operator-private, not in repo).
- [x] Lawyer engaged for the CLA review (ADR-0019 migration §1). Review
  still pending; CLA gate stays inactive until lawyer signs off.

### Phase 1 — Entity registration — COMPLETE

- [x] Entity registered with Argentine registry. Xipher Labs S.R.L. is the
  constituted legal entity.
- [x] Filing fees paid.
- [x] Entity confirmation + CUIT received (CUIT stored in operator's
  overlay `~/.config/walter-os/overlay/personal.env` as
  `WALTER_LEGAL_ENTITY_CUIT`, never committed).
- [x] Entity bank account open (or in process — non-blocking for repo work).

Phase 2 (repo updates) is in flight via the PR that adds this update.

### Phase 2 — Repo updates (this PR)

- [x] `NOTICE`: attribution updated to `Xipher Labs S.R.L.`; "entity is
  being constituted" paragraph rewritten to reflect the constituted entity.
- [x] `COMMERCIAL.md`: "Operator-side caveat" replaced with a "Contracting
  entity" section naming Xipher Labs S.R.L.
- [x] `CLA.md`: Owner attribution updated; STATUS NOTE rewritten to flag
  that only the lawyer-review gate remains (Phase 3); governing-law clause
  names Argentine Republic as the constituted-entity jurisdiction.
- [x] README's License section already names Xipher Labs; no change needed
  in the body (the legal entity name lives in NOTICE / COMMERCIAL.md / CLA).
- [x] This runbook: Phase 0 + Phase 1 marked complete, Phase 2 status
  updated below.

The STATUS NOTE in `CLA.md` is intentionally NOT removed yet — that is
Phase 3, gated on lawyer sign-off per ADR-0019 migration §1.

### Phase 3 — CLA activation (post-entity-formation, post-lawyer-review)

- [ ] Lawyer signs off on `CLA.md` text.
- [ ] Operator removes the "STATUS NOTE" block from `CLA.md` (separate
  cleanup PR).
- [ ] Operator signs the CLA retroactively on a test PR or via direct
  insertion into the signatures branch.
- [ ] `gh variable set WALTER_CLA_ACTIVE --body 'true'` flips the workflow on.
- [ ] Verify on a test PR: the CLA Assistant bot posts a signature request +
  blocks merge until signed.

### Phase 4 — External PR merge gate unlocked

- [ ] External PRs can now be accepted. Add a tracking comment to the
  oldest open external PR (if any) explaining the gate is now lifted.

## Pre-merge external-PR check (advisory hook)

`hooks/external-pr-merge-gate.sh` is an advisory check that the operator
can wire into their pre-merge workflow (or run manually). It checks for
the presence of the constituted-entity marker file at
`~/.config/walter-os/overlay/entity-formed` and refuses to confirm if it
is missing.

The hook is opt-in — it is not registered in `.claude/settings.json` by
default because the gate is operator-policy, not a Walter-OS contract
guarantee. Operators who want enforcement add the hook reference to their
overlay settings.

## Template — "post-formation repo update" PR

When the operator gets here, this template generates the Phase 2 PR.
Note: this template is left in place as a reference for any FUTURE
post-formation attribution updates (e.g., if the entity is ever
re-domiciled or renamed). The first Phase 2 PR was #165 which constituted
Xipher Labs S.R.L. — replace the entity name + date in the template if
re-using it.

```
Title: [CHORE] -COMPLIANCE- update repo attribution post entity formation (ADR-0022)

Body:
Closes the post-formation half of #156. The Xipher Labs S.R.L. legal
entity was constituted on YYYY-MM-DD per ADR-0022 phase 1. This PR
updates the repo's attribution to the constituted entity.

Diff scope (all single-line attribution edits):
- NOTICE: name the entity, drop the "being constituted" paragraph
- COMMERCIAL.md: drop the "operator-side caveat" paragraph
- CLA.md: replace STATUS NOTE block with constituted-entity attribution
- README: License section names the entity
- docs/operational/xipher-labs-entity-formation.md: mark phases 1+2 complete

Tests:
- tests/oss/license-files.bats already verifies NOTICE/COMMERCIAL.md
  reference ADR-0018 — no change required.
- tests/oss/cla-gate.bats already verifies the workflow gate — no change
  required until CLA activation (separate PR).

Refs: docs/decisions/0022-xipher-labs-legal-entity.md
```

## Status snapshot

| Phase | Status |
|---|---|
| Phase 0 — prerequisites | **complete** (entity form chosen: S.R.L.) |
| Phase 1 — registration | **complete** (Xipher Labs S.R.L. constituted) |
| Phase 2 — repo updates | **complete** (this PR) |
| Phase 3 — CLA activation | pending (blocked by lawyer review of CLA.md) |
| Phase 4 — external PRs unlocked | pending (blocked by Phase 3) |

The operator updates this table as phases complete. CI does NOT enforce
phase completion — the gate is operator-policy.
