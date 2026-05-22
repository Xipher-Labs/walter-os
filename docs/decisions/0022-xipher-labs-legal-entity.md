# 0022. Xipher Labs Legal Entity — required before accepting external PRs

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/walter-os-oss-readiness-roadmap.md`

## Context

Walter-OS's LICENSE file already attributes copyright to "Xipher Labs" and the
README names "Xipher Labs" as the publisher. However, it is unclear at the time
of this ADR whether Xipher Labs is constituted as a legal entity (corporation,
LLC, SAS, or equivalent) with registered copyright holding capacity, or whether
"Xipher Labs" is currently a trade name used by the operator as a natural person.

This distinction matters for three reasons:

1. **CLA enforcement (ADR-0019):** The CLA's relicensing grant is made to
   "Xipher Labs." If Xipher Labs is not a legal entity, the grant is effectively
   made to the operator as a natural person. This creates risk if the operator
   ever leaves the project or if there is a dispute about who holds the grant.

2. **Commercial licensing (ADR-0018):** The dual-license strategy and the
   IdeaOS commercial license depend on Xipher Labs having the legal standing
   to issue commercial licenses as an entity.

3. **Contributor trust:** Contributors to an OSS project prefer to grant rights
   to a legal entity rather than to an anonymous individual. The entity provides
   continuity and accountability.

## Decision

**The operator must constitute Xipher Labs as a legal entity before the first
external PR is merged into the repository.**

"External PR" means a PR from any GitHub account that is not the operator's
primary account. PRs from the operator's own accounts, the CLA Assistant bot,
and CI bots are not external.

### What constituting the entity entails (operator's responsibility)

This ADR does not specify the jurisdiction or entity type — those are the
operator's decisions based on their personal situation. Common options for
a solo operator in Argentina include:

- **SAS (Sociedad por Acciones Simplificada):** Simplified LLC, fastest to
  register, online process via the Argentine national registry. Recommended
  for a solo founder.
- **SA (Sociedad Anónima):** Traditional corporation. More overhead; appropriate
  if the operator intends to raise VC capital.
- **Personal trademark registration (not sufficient):** Registering "Xipher Labs"
  as a trademark is not the same as constituting a legal entity. The entity
  must be able to hold contracts, be a party to the CLA, and hold copyright.

Alternative if the operator is based in or plans to operate primarily in another
jurisdiction: Delaware C-Corp (common for US-facing SaaS), BVI/Cayman
(offshore, complex for banking), UK Ltd (simple, but requires UK presence).

**The operator's recommendation: Argentina SAS** for speed and simplicity while
the project is bootstrapped. The entity can be redomiciled or a holding
structure added later if IdeaOS raises external capital.

### What changes after the entity is constituted

1. The `LICENSE` file's copyright notice is updated from `Copyright (C) 2026
   Xipher Labs` to `Copyright (C) 2026 Xipher Labs S.A.S.` (or equivalent with
   the registered entity type).
2. The `NOTICE` file is updated similarly.
3. The CLA text (ADR-0019) names the legal entity as the grant recipient.
4. The `COMMERCIAL.md` file is updated to identify the contracting entity.
5. All new repository files created after entity registration should use the
   registered entity name in any copyright notices.

### Interim state

Before the entity is registered, the operator MAY continue to develop the repo
and merge their own PRs. They MUST NOT merge external PRs until:
- The entity is registered.
- The CLA is drafted and reviewed by a lawyer.
- The CLA Assistant bot is configured.

This is a hard gate. Merging external PRs without it creates legal ambiguity
about who holds the contributor grants.

## Consequences

**Positive:**
- The contributor rights chain (contributor → entity → commercial license →
  IdeaOS) is legally sound.
- Adopters and contributors have a legal entity to contact, not an anonymous
  individual.
- The entity can enter into contracts (e.g., commercial license agreements
  with corporate adopters).

**Negative:**
- Entity registration takes time and money. In Argentina, SAS registration
  can take 2-6 weeks and costs approximately $200-400 USD in filing fees.
- The operator takes on compliance obligations (annual filings, accounting,
  etc.) for the entity.
- External PRs are blocked until the entity is constituted and the CLA is in
  place. This delays community contributions.

**Reversible:**
- Entity registration is not reversible in the sense that the entity, once
  constituted, exists independently. It can be dissolved, but that is not
  trivially reversible.
- The decision to use Xipher Labs as the entity name is already embedded in
  the repo; changing the entity name would require updating all copyright
  notices and the CLA.

## Migration

1. **Operator action (off-repo):** Register Xipher Labs as a legal entity.
2. **Operator action:** Engage a lawyer to review and finalize the CLA text
   (from the scaffold in ADR-0019).
3. **Repo PR:** Update `LICENSE`, `NOTICE`, `COMMERCIAL.md` with the
   registered entity name.
4. **Repo PR:** Commit `CLA.md` and the CLA Assistant workflow.
5. **Merge gate unlocked:** External PRs can now be accepted.

## References

- ADR-0018 — licensing strategy (entity as copyright holder enables commercial licensing)
- ADR-0019 — CLA (entity as grant recipient)
- `docs/specs/walter-os-oss-readiness-roadmap.md` — roadmap context
- Argentine SAS registration: https://www.argentina.gob.ar/aaip/sasorga
