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

### Phase 0 — Prerequisites (operator decisions)

- [ ] Choose jurisdiction. Recommendation per ADR-0022: **Argentina SAS**
  (fast, cheap, online registration, fits a bootstrapped solo founder). See
  ADR-0022 §Decision for alternatives.
- [ ] Choose entity name. Default: `Xipher Labs S.A.S.` (matching the
  existing "Xipher Labs" trade name). If the registry rejects, fall back to
  `Xipher Labs Argentina S.A.S.` and document the divergence here.
- [ ] Choose registered address. Operator's residential address is sufficient
  for SAS; reserve a P.O. Box / virtual address if privacy is a concern.
- [ ] Engage a lawyer for the CLA review (ADR-0019 migration §1). This can
  happen in parallel with entity formation.

### Phase 1 — Entity registration (operator action, ~2–6 weeks)

- [ ] Submit SAS registration via the AAIP portal:
  <https://www.argentina.gob.ar/aaip/sasorga>
- [ ] Pay filing fees (~USD 200–400 equivalent).
- [ ] Receive entity confirmation + CUIT (tax ID).
- [ ] Open the entity's bank account (Argentine banks typically require a
  proof-of-registration document).
- [ ] Record entity formation details (CUIT, registration date, registered
  address) in `~/.config/walter-os/overlay/personal.env` as
  `WALTER_LEGAL_ENTITY_CUIT` etc. — never commit these to the public repo.

### Phase 2 — Repo updates (PR, post-entity-formation)

These updates land in a follow-up PR once Phase 1 is complete. They are
intentionally one-line-style edits to keep the diff reviewable:

- [ ] `NOTICE`: change the "Xipher Labs is the trade name. ... entity is being
  constituted" paragraph to reflect the constituted entity name + CUIT.
- [ ] `COMMERCIAL.md`: change the operator-side caveat to reflect the
  constituted entity name.
- [ ] `CLA.md`: replace the "STATUS NOTE" block with the entity-formed
  attribution; update the governing-law clause to name the registered
  jurisdiction.
- [ ] `LICENSE`'s adjacent NOTICE paragraph (in `NOTICE`, not `LICENSE`
  itself which is canonical AGPL) names the entity.
- [ ] README's License section names the entity.

A PR template for this work is at the bottom of this runbook.

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

```
Title: [CHORE] -COMPLIANCE- update repo attribution post entity formation (ADR-0022)

Body:
Closes the post-formation half of #156. The Xipher Labs S.A.S. legal
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
| Phase 0 — prerequisites | pending |
| Phase 1 — registration | pending |
| Phase 2 — repo updates | pending (blocked by Phase 1) |
| Phase 3 — CLA activation | pending (blocked by Phase 1 + lawyer review) |
| Phase 4 — external PRs unlocked | pending (blocked by Phase 3) |

The operator updates this table as phases complete. CI does NOT enforce
phase completion — the gate is operator-policy.
