# Implementation Plan: walter-oss-license-switch

**Spec**: `docs/specs/walter-oss-license-switch.md`
**Branch**: `v0.2.0-walter-oss`
**PR**: #48

TDD discipline applies: each task writes or updates the failing bats test FIRST
(RED), then makes it pass (GREEN). Tasks 1–3 each follow RED-GREEN. Task 4 is
the CI/verification gate.

---

## Task 1: Replace LICENSE + NOTICE [AC-1, AC-2, AC-3, AC-9 partial] (~10 min)

### RED — write the failing tests first

File: `tests/oss/license-files.bats` (modify)

Replace the existing test block:

```bats
@test "LICENSE contains Apache License Version 2.0" {
  grep -q "Apache License" "$REPO_ROOT/LICENSE"
  grep -q "Version 2.0" "$REPO_ROOT/LICENSE"
}
```

with:

```bats
@test "LICENSE contains GNU AGPL Version 3" {
  grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" "$REPO_ROOT/LICENSE"
  grep -q "Version 3" "$REPO_ROOT/LICENSE"
}

@test "LICENSE contains Xipher Labs copyright" {
  grep -q "Xipher Labs" "$REPO_ROOT/LICENSE"
}

@test "NOTICE contains Xipher Labs" {
  grep -q "Xipher Labs" "$REPO_ROOT/NOTICE"
}
```

Run `bats tests/oss/license-files.bats` — expect 2 failures (LICENSE assertions)
and 2 new failures (Xipher Labs assertions). NOTICE existence test still passes.
This is RED.

### GREEN — update LICENSE and NOTICE

**File: `LICENSE`** (full replacement)

Fetch the canonical AGPLv3 text from https://www.gnu.org/licenses/agpl-3.0.txt.
The implementer must download or paste the verbatim text. The file MUST open with
exactly:

```
                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007
```

Prepend the copyright notice as the very first lines of the file (before the
license body), matching GNU convention:

```
Walter-OS
Copyright (C) 2026 Xipher Labs

```

Then the full AGPLv3 canonical text follows without modification.

**File: `NOTICE`** (full replacement)

```
Walter-OS
Copyright (C) 2026 Xipher Labs

Walter-OS is licensed under the GNU Affero General Public License, Version 3
(AGPL-3.0-or-later). See the LICENSE file at the root of this repository or
<https://www.gnu.org/licenses/agpl-3.0.html> for the full license text.

Project URL: <https://github.com/xipher-labs/walter-os>
```

### Verify

```bash
bats tests/oss/license-files.bats
# Expect: all 6 tests pass (LICENSE exists, AGPL v3, Xipher in LICENSE, NOTICE exists, Xipher in NOTICE)
head -3 LICENSE
# Must output: "                    GNU AFFERO GENERAL PUBLIC LICENSE"
```

### Commit

```
test(oss): RED — update license-files.bats for AGPLv3 + Xipher Labs

Refs: docs/specs/walter-oss-license-switch.md
```

then after GREEN:

```
feat(license): replace Apache-2.0 with AGPLv3, copyright Xipher Labs

- LICENSE: full AGPLv3 canonical text with Xipher Labs copyright header
- NOTICE: AGPL-style attribution, Xipher Labs, project URL placeholder

Refs: docs/specs/walter-oss-license-switch.md
Closes #48 (partial)
```

---

## Task 2: Update ADR-0010 + create COMMERCIAL.md [AC-4, AC-5, AC-9 partial] (~8 min)

### RED — write the failing test first

File: `tests/oss/license-files.bats` (modify — add one test)

```bats
@test "COMMERCIAL.md exists at repo root" {
  [[ -f "$REPO_ROOT/COMMERCIAL.md" ]]
}
```

Run `bats tests/oss/license-files.bats` — expect 1 new failure (COMMERCIAL.md
not yet created). This is RED.

### GREEN — create COMMERCIAL.md and rewrite ADR-0010

**File: `COMMERCIAL.md`** (new, repo root)

```markdown
# Commercial Licensing

Walter-OS is free and open-source software licensed under the
**GNU Affero General Public License, Version 3 (AGPL-3.0-or-later)**.

Under the AGPL, you may use, modify, and distribute Walter-OS freely provided
that any modifications you deploy as a network service are also released under
the AGPL. See [LICENSE](LICENSE) for the full terms.

## Enterprise / Commercial License

If you need to use Walter-OS in a closed-source product, offer it as a managed
service without releasing your modifications, or require commercial support and
custom terms, a commercial license is available from Xipher Labs.

Contact: <licensing@xipherlabs.xyz>

_This file is the latent hook for dual-licensing. The commercial license is not
yet exercised — it will be negotiated case-by-case._
```

**File: `docs/decisions/0010-oss-license.md`** (full rewrite)

Rewrite the entire file. Keep the filename and ADR number (0010). The new content:

```markdown
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

**Internal use**: organisations that deploy modified Walter-OS *only internally*
(no network service offered to external users) are not required to release
modifications under AGPL's distribution clause. AGPLv3 §13 covers *remote
network interaction* — pure internal use does not trigger it.

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
```

### Verify

```bash
bats tests/oss/license-files.bats
# Expect: all 7 tests pass (including COMMERCIAL.md exists)
grep -q "Xipher Labs" docs/decisions/0010-oss-license.md && echo "ADR OK"
grep -q "AGPLv3" COMMERCIAL.md && echo "COMMERCIAL OK"
```

### Commit

```
test(oss): RED — add COMMERCIAL.md existence test to license-files.bats

Refs: docs/specs/walter-oss-license-switch.md
```

then after GREEN:

```
feat(license): create COMMERCIAL.md + rewrite ADR-0010 for AGPLv3

- COMMERCIAL.md: latent dual-licensing hook, Xipher Labs contact placeholder
- docs/decisions/0010-oss-license.md: full rewrite — Apache-2.0 proposal
  superseded by AGPLv3, Xipher Labs copyright, SaaS impact, dual-license
  consequences, alternatives comparison

Refs: docs/specs/walter-oss-license-switch.md
```

---

## Task 3: Sweep manifests + README + .env files [AC-6, AC-7, AC-8, AC-10] (~10 min)

### RED — write the failing test first

File: `tests/oss/license-files.bats` (modify — add one test)

```bats
@test "no Apache-2.0 string outside allowlisted files" {
  local matches
  matches="$(grep -rn "Apache-2\.0\|Apache License, Version 2\.0" "$REPO_ROOT" \
    --exclude-dir=external \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --exclude-dir=.claude \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/decisions/0010-oss-license.md" \
    | grep -v "$REPO_ROOT/docs/specs/walter-oss-license-switch.md" \
    | wc -l \
    | tr -d ' ')"
  [ "$matches" -eq 0 ]
}
```

Run `bats tests/oss/license-files.bats` — the new test fails because README.md
still declares `Apache-2.0`. This is RED.

### GREEN — targeted file edits

**File: `README.md`** (modify, line ~647)

Find:
```markdown
## License

Apache-2.0. See [LICENSE](LICENSE).
```

Replace with:
```markdown
## License

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

AGPLv3. See [LICENSE](LICENSE) and [COMMERCIAL.md](COMMERCIAL.md) for commercial licensing.
```

**File: `apps/control-tower/package.json`** (modify)

Add `"license"` and `"author"` fields (the file currently has neither at the
package level — it is `"private": true`):

```json
{
  "name": "control-tower",
  "version": "0.1.0",
  "private": true,
  "license": "AGPL-3.0-or-later",
  "author": "Xipher Labs",
  "type": "module",
  ...
}
```

Note: `apps/control-tower/package.json` has no root-level `package.json` sibling
in the repo (the root has no manifest). The `external/` submodule's
`packages/react-best-practices-build/package.json` declares MIT — that is
out of scope (third-party, different license is correct and expected).

**File: `contexts/_examples/personal.env.example`** (modify)

Find:
```
WALTER_COPYRIGHT_HOLDER="Your Name"
```

Replace with:
```
WALTER_COPYRIGHT_HOLDER="Xipher Labs"
```

Note: `WALTER_COPYRIGHT_HOLDER` in `.env.example` (the root-level template) does
NOT contain this variable — the root `.env.example` is an operator-facing deployment
template, not a branding template. Only `contexts/_examples/personal.env.example`
has this variable. Confirm with `grep -r WALTER_COPYRIGHT_HOLDER .` before
editing (should return exactly one hit).

### Verify

```bash
bats tests/oss/license-files.bats
# Expect: all 8 tests pass

# Confirm no stray Apache strings (outside allowlist):
grep -rn "Apache-2\.0\|Apache License, Version 2\.0" . \
  --exclude-dir=external \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.claude \
| grep -v "docs/decisions/0010-oss-license.md" \
| grep -v "docs/specs/walter-oss-license-switch.md"
# Must return empty

# Confirm AGPL in NOTICE and LICENSE:
grep -n "AGPL\|GNU Affero" LICENSE NOTICE
# Must return hits in both files
```

### Commit

```
test(oss): RED — add Apache-2.0 stray-string sweep test

Refs: docs/specs/walter-oss-license-switch.md
```

then after GREEN:

```
chore(license): sweep Apache-2.0 refs — README, package.json, env example

- README.md: AGPLv3 badge + updated license section
- apps/control-tower/package.json: license=AGPL-3.0-or-later, author=Xipher Labs
- contexts/_examples/personal.env.example: WALTER_COPYRIGHT_HOLDER default
  changed from "Your Name" to "Xipher Labs"

Refs: docs/specs/walter-oss-license-switch.md
```

---

## Task 4: CI green + push [AC-1 through AC-11 final gate] (~5 min)

No new test writes in this task. This is the verification gate before push.

### Run the full test suite

```bash
# OSS test suite
bats tests/oss/license-files.bats
bats tests/oss/depersonalization.bats

# Shellcheck on any shell files touched (none in this PR, but verify)
shellcheck hooks/*.sh 2>/dev/null || true

# Manual spot checks
head -3 LICENSE
# Output must be: "                    GNU AFFERO GENERAL PUBLIC LICENSE"

grep -c "Xipher Labs" LICENSE NOTICE
# LICENSE: 1, NOTICE: 1

grep -c "AGPL-3.0-or-later" apps/control-tower/package.json
# 1

grep -c "AGPL" README.md
# >= 1

[[ -f COMMERCIAL.md ]] && echo "COMMERCIAL.md OK"

# Final Apache stray-string check (the canonical AC-10 command):
grep -rn "Apache-2\.0\|Apache License, Version 2\.0" . \
  --exclude-dir=external \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.claude
# Must return ONLY lines in:
#   docs/decisions/0010-oss-license.md
#   docs/specs/walter-oss-license-switch.md
```

### Depersonalization regression check

`tests/oss/depersonalization.bats` must still pass in full. Note: "Xipher Labs"
as copyright holder is intentional branding and is NOT guarded by the
depersonalization suite (which guards against private operator identifiers and
non-contact domain leaks). These are different patterns and must not be
confused. Confirm `bats tests/oss/depersonalization.bats` has 0 failures.

### Push

```bash
git push origin v0.2.0-walter-oss
```

### Commit (none needed — task 4 is verification only, no code changes)

If any spot check in Task 4 reveals a missed file, fix it inline and commit:

```
fix(license): <specific file> missed in Apache-2.0 sweep

Refs: docs/specs/walter-oss-license-switch.md
```

---

## File touch matrix

| File | Task | Change type |
|---|---|---|
| `tests/oss/license-files.bats` | 1, 2, 3 | modify (RED tests, then grow with each GREEN) |
| `LICENSE` | 1 | full replacement (AGPLv3 text) |
| `NOTICE` | 1 | full replacement (AGPL attribution) |
| `COMMERCIAL.md` | 2 | new |
| `docs/decisions/0010-oss-license.md` | 2 | full rewrite |
| `README.md` | 3 | modify (license section ~line 645–648) |
| `apps/control-tower/package.json` | 3 | modify (add license + author fields) |
| `contexts/_examples/personal.env.example` | 3 | modify (one line: WALTER_COPYRIGHT_HOLDER) |

**Files explicitly NOT touched:**
- `tests/oss/depersonalization.bats` — copyright holder is intentional, not a leak
- `external/` — third-party submodules, own licenses
- `node_modules/` — out of scope
- `.env.example` (root) — deployment template, no WALTER_COPYRIGHT_HOLDER var
- `setup/vm/services/**/.env.example` — service configs, no license declarations
