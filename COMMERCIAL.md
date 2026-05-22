# Commercial Licensing

Walter-OS is dual-licensed by directory tree. See [NOTICE](NOTICE) for the
canonical map and [docs/decisions/0018-licensing-strategy.md](docs/decisions/0018-licensing-strategy.md)
for the decision record.

## License map at a glance

| Tree | License | SPDX identifier | Why |
|---|---|---|---|
| Default (repo root + all subdirectories not listed below) | Apache License 2.0 | `Apache-2.0` | Lowers friction for corporate adoption of the agent contract layer. No copyleft. |
| `setup/walter-host/` | GNU AGPL v3 (or later) | `AGPL-3.0-or-later` | Network-service copyleft (§13) closes the SaaS-loophole for hyperscalers white-labeling the host stack. |

Files in `setup/walter-host/` carry SPDX header `# SPDX-License-Identifier: AGPL-3.0-or-later`.
Files outside that subtree carry `# SPDX-License-Identifier: Apache-2.0`.
Headers are required on new files going forward; the existing tree is not
back-filled in the same change to keep the diff reviewable.

## When you do NOT need a commercial license

- You build a product on top of the contract layer (skills, agents, hooks,
  `AGENTS.md` cascade) and ship it as proprietary software. Apache-2.0 has no
  copyleft. Just preserve the NOTICE and license attribution.
- You self-host `setup/walter-host/` for your own use without exposing it as a
  public service. AGPL §13 only kicks in when you offer modified versions of
  the host stack over a network.
- You contribute back to the project via PR. Your contribution is licensed
  under the matching tree's license per the CLA (ADR-0019).

## When you DO need a commercial license

A commercial license is required if you want:

1. **Closed-source modifications of `setup/walter-host/` deployed as a
   network service.** AGPL-3.0 §13 requires you to publish your modifications
   under the AGPL. A commercial license lifts that obligation.
2. **A managed-hosting product based on `setup/walter-host/`** that competes
   with future Xipher Labs hosted offerings. Independent of the AGPL terms,
   we want to be in the loop on those conversations.
3. **OEM / embedding rights** that need legal certainty beyond what
   Apache-2.0 or AGPL provide (warranty disclaimer carve-outs, indemnity, SLAs).
4. **Trademark usage rights** for the "Walter-OS" or "Xipher Labs" names beyond
   what fair use covers in your own promotional materials.

## How to request

Contact: <licensing@xipherlabs.xyz>

Include:
- Your organization, country, and intended use case.
- Which subtree triggers the request (`setup/walter-host/`, the contract
  layer for OEM purposes, or trademark scope).
- Expected scale (single-tenant vs. multi-tenant, internal vs. external
  service, approximate user count).

## Contracting entity

Xipher Labs S.R.L. (Sociedad de Responsabilidad Limitada, Argentina) is
the constituted legal entity issuing commercial licenses for Walter-OS,
per ADR-0022. The entity holds the Walter-OS copyright.

## Related ADRs

- [docs/decisions/0010-oss-license.md](docs/decisions/0010-oss-license.md) — original AGPL decision (partially superseded by 0018)
- [docs/decisions/0018-licensing-strategy.md](docs/decisions/0018-licensing-strategy.md) — dual-license decision
- [docs/decisions/0019-contributor-license-agreement.md](docs/decisions/0019-contributor-license-agreement.md) — CLA decision
- [docs/decisions/0022-xipher-labs-legal-entity.md](docs/decisions/0022-xipher-labs-legal-entity.md) — entity constitution
