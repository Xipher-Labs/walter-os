# Walter-OS OSS License Switch — Apache-2.0 to AGPLv3

**Status**: Approved
**Owner**: Xipher Labs
**Created**: 2026-05-11
**PR**: #48 (v0.2.0 OSS launch chain)

---

## Problem

Walter-OS was initially released under Apache-2.0 with copyright attributed to
an individual operator (ADR-0010, 2026-05-11). That decision was made before the operator's three
explicit commercialization guardrails were fully articulated. Apache-2.0 is a permissive
license: it allows anyone to take Walter-OS, modify it, ship it as a closed-source SaaS
product, and never release their changes. That is directly contrary to what Xipher Labs
needs from the OSS release.

The second problem is attribution. Walter-OS is now operated under the Xipher Labs
entity. Copyright under an individual operator creates ambiguity about assignments,
future co-authors, and business licensing conversations. The copyright holder
should be the legal entity: Xipher Labs.

Both problems must be fixed before v0.2.0 is tagged. The fix touches `LICENSE`,
`NOTICE`, the ADR, one new file (`COMMERCIAL.md`), the README, manifest files, and
the `.env.example` defaults. The test suite in `tests/oss/license-files.bats` must
be updated in lockstep so CI continues to enforce the correct state going forward.

## Proposed Solution

Replace the Apache-2.0 `LICENSE` file with the canonical AGPLv3 text from the GNU
project, updated with the "Copyright (C) 2026 Xipher Labs" header. Update `NOTICE`
to reflect AGPL-style attribution. Rewrite `docs/decisions/0010-oss-license.md` to
document the switch and its reasoning so future contributors understand the intent.
Add a `COMMERCIAL.md` file at the repo root that is the latent hook for future
dual-licensing: it tells anyone who reads it that a commercial license is available
from Xipher Labs, without exercising that commercial license now.

Do a targeted sweep of every manifest (`apps/control-tower/package.json`), the
`README.md` license section, and the `contexts/_examples/personal.env.example`
default value for `WALTER_COPYRIGHT_HOLDER`. Update `tests/oss/license-files.bats`
to assert the new state. Verify with `grep` that no file outside the two allowlisted
paths still declares "Apache-2.0" or "Apache License, Version 2.0".

## Acceptance Criteria

- [AC-1] `LICENSE` contains AGPLv3 canonical text verbatim (from
  https://www.gnu.org/licenses/agpl-3.0.txt). `head -3 LICENSE` outputs:
  ```
                      GNU AFFERO GENERAL PUBLIC LICENSE
                         Version 3, 19 November 2007
  ```

- [AC-2] **LICENSE is canonical AGPLv3 with NO project-specific copyright injected.**
  Per AGPL §0, the license document "may be copied verbatim, but changing it is
  not allowed." Adding a project copyright line inside LICENSE corrupts the
  canonical text. The project's copyright belongs in `NOTICE` (see AC-3).
  Verify: `! grep -q "Xipher Labs" LICENSE` exits 0.
  (Revised after Codex round-1 review on PR #48 flagged the original AC-2
  as conflicting with canonical AGPL distribution requirements.)

- [AC-3] `NOTICE` reads "Walter-OS by Xipher Labs" and includes:
  - The AGPLv3 license declaration (not Apache attribution boilerplate)
  - A project URL placeholder in the form `<https://github.com/xipher-labs/walter-os>`

- [AC-4] `docs/decisions/0010-oss-license.md` is rewritten:
  - Status field: `Accepted (supersedes the Apache-2.0 proposal in this same file)`
  - Decision section: "License Walter-OS under AGPLv3 attributed to Xipher Labs"
  - Consequences section covering: source-release obligation under AGPLv3 §13, SaaS
    impact (operators who serve modified Walter-OS as a network service must release
    modifications), dual-license potential (COMMERCIAL.md enables future commercial
    license without re-licensing the OSS tier)
  - References PR #48

- [AC-5] New file `COMMERCIAL.md` exists at repo root containing:
  - A statement that Walter-OS is AGPLv3-licensed
  - An invitation to contact Xipher Labs for commercial licensing
  - A contact placeholder: `<licensing@xipherlabs.xyz>` (placeholder email, not
    a real mailbox today — to be configured before the GitHub OSS launch)

- [AC-6] All manifests in the repo updated:
  - `apps/control-tower/package.json`: `"license"` field set to
    `"AGPL-3.0-or-later"` and `"author"` field added/updated to `"Xipher Labs"`
  - No `Cargo.toml` or `pyproject.toml` exist at the root level (confirmed: not
    in scope). If any are added in a future PR, they must default to AGPL-3.0-or-later.

- [AC-7] `README.md`:
  - License section (line ~647) changed from `Apache-2.0. See [LICENSE](LICENSE).`
    to include the AGPLv3 SPDX identifier and a shields.io badge:
    `[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)`
  - Body text updated: `AGPLv3. See [LICENSE](LICENSE).`

- [AC-8] `contexts/_examples/personal.env.example`:
  - `WALTER_COPYRIGHT_HOLDER` default value **stays as `"Your Name"`** —
    this is a FORKER-facing template where each operator fills in their
    own copyright holder. Xipher Labs uses its own overlay (`personal.env`
    out-of-repo) where the value is set to `"Xipher Labs"`. The template
    in this repo must remain generic.
  (Revised after Codex round-2 review on PR #48 — original AC-8 would have
  baked the Xipher Labs name into the public template, which is wrong for forkers.)

- [AC-9] `tests/oss/license-files.bats` updated:
  - Existing test `"LICENSE contains Apache License Version 2.0"` replaced by:
    `"LICENSE contains AGPL Version 3"` (asserts `grep -q "GNU AFFERO GENERAL PUBLIC LICENSE"` and `grep -q "Version 3"`)
  - New test: `"COMMERCIAL.md exists at repo root"` (asserts `[[ -f "$REPO_ROOT/COMMERCIAL.md" ]]`)
  - New test: `"LICENSE is canonical AGPL (no project copyright injected)"`
    (asserts `! grep -q "Xipher Labs" "$REPO_ROOT/LICENSE"`) — aligns with revised AC-2
  - New test: `"NOTICE contains Xipher Labs"` (asserts `grep -q "Xipher Labs" "$REPO_ROOT/NOTICE"`)

- [AC-10] The command:
  ```
  grep -rn "Apache-2.0\|Apache License, Version 2.0" . \
    --exclude-dir=external \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --exclude-dir=.claude
  ```
  returns matches ONLY in:
  - `docs/decisions/0010-oss-license.md` (references the previous decision)
  - `docs/specs/walter-oss-license-switch.md` (this spec — "switching from")
  No other file may contain these strings.

- [AC-11] This spec explicitly documents the dual-licensing-latent capability:
  `COMMERCIAL.md` is the hook that enables a future commercial license without
  re-licensing the AGPLv3 OSS tier. Xipher Labs retains the right to offer
  proprietary licenses to specific downstream users because Xipher Labs holds
  copyright. This is documented in ADR-0010 Consequences section and referenced
  in `COMMERCIAL.md`.

## Non-goals

- NOT setting up the GitHub mirror workflow (PR #50, post-OSS-launch).
- NOT building or scaffolding `walter-personal` (PR #49).
- NOT updating `tests/oss/depersonalization.bats` for "Xipher Labs" — copyright
  holder is intentional branding, not a depersonalization leak. The depersonalization
  suite guards against *personal* identifiers (xipherlabs.xyz domain, the operator's personal
  email), not entity names.
- NOT signing a CLA or building contributor agreements — separate v0.2.x decision.
- NOT setting up the `licensing@xipherlabs.xyz` mailbox — COMMERCIAL.md placeholder
  only; mailbox is an ops task outside this PR.
- NOT changing the Apache-2.0 license on `external/` submodules — those carry their
  own licenses and are out of scope.
- NOT adding SPDX headers to individual source files — repo-level LICENSE is
  sufficient for this release tier. Individual file headers are a v0.3.x concern.

## Open Questions

- The placeholder email in `COMMERCIAL.md` (`<licensing@xipherlabs.xyz>`) will
  appear in the public repo before the mailbox exists. Operator should either
  configure the mailbox before the OSS launch or use a generic contact form URL.
  Flag for pre-launch checklist.
- AGPLv3 compatibility with `obra/superpowers` (the required plugin): superpowers
  is proprietary (Jesse Vincent, Anthropic marketplace). Walter-OS does not
  distribute superpowers; it references it as an install-time plugin. This is
  analogous to a GPL-licensed OS referencing a proprietary driver — distribution
  of superpowers is not triggered. However, if Walter-OS ever bundles or vendors
  superpowers files, legal review is required.
- `apps/control-tower/package.json` has `"private": true` — the `"license"` field
  has no operational effect for private packages, but it is still the correct
  documentary signal. No open question, just a note.

## References

- `docs/decisions/0010-oss-license.md` — ADR being superseded/updated in this PR
- `tests/oss/license-files.bats` — test file being updated
- `tests/oss/depersonalization.bats` — NOT modified (see Non-goals)
- https://www.gnu.org/licenses/agpl-3.0.txt — canonical AGPLv3 text source
- https://spdx.org/licenses/AGPL-3.0-or-later.html — SPDX identifier
- PR #48 in v0.2.0 OSS launch chain
