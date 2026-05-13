# W-5: Depersonalization — Personal Overlay Extraction

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

The Walter-OS repo is public but not forkable. The following personal references
are embedded directly in OSS-core files, making every adopter's first task a
search-and-replace across a dozen files they do not fully understand yet:

- `xipherlabs.xyz` domain appears in: 10+ compose files, `.env.example`,
  `README.md`, `setup/vm/services/homepage/services.yaml`, and multiple service
  configs.
- `contexts/work/AGENTS.md` describes example work org's specific stack (Yellowstone
  gRPC, Solana, baremetal Ansible, Linear org), custom Solana reasoning rules,
  and example work org-specific branch flow exceptions.
- `contexts/projects-personal/AGENTS.md` names example civic app and example medical app explicitly,
  includes Argentine legal framework references (Law 13.064, Decree 1023/2001,
  Law 26.529, Law 25.326, ANMAT).
- `contexts/personal/AGENTS.md` includes Argentina-specific tax/legal references
  (AFIP, ARCA, small-taxpayer regime, gross-receipts tax, MEP-CCL).
- `skills/regulatory-research-argentina/` is a skill scoped to a single country.
- Operator profile in `AGENTS.md` (root) names "the operator", "example work org",
  and a private operator location.

Anyone reading these files gets a rich view of one operator's setup. Anyone trying
to adopt the patterns has to surgically remove all of this before the repo is safe
to commit with their own credentials and configurations.

The fix is not to delete this content — it is useful as examples. The fix is to
move it to a personal overlay that lives outside the OSS repo, and provide:
(a) clean templates in the repo, and (b) a mechanism for operators to maintain
their personal overlay separately.

## Proposed solution

Two-layer model (see ADR 0011 for the full decision and alternatives):

**Layer 1 — OSS core (this repo):** contains generic placeholders and example
context files. `AGENTS.md` root operator profile becomes generic ("you are working
with the operator..."). Context files ship as templates in `contexts/_examples/`.
All domain references replaced with `${WALTER_DOMAIN}`. The regulatory research
skill is generalized to `regulatory-research-international` and accepts a
`WALTER_JURISDICTION` parameter.

**Layer 2 — Personal overlay (`~/.config/walter-os/overlay/`):** operator's own
AGENTS.md fragments, context files, and custom skills. The overlay is created by
`setup/personal-overlay-init.sh` (a new script that scaffolds the skeleton from
templates). The global AGENTS.md cascade checks for overlay files first and falls
back to the repo templates.

This preserves backward compatibility for existing operators: if the overlay
directory exists, it takes precedence. If not, the repo's generic templates load.
New operators get working generics immediately; existing operators migrate their
personal content to the overlay at their own pace.

## Acceptance Criteria

- [AC-1] `grep -r "xipherlabs" --include="*.md" --include="*.sh" --include="*.yml"
  --include="*.yaml" --include="*.json" --include="*.toml"` on all files
  **outside** `docs/specs/` and `contexts/_examples/` returns zero matches
  on the `v0.2.0-walter-oss` branch.
- [AC-2] `grep -r "project-a\|project-b\|private-domain" -i --include="*.md" --include="*.sh"`
  on all files outside `docs/specs/` and `contexts/_examples/` returns zero
  matches. (Case-insensitive. Historical spec references inside `docs/specs/`
  are exempt — they are a record, not active config.)
- [AC-3] `grep -riE "argentine law [0-9]|Law [0-9]{1,3}\.[0-9]{3}|AFIP|ARCA|small-taxpayer|gross-receipts|MEP-CCL|ANMAT"
  --include="*.md"` on all files outside `contexts/_examples/` returns zero
  matches. Country-specific law references removed from OSS core.
- [AC-4] `contexts/_examples/` directory exists and contains:
  - `work-template.example.md` — generic work context template with instructions
    to fill in company/stack details
  - `work-example.example.md` — representative `contexts/work/AGENTS.md` content,
    preserved as a reference example
  - `projects-personal-template.example.md` — generic projects-personal template
  - `projects-personal-example.example.md` — representative content preserved
  - `personal-template.example.md` — generic personal context template
  - `personal-example.example.md` — representative content preserved
- [AC-5] `setup/personal-overlay-init.sh` exists. Running it on a machine
  without `~/.config/walter-os/overlay/` creates the skeleton directory with
  empty template files. Running it on a machine that already has an overlay
  does not overwrite existing files (idempotent).
- [AC-6] `skills/regulatory-research-international/SKILL.md` exists. The
  original `skills/regulatory-research-argentina/SKILL.md` either:
  (a) moved to `contexts/_examples/skills/regulatory-research-argentina.example.md`
  as an operator example, or (b) retained in place but marked `@deprecated`
  with a pointer to the international version. T3 honored: kept in place with
  @deprecated frontmatter.
- [AC-7] `AGENTS.md` root operator profile section is replaced with a generic
  description that does not name the operator, example work org, or private
  operator location. A comment block in the file explains where to put the
  operator-specific profile (in the personal overlay).
- [AC-8] All compose files, `.env.example`, and service templates use
  `${WALTER_DOMAIN}` (for domain) and `${WALTER_ADMIN_EMAIL}`, `${WALTER_INITIAL_USER}`,
  `${WALTER_TIMEZONE}` (for bootstrap vars). No hardcoded hostnames.
- [AC-9] Bats test `tests/oss/depersonalization.bats` greps for the patterns
  in AC-1, AC-2, AC-3 and fails if any match is found outside exempt paths.
  This test runs in CI to prevent regressions.

## Non-goals

- Deleting the personal content: it moves to `contexts/_examples/` (in-repo,
  clearly labeled) and the operator's overlay (out-of-repo). Nothing is lost.
- Automating the migration of an existing operator's configs to the overlay:
  `personal-overlay-init.sh` creates the skeleton; the operator copies their
  content manually.
- Removing the Solana/example work org-specific skills from the repo: `solana-rpc-review`
  and `solana-program-review` are domain-specific but domain-agnostic-ish (any
  Solana operator would want them). They stay in `skills/` but their SKILL.md
  files are audited to remove example work org-specific references.

## Open questions

- Should `AGENTS.md` root's operator profile section be a `@include` pointing
  to `~/.config/walter-os/overlay/profile.md` (if it exists), or should it
  be a comment explaining where to customize? Spec says comment-based (simpler,
  no new include mechanism needed). Flag if reviewer disagrees.
- The `contexts/work/AGENTS.md` and `contexts/projects-personal/AGENTS.md`
  files in the repo root: after W-5, do they contain generic templates or are
  they empty stubs pointing to the overlay? Spec says: generic templates with
  enough content to be usable out of the box, plus a comment block directing
  operators to the overlay for customization. The overlay takes precedence via
  the cascade if present.

## Implementation plan

### Task 1: Grep audit — catalogue all personal references [AC-1, AC-2, AC-3]
- File: Audit only (no file writes in this task)
- Change: Run grep for maintainer domains and project-specific names,
  `argentine law [0-9]`, `Law [0-9]{1,3}.[0-9]{3}`, `AFIP`, `ARCA`,
  `small-taxpayer`, `gross-receipts`, `MEP-CCL`, `ANMAT`.
  Produce an annotated list of every file and line that needs changing.
  Output: comment in commit body, not a file.
- Verify: Audit list is non-empty (confirming the grep patterns work).

### Task 2: Replace domain references in compose/service files [AC-1, AC-8]
- File: `setup/vm/services/*/compose.yml`, `setup/vm/services/*/.env.*`,
  `setup/vm/services/homepage/services.yaml`, `.env.example` (bulk modify)
- Change: `sed -i 's/xipherlabs\.xyz/${WALTER_DOMAIN}/g'` equivalent across
  all compose and service files. Add `${WALTER_ADMIN_EMAIL}`,
  `${WALTER_INITIAL_USER}`, `${WALTER_TIMEZONE}` where currently hardcoded.
- Verify: AC-1 grep returns zero matches in `setup/` tree.

### Task 3: Create `contexts/_examples/` directory with example files [AC-4]
- File: `contexts/_examples/work-example.example.md` (new — representative
  `contexts/work/AGENTS.md`), `contexts/_examples/work-template.example.md`
  (new — generic), `contexts/_examples/projects-personal-example.example.md`
  (copy of current), `contexts/_examples/projects-personal-template.example.md`
  (generic), `contexts/_examples/personal-example.example.md` (representative),
  `contexts/_examples/personal-template.example.md` (generic)
- Change: Create copies first, then genericize the live context files.
- Verify: 6 files exist in `contexts/_examples/`. Live context files no longer
  contain example work org/example civic app/example medical app/Argentine references (AC-2, AC-3).

### Task 4: Genericize `contexts/work/AGENTS.md` [AC-2, AC-7]
- File: `contexts/work/AGENTS.md` (modify)
- Change: Remove example work org-specific content. Replace with generic work context
  template: company name placeholder, stack placeholder, PM tool choice, git
  provider choice, CI notes. Add comment block pointing to overlay.
- Verify: AC-2 grep on `contexts/work/AGENTS.md` returns zero matches.

### Task 5: Genericize `contexts/projects-personal/AGENTS.md` [AC-2, AC-3]
- File: `contexts/projects-personal/AGENTS.md` (modify)
- Change: Remove example civic app/example medical app/Argentine law references. Replace with
  generic projects-personal template: active projects placeholder, regulatory
  skill placeholder (pointing to `regulatory-research-international`), toolchain
  notes as generic choices not the operator's specific tools.
- Verify: AC-2 and AC-3 greps on file return zero matches.

### Task 6: Genericize `contexts/personal/AGENTS.md` [AC-3]
- File: `contexts/personal/AGENTS.md` (modify)
- Change: Remove AFIP/ARCA/small-taxpayer/gross-receipts/MEP-CCL references. Replace
  Argentina-specific financial section with generic personal finance placeholder.
  Keep the spirit (privacy-first, PHI rules, journaling) — remove the
  jurisdiction-specific details.
- Verify: AC-3 grep on file returns zero matches.

### Task 7: Genericize `AGENTS.md` root operator profile [AC-7]
- File: `AGENTS.md` (modify)
- Change: Replace the private operator profile with a generic operator profile
  template. Add comment explaining the overlay path for personalization.
- Verify: `grep -i "operator-name\|project-name\|private-location" AGENTS.md` returns zero matches.

### Task 8: Create `regulatory-research-international` skill [AC-6]
- File: `skills/regulatory-research-international/SKILL.md` (new)
- Change: Generalized version of the Argentine skill. Accepts `WALTER_JURISDICTION`
  (e.g., "Argentina", "EU", "US-healthcare") and `WALTER_REGULATORY_DOMAIN`
  (e.g., "procurement", "data-protection", "financial"). Skill drives research
  using these parameters rather than hardcoded Argentine law names.
- Verify: File exists. `walter explain regulatory-research-international`
  returns non-empty output. Skill text does not mention Argentine law names.

### Task 9: Move `regulatory-research-argentina` to examples [AC-6]
- File: `skills/regulatory-research-argentina/` (move to
  `contexts/_examples/skills/regulatory-research-argentina.example.md`)
- Change: Move the full SKILL.md content into the examples directory as a
  reference for operators in Argentina. The `skills/` directory entry is removed.
  Update `AGENTS.md` skill references accordingly.
- Verify: `ls skills/regulatory-research-argentina` returns "not found".
  `ls contexts/_examples/skills/` shows the example file.

### Task 10: Write `setup/personal-overlay-init.sh` [AC-5]
- File: `setup/personal-overlay-init.sh` (new)
- Change: Creates `~/.config/walter-os/overlay/{contexts,skills}/` skeleton.
  Copies `*-template.example.md` files as starting points. Does not overwrite
  existing files. Prints instructions on next steps.
- Verify: Running on empty machine creates skeleton. Running again produces
  "overlay already exists, nothing to do" message.

### Task 11: Write `tests/oss/depersonalization.bats` [AC-9]
- File: `tests/oss/depersonalization.bats` (new)
- Change: Bats test that greps for each personal reference pattern and asserts
  zero matches outside exempt paths. Also asserts `contexts/_examples/` contains
  exactly 6 expected files.
- Verify: Test passes on clean repo. Introducing "xipherlabs.xyz" in a non-exempt
  file causes test to fail.

## References

- `docs/decisions/0011-depersonalization-strategy.md` — decision: dual-layer
  overlay vs single-repo+gitignore vs env-substitution only
- `contexts/work/AGENTS.md` — source to be genericized
- `contexts/projects-personal/AGENTS.md` — source to be genericized
- `contexts/personal/AGENTS.md` — source to be genericized
- `skills/regulatory-research-argentina/` — skill to be generalized
