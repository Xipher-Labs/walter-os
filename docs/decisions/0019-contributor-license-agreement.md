# 0019. Contributor License Agreement — CLA via CLA Assistant

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/walter-os-oss-readiness-roadmap.md`

## Context

Walter-OS is now accepting external PRs. Currently there is no mechanism to
ensure that contributors grant Xipher Labs the right to relicense their
contributions. This matters for two reasons:

1. ADR-0018 introduces a dual-license structure (Apache-2.0 contract layer +
   AGPL-3.0 host stack). Xipher Labs's ability to issue commercial licenses
   and to build IdeaOS depends on holding copyright or having a clear license
   grant from all contributors. Without a CLA, contributors implicitly grant
   the license specified by the file's SPDX header — but they do NOT grant
   Xipher Labs the right to issue commercial licenses for their contribution.

2. ADR-0022 records that Xipher Labs needs to be constituted as a legal entity.
   Once constituted, the entity should hold the CLA grants (not the individual
   operator's personal identity).

Two standard mechanisms exist: CLA (Contributor License Agreement) and DCO
(Developer Certificate of Origin). They have different legal and process
trade-offs.

## Decision

**Use a CLA enforced via CLA Assistant on GitHub.**

The specific mechanism:
- CLA Assistant bot is configured in the repository.
- Every PR from an external contributor triggers a CLA check.
- Contributors sign the CLA once by commenting `I have read the CLA Document
  and I hereby sign the CLA` on the PR. CLA Assistant records the signature
  and their GitHub identity.
- The bot adds a required status check to the PR that blocks merge until the
  CLA is signed.
- The CLA text is committed to the repo at `CLA.md`.

### CLA text scaffold

The CLA text should be derived from the Apache Individual CLA (ICLA):
https://www.apache.org/licenses/icla.pdf

Key grants required:
- Copyright license: contributor grants Xipher Labs the right to reproduce,
  prepare derivative works, distribute, publicly display, and publicly perform
  the contribution.
- Patent license: contributor grants Xipher Labs a patent license for any
  patents the contribution covers.
- Relicensing grant: contributor grants Xipher Labs the right to sublicense
  and relicense the contribution, including to commercial licensees. This is
  the critical clause that enables IdeaOS without violating the contributor's
  rights.

The CLA must explicitly state that the community's use of the contribution
under the SPDX-indicated license (Apache-2.0 or AGPL-3.0) is not affected
by the grant to Xipher Labs — the grant is additive.

### Bot configuration

CLA Assistant is configured via a `.github/PULL_REQUEST_TEMPLATE.md` note and
a GitHub Actions workflow at `.github/workflows/cla.yml` using the
`contributor-assistant/github-action` action. Signatures are stored in a
dedicated branch (`cla-signatures`) or in a GitHub Gist linked from the
workflow file.

## Consequences

**Positive:**
- Xipher Labs has clear legal standing to issue commercial licenses (for the
  host stack) and to build proprietary products (IdeaOS) using all contributions.
- The CLA is a well-understood mechanism. Large OSS projects (Apache, Google,
  JetBrains) use it. Contributors recognize it.
- CLA Assistant automates enforcement — no manual tracking.
- Signing is frictionless for contributors: one comment on the first PR they
  open, then never again.

**Negative:**
- Some contributors are philosophically opposed to CLAs. A DCO requires no
  such grant (contributors just certify they have the right to contribute).
  The CLA requirement will deter some potential contributors.
- The CLA must be reviewed by a lawyer before the repo accepts external PRs.
  This is an operator action (part of ADR-0022 legal entity setup).
- CLA signatures are stored in a GitHub Gist or branch; if the repo moves
  to a different Git host, signatures need to be migrated.

## Alternatives considered

**A — DCO (Developer Certificate of Origin)**
- Contributors add `Signed-off-by: Name <email>` to every commit via
  `git commit -s`.
- The DCO certifies that the contributor has the right to contribute under the
  file's license — it does NOT grant Xipher Labs the right to relicense or
  issue commercial licenses.
- For a project where the copyright holder wants to issue commercial licenses
  and build a proprietary product, DCO is insufficient.
- Rejected: DCO does not cover the relicensing and commercial license grant
  that Xipher Labs needs for IdeaOS.

**B — No CLA, rely on SPDX license grants alone**
- Contributors' contributions are governed by the file's SPDX license.
  Apache-2.0 contributions are Apache-2.0; AGPL-3.0 contributions are AGPL-3.0.
- No additional grant is collected.
- Xipher Labs cannot issue commercial licenses for AGPL contributions, and
  cannot build a fully proprietary IdeaOS using contributors' AGPL code without
  violating the license.
- Rejected: this path makes IdeaOS legally impossible once external contributions
  land in the AGPL host stack.

**C — Corporate CLA instead of ICLA**
- Require a separate Corporate CLA (CCLA) for contributors acting on behalf of
  an employer.
- Added complexity at this stage; the project's contributor base is
  individuals, not corporate engineering teams, at v0.4.5-alpha.
- RECOMMENDED: add the CCLA as a follow-up once the project grows to have
  corporate contributors. Out of scope for this ADR.

## Migration

1. Lawyer reviews and approves the CLA text before any external PR is merged.
2. `CLA.md` is committed to the repo.
3. `.github/workflows/cla.yml` is committed and the CLA Assistant GitHub App
   is installed on the repository.
4. `.github/PULL_REQUEST_TEMPLATE.md` is updated with a note:
   "By opening this PR you agree to sign the CLA at `CLA.md` if you haven't
   already. The CLA Assistant bot will guide you."
5. All maintainers (currently: the operator) sign the CLA retroactively
   to establish parity.

## References

- ADR-0018 — licensing strategy (why the CLA is needed)
- ADR-0022 — Xipher Labs legal entity (CLA is assigned to the entity)
- Apache ICLA — https://www.apache.org/licenses/icla.pdf (CLA text scaffold)
- CLA Assistant — https://github.com/contributor-assistant/github-action
- `docs/specs/walter-os-oss-readiness-roadmap.md` — roadmap context
