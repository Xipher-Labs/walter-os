# Walter-OS Individual Contributor License Agreement ("CLA")

**Version**: 1.0 (DRAFT — pending lawyer review per ADR-0019 migration step 1)
**Date**: 2026-05-21
**Project**: Walter-OS (the "Project")
**Owner**: Xipher Labs (the "Project Owner")

> **STATUS NOTE — TO BE REMOVED ON ACTIVATION**
>
> This CLA scaffold has been committed to the repository per
> [ADR-0019](docs/decisions/0019-contributor-license-agreement.md). It is
> **NOT yet active**. Per the migration plan in ADR-0019, the text must
> be reviewed and approved by a lawyer before the CLA Assistant bot is
> enabled and external PRs are gated on it. Until activation, the
> `.github/workflows/cla.yml` workflow is gated by `if:
> ${{ vars.WALTER_CLA_ACTIVE == 'true' }}` — it will not block any PR.
>
> Activation steps once approved:
> 1. Remove this status note + the gating `if:` from the workflow.
> 2. Set the `WALTER_CLA_ACTIVE` repo variable to `true`.
> 3. The CLA Assistant bot starts enforcing the signature requirement
>    on every external PR from that point forward.
> 4. All existing maintainers sign retroactively (operator first).

---

Thank you for your interest in contributing to Walter-OS. To clarify the
intellectual property license granted with Contributions from any person or
entity, the Project Owner must have a Contributor License Agreement ("CLA")
on file that has been signed by each Contributor, indicating agreement to
the license terms below.

This CLA is derived from the **Apache Individual Contributor License
Agreement v2.0** (the "Apache ICLA"; see
<https://www.apache.org/licenses/icla.pdf>) with project-specific
adaptations. By signing this CLA you agree that the terms below apply to
your past, present, and future Contributions to the Project.

## 1. Definitions

"**You**" (or "**Your**") shall mean the individual identified by the GitHub
account that signs this CLA via the CLA Assistant bot.

"**Contribution**" shall mean any original work of authorship, including any
modifications or additions to an existing work, that is intentionally
submitted by You to the Project Owner for inclusion in, or documentation of,
the Project. "Submitted" means any form of electronic, verbal, or written
communication sent to the Project Owner or the Project's contributors,
including but not limited to communication on electronic mailing lists,
source code control systems, and issue tracking systems that are managed by,
or on behalf of, the Project Owner for the purpose of discussing and
improving the Project, but excluding communication that is conspicuously
marked or otherwise designated in writing by You as "Not a Contribution."

## 2. Grant of Copyright License

Subject to the terms and conditions of this Agreement, You hereby grant to
the Project Owner and to recipients of software distributed by the Project
Owner a perpetual, worldwide, non-exclusive, no-charge, royalty-free,
irrevocable copyright license to reproduce, prepare derivative works of,
publicly display, publicly perform, sublicense, and distribute Your
Contributions and such derivative works.

This grant includes the right for the Project Owner to:

a. Distribute Your Contribution under any OSI-approved open-source license
   that applies to the file You contributed (as indicated by the file's
   SPDX-License-Identifier or, if absent, the license that applies to the
   directory subtree per the Project's NOTICE file).

b. **Sublicense Your Contribution under a commercial license** to third
   parties on terms different from the OSI license, including but not
   limited to proprietary, closed-source, and managed-service licenses.
   This sublicensing right is the basis on which the Project Owner is able
   to offer the commercial-license path documented in `COMMERCIAL.md`.

c. **Relicense Your Contribution** under a different OSI-approved
   open-source license in the future, including to facilitate the
   evolution of the Project's licensing strategy as documented in
   `docs/decisions/` (the ADRs).

The community's right to use Your Contribution under the SPDX-indicated
license (or the directory-subtree license) is **not affected** by this
grant. This grant is **additive** — it gives the Project Owner additional
rights on top of the community's rights, not in place of them.

## 3. Grant of Patent License

Subject to the terms and conditions of this Agreement, You hereby grant to
the Project Owner and to recipients of software distributed by the Project
Owner a perpetual, worldwide, non-exclusive, no-charge, royalty-free,
irrevocable (except as stated in this section) patent license to make, have
made, use, offer to sell, sell, import, and otherwise transfer Your
Contribution, where such license applies only to those patent claims
licensable by You that are necessarily infringed by Your Contribution
alone or by combination of Your Contribution with the Project to which
such Contribution was submitted. If any entity institutes patent
litigation against You or any other entity (including a cross-claim or
counterclaim in a lawsuit) alleging that Your Contribution, or the Project
to which You have contributed, constitutes direct or contributory patent
infringement, then any patent licenses granted to that entity under this
Agreement for that Contribution or Project shall terminate as of the date
such litigation is filed.

## 4. Representations

You represent that:

a. You are legally entitled to grant the above license. If your employer(s)
   has rights to intellectual property that You create that includes Your
   Contributions, You represent that You have received permission to make
   Contributions on behalf of that employer, that your employer has waived
   such rights for Your Contributions to the Project Owner, or that your
   employer has executed a separate Corporate CLA with the Project Owner.

b. Each of Your Contributions is Your original creation (see Section 5 for
   submissions on behalf of others).

c. Your Contribution submissions include complete details of any third-party
   license or other restriction (including, but not limited to, related
   patents and trademarks) of which You are personally aware and which are
   associated with any part of Your Contributions.

## 5. Third-party works

Should You wish to submit work that is not Your original creation, You may
submit it to the Project Owner separately from any Contribution, identifying
the complete details of its source and of any license or other restriction
(including, but not limited to, related patents, trademarks, and license
agreements) of which You are personally aware, and conspicuously marking
the work as "Submitted on behalf of a third-party: [named here]".

## 6. Support

You are not expected to provide support for Your Contributions, except to
the extent You desire to provide support. You may provide support for free,
for a fee, or not at all. Unless required by applicable law or agreed to in
writing, You provide Your Contributions on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including,
without limitation, any warranties or conditions of TITLE,
NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE.

## 7. Notification

You agree to notify the Project Owner of any facts or circumstances of
which You become aware that would make these representations inaccurate in
any respect.

## 8. Governing Law

This Agreement is governed by the laws of the jurisdiction in which Xipher
Labs is constituted (per ADR-0022). Until the entity is constituted, this
Agreement is governed by the laws of Argentina (the operator's residence).
Once the entity is constituted, this Agreement transfers to the entity by
operation of the entity-formation documents; no re-signing is required.

---

## How to sign

When you open your first PR to Walter-OS, the **CLA Assistant** bot will
post a comment with a signing link. To sign:

1. Read this CLA in full.
2. Comment on the PR with: `I have read the CLA Document and I hereby sign the CLA`
3. CLA Assistant records your signature against your GitHub identity and
   the PR's CLA check goes green.

You only sign once. Subsequent PRs from the same GitHub account inherit the
signature.

## Questions

For questions about this CLA, contact `licensing@xipherlabs.xyz`.
