# Walter-OS OSS-Ready Docs

**Status**: Draft
**Owner**: operator (Xipher Labs)
**Created**: 2026-05-11
**PR**: #51 (v0.2.0 OSS launch chain)

---

## Problem

After PR #47 (depersonalization + Walter-Bridge expansion + CLI client modules),
PR #48 (AGPLv3 + Xipher Labs brand + COMMERCIAL.md), and PR #49 (walter-personal
skeleton), the Walter-OS repository has a sound technical foundation and a clean
OSS identity. What it still lacks is the standard set of files a first-time visitor
expects when evaluating a framework for adoption.

The current README.md was written for the operator — it documents the Council v2
phases in flight, references personal overlay details, and assumes the reader is
configuring their own Walter-OS instance. A new visitor landing on the repo for the
first time gets a dense reference document with no clear "is this for me?" moment,
no 60-second on-ramp, and no guidance on how to contribute. The barrier to forming
an accurate first impression is too high.

Beyond the README, there are no standard community health files. There is no
CONTRIBUTING.md, so a would-be contributor has no way to know the workflow
(brainstorm → plan → TDD → conventional commit), the AGPL contribution implications,
or which CI checks must pass. There is no SECURITY.md, so a security researcher who
finds a vulnerability has no disclosed channel. There is no CODE_OF_CONDUCT.md,
which is a hard requirement for most OSS platforms' "community standards" badges.
There is no CHANGELOG.md, so adopters cannot see what changed between releases.
There are no GitHub issue or PR templates, so bug reports arrive without the context
needed to reproduce them and PRs lack standard spec-link discipline.

These gaps do not block using Walter-OS, but they do block the repo from meeting the
"OSS-ready" bar expected by GitHub, package registries, and early adopters evaluating
whether to commit to the framework.

## Proposed solution

This PR adds eight files at repo root and in `.github/`:

1. **README.md** — full rewrite, adopter-first. The new README leads with a
   one-paragraph value prop, orients the three target personas (Builder / Founder /
   Operator), provides a 60-second Quick Start (`git clone && ./install.sh`), and
   indexes the major docs. The deep reference content (Council v2 phases, CLI
   command catalog, Walter-VM service list) is preserved but moved below a clear
   fold. License and project-status badges are added to the header.

2. **CONTRIBUTING.md** — contribution workflow, AGPL implications for PRs,
   dev setup, required superpowers plugin, conventional commits, and the
   brainstorm → plan → TDD → review chain that AGENTS.md mandates.

3. **SECURITY.md** — responsible disclosure policy with `security@xipherlabs.xyz`
   placeholder (HTML TODO comment for mailbox setup), 90-day window, scope
   definition, and an honest "no bug bounty" statement.

4. **CODE_OF_CONDUCT.md** — Contributor Covenant 2.1 verbatim, project name
   substituted ("Walter-OS"), enforcement contact `conduct@xipherlabs.xyz` with
   HTML TODO comment.

5. **CHANGELOG.md** — seeded with v0.2.0 entry (Keep a Changelog 1.1 schema)
   summarizing Phase W deliverables and the AGPLv3 switch.

6. **.github/ISSUE_TEMPLATE/bug.md** — structured bug template with compose
   profile, OS version, redacted log, expected vs actual, reproduction steps.

7. **.github/ISSUE_TEMPLATE/feature.md** — feature request template with persona
   selector, use case, proposed solution, alternatives.

8. **.github/PULL_REQUEST_TEMPLATE.md** — PR template linking spec, test plan
   checkboxes, and the Copilot review REST API reminder.

Plus a bats test suite (`tests/oss/oss-ready-docs.bats`) that asserts all eight
files exist and contain the required strings, so CI enforces the complete state
going forward.

## Acceptance Criteria

- [AC-1] `README.md` rewrite contains:
  - Hero: "Walter-OS — A self-hostable AI-agent operations framework by Xipher Labs"
  - One-paragraph value prop (what it is, why it exists, who it is for)
  - Personas section: Builder / Founder / Operator
  - 60-second Quick Start block (`git clone https://github.com/xipher-labs/walter-os &&
    cd walter-os && ./install.sh`)
  - Docs index section with links to CONTRIBUTING.md, SECURITY.md,
    `docs/specs/`, `docs/decisions/`, and the superpowers plugin install
  - License badge: AGPLv3 shields.io badge linking to `https://www.gnu.org/licenses/agpl-3.0`
  - Status badge: "early alpha" (honest)
  - Built-with section naming: Anthropic Claude, LiteLLM, obra/superpowers,
    Forgejo, Plane, Penpot, Grafana, n8n, Headscale/Tailscale
  - Sponsor/follow links: `https://github.com/operator-handle` and
    `https://github.com/xipher-labs` org placeholder
  - "by Xipher Labs" attribution in the hero and footer

- [AC-2] `CONTRIBUTING.md` contains:
  - AGPLv3 contributor DCO statement: "By submitting a PR you agree your
    contribution is AGPLv3-compatible and may be used under those terms."
  - Dev setup: `git clone`, `./setup/personal-overlay-init.sh --from-skeleton`,
    `./install.sh --dev`
  - Required plugin section: `obra/superpowers` with install command
  - Workflow section: brainstorm → plan (`/write-plan`) → TDD (`RED-GREEN-REFACTOR`)
    → conventional commit → PR
  - Conventional commits format table with ≤72 char subject line rule
  - CI gate: all checks must be green before requesting review

- [AC-3] `SECURITY.md` contains:
  - Disclosure email `security@xipherlabs.xyz` wrapped in an HTML TODO comment:
    `<!-- TODO(pre-launch): set up security@xipherlabs.xyz mailbox -->`
  - "90-day responsible disclosure window" statement
  - "We do not currently run a bug bounty program" statement
  - PGP key placeholder: instruction to fetch from `keys.openpgp.org`
    (key fingerprint placeholder)
  - In-scope definition: Walter-OS source code, configs, CI pipeline
  - Out-of-scope definition: third-party deps (report upstream), infrastructure
    operated by adopters

- [AC-4] `CODE_OF_CONDUCT.md` is Contributor Covenant 2.1 verbatim with:
  - All instances of `[INSERT CONTACT METHOD]` replaced by `conduct@xipherlabs.xyz`
  - All instances of `[INSERT COMMUNITY NAME]` replaced by `Walter-OS`
  - HTML TODO comment after the contact line:
    `<!-- TODO(pre-launch): set up conduct@xipherlabs.xyz mailbox -->`

- [AC-5] `CHANGELOG.md` contains:
  - Header line: `<!-- Keep a Changelog 1.1 | SemVer -->`
  - `## [Unreleased]` section (empty body — just the heading)
  - `## [0.2.0] — 2026-05-11` section with subsections:
    - `### Added` listing: multi-provider Walter-Bridge (LiteLLM expansion,
      PR #47), CLI client modules for major LLM providers (PR #47), AGPLv3
      license + Xipher Labs attribution (PR #48), COMMERCIAL.md dual-licensing
      hook (PR #48), walter-personal skeleton pattern (PR #49), W-10
      depersonalization + personal overlay layer (PR #47), OSS-ready
      community health files (this PR)
    - `### Changed` listing: README rewritten as adopter-first, LICENSE
      switched from Apache-2.0 to AGPLv3
  - Footer link references:
    `[0.2.0]: https://github.com/xipher-labs/walter-os/releases/tag/v0.2.0`
    `[Unreleased]: https://github.com/xipher-labs/walter-os/compare/v0.2.0...HEAD`

- [AC-6] `.github/ISSUE_TEMPLATE/bug.md` contains:
  - YAML frontmatter with `name: Bug report` and `labels: bug`
  - Fields: Walter-OS version, compose profile (core / devrel / design /
    assistant / all), OS + version, steps to reproduce, expected behavior,
    actual behavior, redacted logs (code fence), additional context

- [AC-7] `.github/ISSUE_TEMPLATE/feature.md` contains:
  - YAML frontmatter with `name: Feature request` and `labels: enhancement`
  - Fields: persona (Builder / Founder / Operator — choose one), use case
    (what are you trying to do), proposed solution, alternatives considered,
    additional context

- [AC-8] `.github/PULL_REQUEST_TEMPLATE.md` contains:
  - Spec link field: `**Spec**: docs/specs/<slug>.md`
  - Problem summary (1-2 sentences) field
  - Test plan checklist: `[ ] Unit / bats tests pass`,
    `[ ] Acceptance criteria in spec have corresponding tests`,
    `[ ] markdownlint clean (if applicable)`,
    `[ ] `grep -rn "TODO.*mailbox"` returns expected count (if adding contacts)`
  - Copilot review reminder with the exact REST API snippet from AGENTS.md:
    ```
    gh api -X POST \
      /repos/<owner>/<repo>/pulls/<NUM>/requested_reviewers \
      --input - <<<'{"reviewers":["copilot-pull-request-reviewer[bot]"]}'
    ```
  - Checklist item: `[ ] Copilot review requested (REST API above)`

- [AC-9] `tests/oss/oss-ready-docs.bats` exists and contains assertions that:
  - All 8 files exist at their expected paths
  - `README.md` contains "Xipher Labs" and "AGPL"
  - `CONTRIBUTING.md` contains "superpowers" and "AGPLv3"
  - `SECURITY.md` contains "security@xipherlabs.xyz" and
    `"TODO(pre-launch)"` (the TODO comment pattern)
  - `CODE_OF_CONDUCT.md` contains "Contributor Covenant" and "2.1"
  - `CHANGELOG.md` contains "[0.2.0]"
  - `.github/ISSUE_TEMPLATE/bug.md` YAML frontmatter includes `name:` and `labels:`
  - `.github/ISSUE_TEMPLATE/feature.md` YAML frontmatter includes `name:` and `labels:`
  - `.github/PULL_REQUEST_TEMPLATE.md` contains "Copilot"

- [AC-10] All contact email placeholders follow the same pattern so a single
  grep catches them all before launch:
  - Pattern: `<!-- TODO(pre-launch):` appearing on the line immediately before
    or after the `@xipherlabs.xyz` address
  - Emails present: `security@xipherlabs.xyz`, `conduct@xipherlabs.xyz`
    (COMMERCIAL.md has `licensing@xipherlabs.xyz` which was shipped in PR #48
    with the same pattern — the grep catches all four addresses in one pass)
  - `grep -rn "TODO(pre-launch)" . --include="*.md"` returns ≥ 3 matches
    (security, conduct, licensing)

## Non-goals

- NOT setting up any `@xipherlabs.xyz` mailboxes — operator action, pre-launch checklist
- NOT adding a GitHub Pages site or landing page — separate v0.2.1+ initiative
- NOT writing API reference documentation — Walter-OS is a framework, not a library API
- NOT adding logo / brand assets — separate Xipher Labs brand work
- NOT writing a release-notes blog post — DevRel content, post-launch
- NOT signing or tooling a formal CLA — deferred to v0.2.x contributor growth decision
- NOT adding SPDX headers to individual source files — repo-level LICENSE is sufficient
  at this release tier (v0.3.x concern per PR #48 spec)
- NOT changing the existing `.github/workflows/` CI files — those are in scope for
  Council v2 phases, not this PR

## Open questions

- The canonical repo URL placeholder is `https://github.com/xipher-labs/walter-os`.
  If the operator switches to `xipher-labs/walter-os` before tagging v0.2.0, a
  single `sed` pass updates the two CHANGELOG footer links and the README Quick Start
  URL. Flag for pre-launch checklist — do not block this PR on the org decision.
- The README Quick Start says `./install.sh`. PR #47 mentions W-6 (install wizard)
  is a separate Phase W item. If W-6 lands before this PR merges, the Quick Start
  command may need `--wizard` flag. The implementer should check whether W-6 has
  landed on the branch being targeted. If not, `./install.sh` is correct as-is.
- "early alpha" vs "alpha" for the status badge — the README currently says
  "Not stable. Council v2 is in PRs; the catalog is still moving." Post-PR-51
  all Council v2 PRs are assumed merged (they are the v0.2.0 chain). "alpha" alone
  may be more appropriate than "early alpha" if Council v2 is done. Operator to
  confirm before badge text is finalised — implementer should use "alpha" as default
  and note this as a pre-launch confirmation item.

## References

- `docs/specs/walter-oss-license-switch.md` — PR #48, AGPLv3 + COMMERCIAL.md
- `docs/specs/phase-w-5-depersonalization.md` — PR #47, personal overlay + templates
- `docs/specs/walter-personal-skeleton.md` — PR #49, walter-personal skeleton
- `docs/specs/phase-w-overview.md` — Phase W overview (W-1 through W-10)
- `tests/oss/license-files.bats` — existing OSS test suite (do not modify)
- `tests/oss/depersonalization.bats` — existing OSS test suite (do not modify)
- `AGENTS.md` §"Review loop" — the Copilot REST API snippet that PR template must quote
- https://www.contributor-covenant.org/version/2/1/code_of_conduct/ — CoC source
- https://keepachangelog.com/en/1.1.0/ — Keep a Changelog 1.1 schema
- https://github.com/xipher-labs/walter-os — canonical public repo URL (placeholder)
