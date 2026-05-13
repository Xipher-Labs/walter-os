# 0010. OSS License — AGPLv3 (Xipher Labs)

**Date**: 2026-05-11 (revised 2026-05-11)
**Status**: Accepted (supersedes the Apache-2.0 proposal recorded in the
initial draft of this file)

## Context

Walter-OS v0.2.0 is the first release intended for third-party adoption. Before
publishing, the operator (Xipher Labs) finalized three explicit OSS goals:

1. No one should be able to resell Walter-OS as a closed product — any
   distribution must remain open.
2. Modifications deployed as network services must be publicly released under
   the same terms (the "SaaS loophole" must be closed).
3. The copyleft must propagate to derivative works, so the community benefits
   from ecosystem improvements.

Apache-2.0 (the initial proposal) satisfies none of these three goals: it is
permissive, it does not close the SaaS loophole, and copyleft does not propagate.

The copyright holder is Xipher Labs (the operating entity), not the operator as
a natural person. Holding copyright in an entity is cleaner for future
co-authorship, business licensing conversations, and organizational continuity.

## Decision

License Walter-OS under **AGPLv3 (AGPL-3.0-or-later)**, with copyright attributed
to **Xipher Labs**.

- `LICENSE`: full canonical AGPLv3 text, `Copyright (C) 2026 Xipher Labs`
- `NOTICE`: AGPL-style attribution, Xipher Labs, project URL
- `COMMERCIAL.md`: latent dual-licensing hook — Xipher Labs may issue commercial
  licenses to specific downstream users without re-licensing the OSS tier, because
  the copyright is held by the entity

Implemented in PR #48 (v0.2.0 OSS launch chain).

## Consequences

**Source-release obligation**: anyone who modifies Walter-OS and offers it as a
network service (SaaS, hosted tool, API) must release their modifications under
AGPLv3. This is the primary enforcement mechanism against closed SaaS forks.

**Internal use nuance**: AGPLv3 §13 triggers whenever users interact with modified
Walter-OS over a network — including internal employees of the deploying organisation.
The §13 obligation is to make the source code AVAILABLE to those interacting users
(corresponding source on request), not necessarily to publish it publicly. So an
org that deploys a modified Walter-OS for only its own staff must still be prepared
to provide source to those staff (which is trivial inside the org), but is not
forced into public source release. Public release becomes required only when the
service is offered to users outside the org. Operators considering internal-only
deployments should consult counsel for their specific situation.

**Dual-license potential**: because Xipher Labs holds copyright, it can grant
commercial licenses to specific users who need closed-source rights. `COMMERCIAL.md`
is the entry point. This does not affect the AGPLv3 rights of the community.

**Ecosystem compatibility**: AGPLv3 is OSI-approved and widely understood. Libraries
licensed under MIT, Apache-2.0, or LGPLv2.1 can be used within Walter-OS without
license conflict (they are permissive upstream). Walter-OS's AGPL copyleft propagates
downstream (to derivatives), not upstream (to dependencies).

**Plugin dependency (obra/superpowers)**: Walter-OS references superpowers as a
required install-time plugin but does not distribute it. This is not a license
compatibility issue — AGPL's distribution clause is not triggered by referencing
a separately-installed proprietary tool. If superpowers files are ever vendored into
this repo, legal review is required before that commit lands.

## Alternatives Considered

**Apache-2.0** (initial proposal):
- Pro: maximally permissive, zero friction, patent grant.
- Con: fails all three operator OSS goals. A cloud provider could fork Walter-OS,
  make proprietary modifications, and offer "HostedWalterOS.com" with no obligation
  to release source.
- Rejected.

**SSPL (Server Side Public License)**:
- Pro: stricter than AGPL — requires release of the entire stack used to run the
  service, not just modifications to the software itself.
- Con: not OSI-approved. Loses ecosystem compatibility (package registries, enterprise
  legal teams treat SSPL as proprietary-equivalent).
- Rejected.

**BUSL (Business Source License)**:
- Pro: time-delayed OSS (converts to a permissive license after N years).
- Con: operator wants OSS day 0, not deferred OSS. BUSL is not OSI-approved.
- Rejected.

**Elastic License v2 / Commons Clause on Apache-2.0**:
- Not OSI-approved. Avoided for the same ecosystem-compatibility reason as SSPL.
- Rejected.

**GPL-2.0 or GPL-3.0** (without the Affero addition):
- The classic GPL distribution clause is not triggered by running the software as a
  network service (the "ASP loophole"). A SaaS operator could serve modified GPL
  software without releasing changes.
- AGPLv3 closes this loophole via §13.
- Rejected in favour of AGPL.
