# 0018. Licensing strategy — dual-license with AGPL-3.0 core + commercial reserve

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/walter-os-oss-readiness-roadmap.md`

## Context

Walter-OS is currently licensed under AGPL-3.0 across the entire repository,
as decided in ADR-0010. Copyright is held by the operator personally as of this
writing. Per ADR-0022, Xipher Labs is being constituted as a legal entity;
copyright is being transferred to the entity. The "commercial license to self"
mechanism described in the Decision section is only fully sound once that
transfer is complete — both the license assignment + the commercial grant rest
on the copyright holder having unambiguous standing to grant both. **ADR-0022 is
a prerequisite for the COMMERCIAL.md text + NOTICE attribution this ADR
generates.** The LICENSE files + SPDX headers can land beforehand with operator-
name attribution as an interim state; the NOTICE attribution updates in a one-
line follow-up once the entity transfer completes.

The operator is planning to build IdeaOS: a commercial SaaS product derived
from Walter-OS. This requires re-examining the licensing strategy to ensure:

1. The open-source core remains genuinely open (not a bait-and-switch).
2. The hosting stack can carry a different license that discourages direct
   competing SaaS offers.
3. IdeaOS can be built as a proprietary product without the operator violating
   their own AGPL license (possible only because the operator is the sole
   copyright holder).
4. Corporate adopters of the agent contract layer (who have strong legal review
   processes) are not blocked by AGPL's copyleft obligations.

The operator's strategic plan proposes: Apache-2.0 for the contract layer +
AGPL-3.0 for the host stack + commercial license for IdeaOS. This ADR
evaluates that proposal against alternatives.

## Decision

**Revise the licensing strategy as follows:**

- **`AGENTS.md` cascade + skills + hooks + agents/ + commands/ (the "contract
  layer")**: License under **Apache-2.0**. This is the layer most likely to be
  adopted by corporate engineering teams for its process discipline, and AGPL's
  network-service copyleft would create legal friction that makes corporate
  adoption unlikely. Apache-2.0 removes that friction while still being OSI-
  approved and patent-granted.

- **`setup/walter-host/` (the "host stack")**: License under **AGPL-3.0**.
  This is the layer that hyperscalers could white-label as a competing hosted
  product. AGPL's §13 requires network-service operators to publish their
  modifications, closing the SaaS loophole for the heavy infrastructure work.

- **IdeaOS**: Licensed under a **commercial proprietary license** that Xipher
  Labs grants to itself (as sole copyright holder, the operator can grant a
  commercial license to a product they build without re-licensing the OSS tiers).
  IdeaOS is a separate product and is not defined in this repository.

- **`COMMERCIAL.md`**: Updated to reflect the dual-license structure and to
  serve as the entry point for organizations that want a commercial license for
  the host stack or for embedding parts of Walter-OS in proprietary products.

### Implementation

1. Add a `LICENSE-APACHE` file at the repo root (Apache-2.0 full text).
2. The existing `LICENSE` file (AGPL-3.0) remains for the host stack.
3. Add a `LICENSE` file inside `setup/walter-host/` that is unambiguously
   AGPL-3.0 for that subtree.
4. Update `NOTICE` to reflect dual-license structure.
5. Update `COMMERCIAL.md` with the licensing map.
6. Add a prominent licensing table to the README.
7. All new skills, agents, commands, and hooks files MUST include a
   SPDX identifier comment header:
   `# SPDX-License-Identifier: Apache-2.0`
   All new files in `setup/walter-host/` MUST include:
   `# SPDX-License-Identifier: AGPL-3.0-or-later`

## Consequences

**Positive:**
- Corporate engineering teams can adopt the agent contract (AGENTS.md cascade,
  skills, hooks) without triggering AGPL's copyleft — Apache-2.0 has no
  copyleft requirement.
- The host stack retains AGPL protection against competing hosted services.
- Xipher Labs retains the ability to issue commercial licenses (both for the
  AGPL host stack and for proprietary products) because copyright is held by
  the entity.
- IdeaOS can be built as a proprietary product without violating the operator's
  own license because the operator is the sole copyright holder.

**Negative:**
- Dual-license repos are more complex to communicate. The licensing table in
  the README must be very clear.
- Any contributor who adds code must understand which license applies to which
  directory. The CLA (ADR-0019) handles the legal side; documentation and
  SPDX headers handle the practical side.
- The Apache-2.0 contract layer can be forked and used in proprietary products
  without obligation. This is an intentional trade-off (lowering adoption
  friction) accepted by the operator.

**Reversible:**
- Changing from Apache-2.0 to AGPL on the contract layer for future releases
  is possible (not retroactive). The opposite (AGPL → Apache-2.0) is also
  possible. Copyright held by Xipher Labs means neither direction requires
  contributor consent.

## Alternatives considered

**A — Keep pure AGPL-3.0 across the entire repo (status quo)**
- The contract layer's copyleft discourages corporate adoption.
- The IdeaOS path still works (operator as sole copyright holder), but
  friction from corporate legal review teams limits the audience.
- Rejected: the operator explicitly wants to enable corporate contract-layer
  adoption.

**B — Apache-2.0 across the entire repo**
- Maximally permissive; minimal friction.
- Removes AGPL protection from the host stack, allowing competing hosted
  services to fork and close the source.
- The operator's original OSS goals (ADR-0010, goal 2: "modifications deployed
  as network services must be publicly released") are violated for the host stack.
- Rejected.

**C — SSPL (Server Side Public License) for the host stack**
- Stricter than AGPL — requires release of the entire stack used to run the
  service, not just modifications.
- Not OSI-approved. Enterprise legal teams treat SSPL as proprietary-equivalent.
  Same ecosystem compatibility problem that ADR-0010 identified.
- Rejected.

**D — BSL (Business Source License) for the host stack**
- Time-delayed OSS: converts to Apache-2.0 after N years.
- Not OSI-approved. Deferred-open-source optics are problematic.
- Rejected.

**E — MIT across the entire repo**
- Even more permissive than Apache-2.0; no patent grant language.
- All the Apache-2.0 cons plus no patent protection.
- Rejected.

## Migration

1. PR adds `LICENSE-APACHE`, updates `LICENSE` (existing AGPL stays), adds
   `setup/walter-host/LICENSE`, updates `NOTICE`, updates `COMMERCIAL.md`,
   updates README with licensing table.
2. All subsequent PRs adding files to the contract layer include SPDX headers.
3. All subsequent PRs adding files to `setup/walter-host/` include SPDX headers.
4. No retroactive header additions to existing files are required in the
   initial PR (too much churn); headers are required on new files from
   the merge date forward.

## References

- ADR-0010 — original AGPL-3.0 decision (now partially superseded)
- ADR-0019 — CLA/DCO decision (prerequisite for accepting external PRs)
- ADR-0022 — Xipher Labs legal entity (prerequisite for sound copyright basis)
- `docs/specs/walter-os-oss-readiness-roadmap.md` — roadmap context
