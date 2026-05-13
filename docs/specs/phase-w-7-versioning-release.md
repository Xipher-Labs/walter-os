# W-7: Versioning and Release Process

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

Walter-OS has no single source of truth for its version. The README says "v0.1.0 =
Walter-Personal baseline" but that string exists only in a comment in the status
table, not in a file that tooling can read. There is no automated changelog,
no release artifacts, and no way for an operator running a forked version to know
if there is a newer upstream release.

This matters less when there is one operator. For OSS adoption, adopters need to
know what version they are running, what changed between versions, and whether they
should upgrade. Without a version file and a release process, adopters have no
anchor — they cannot file a bug report with a version number, cannot cherry-pick
a specific version, and cannot know if a bug they hit was already fixed upstream.

The Control Tower UI (Phase U) also needs a version to display. Currently it
shows nothing.

## Proposed solution

Three parts:

**1. `VERSION` file** at repo root — single line, semver string (e.g., `0.2.0`).
This is the single source of truth. Every tool that needs the version reads this file.

**2. Changelog automation** — a GitHub Actions workflow that runs
`git-cliff` (a conventional-commits-aware changelog generator) on every push to
`main` and every tag. The `CHANGELOG.md` is generated (or updated) and committed
back to `main`. On tags, a GitHub Release is created with the generated changelog
section as the release body.

**3. CLI version command + update check** — `walter-os version` reads `VERSION`,
optionally queries the GitHub API for the latest tag, and prints current version +
"update available: vX.Y.Z" if applicable. The Control Tower header reads the same
version and displays an "update available" badge when the check returns a newer
version.

## Acceptance Criteria

- [AC-1] `cat VERSION` from the repo root returns `0.2.0` on the v0.2.0 release
  tag. The file contains exactly one line with no trailing whitespace (spaces or
  tabs). A single trailing newline is acceptable and expected per POSIX text-file
  convention.
- [AC-2] `walter-os version` prints: `Walter-OS v0.2.0` (or current version).
  With `GITHUB_TOKEN` set (or public API), also prints `(up to date)` or
  `(update available: vX.Y.Z)` depending on the latest upstream tag.
- [AC-3] `CHANGELOG.md` exists at repo root. The v0.2.0 entry is a hand-written
  narrative documenting Council v2 (Phases F → V) and Phase W OSS readiness;
  this is intentional because the repo history predates the conventional-commit
  convention and `git-cliff` cannot auto-generate meaningful entries from those
  commits. From v0.3.0 onward, `git-cliff` will generate entries automatically
  from conventional commit subjects (`## [X.Y.Z] — YYYY-MM-DD` with subsections
  `### Features`, `### Fixes`, `### Docs`). A header comment in `CHANGELOG.md`
  documents this transition.
- [AC-4] `.github/workflows/release.yml` exists and triggers on push of a
  `v*` tag. The workflow: (a) reads `VERSION`, (b) runs `git-cliff` to generate
  the changelog section for the tag, (c) creates a GitHub Release with that
  body, (d) attaches no binary artifacts (Walter-OS is scripts only — no build
  artifact needed).
- [AC-5] The Control Tower UI (`apps/control-tower/`) reads `VERSION` (or an
  env var `WALTER_VERSION` set by the compose or the start script from `VERSION`)
  and displays it in the header. When the update check returns a newer version,
  a badge "Update available: vX.Y.Z → changelog" appears in the header. This
  is a visual element only; no automatic update logic.
- [AC-6] Bats tests in `tests/cli/version.bats` assert: `walter-os version`
  exits 0, output contains a semver string matching `[0-9]+\.[0-9]+\.[0-9]+`,
  and the version matches the content of `VERSION`. Also tests the version
  comparison logic (`_version_is_newer "0.2.0" "0.1.0"` → true).
- [AC-7] `git-cliff.toml` at repo root configures the changelog format and
  conventional commit type mappings. File is committed to the repo.

## Non-goals

- Binary release artifacts: Walter-OS is bash scripts and markdown. `git clone`
  or `git pull` is the distribution mechanism.
- Automated publishing to a package registry (npm, Homebrew, etc.): deferred
  to v0.3.0 if adoption warrants it.
- Automated `VERSION` bumping: the operator sets the version in `VERSION`
  before tagging. No `bump-version.sh` script is needed for v0.2.0.
- Semantic version enforcement via CI (blocking PRs for incorrect version bump):
  deferred.

## Open questions

- Should `CHANGELOG.md` be committed to the repo on every CI run (possible commit
  noise on `main`) or only generated on release tags? Spec says: generated on
  tag push only. On `main` push, the workflow dry-runs `git-cliff` but does not
  commit. This keeps `CHANGELOG.md` clean — it only contains released versions.
- `git-cliff` vs `release-please` (Google): spec chooses `git-cliff` because
  it is a single binary with no authentication requirements beyond the GitHub
  Actions default token. `release-please` requires a more complex setup and
  the PR-based flow is heavier than what Walter-OS needs. Documented in ADR
  section of this spec (see References).

## Implementation plan

### Task 1: Add `VERSION` file [AC-1]
- File: `VERSION` (new, repo root)
- Change: Single line: `0.2.0`. No trailing newline (or consistent with repo
  convention — confirm with reviewer).
- Verify: `cat VERSION | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$"` exits 0.

### Task 2: Implement `walter-os version` subcommand [AC-2, AC-6]
- File: `bin/walter-os` (modify)
- Change: Add `version` subcommand. Reads `$WALTER_OS_HOME/VERSION`. If
  `GITHUB_TOKEN` is set or repo is public, curls
  `https://api.github.com/repos/<owner>/walter-os/releases/latest` and
  compares tags. Prints update message if newer. `_version_is_newer()` utility
  function using `sort -V`.
- Verify: `bats tests/cli/version.bats` passes. Mocked GitHub API response
  with newer version triggers "update available" message.

### Task 3: Add `git-cliff.toml` [AC-3, AC-7]
- File: `git-cliff.toml` (new, repo root)
- Change: Configure `git-cliff` for conventional commits. Type mappings:
  `feat` → Features, `fix` → Fixes, `docs` → Docs, `refactor` → Refactors,
  `perf` → Performance, `security` → Security, `chore` → Chores (excluded
  from release notes), `test` → excluded. Tag pattern: `v[0-9]*`.
- Verify: `git cliff --unreleased --tag v0.2.0` (with git-cliff installed)
  exits 0 and produces a non-empty changelog section.

### Task 4: Generate initial `CHANGELOG.md` [AC-3]
- File: `CHANGELOG.md` (new, repo root)
- Change: Run `git cliff --tag v0.2.0 -o CHANGELOG.md` to generate the full
  changelog from all commits. Commit the file.
- Verify: `CHANGELOG.md` exists. Contains `## [0.2.0]` section.

### Task 5: Write `.github/workflows/release.yml` [AC-4]
- File: `.github/workflows/release.yml` (new)
- Change: Workflow triggered on `push: tags: ['v*']`. Steps:
  (1) checkout with full history,
  (2) install git-cliff via cargo,
  (3) run git-cliff for the pushed tag,
  (4) create GitHub release via `gh release create` with generated body.
  Uses `GITHUB_TOKEN` (default Actions token, sufficient for release creation
  on the same repo).
- Verify: On a test tag push to a fork, release is created with correct body.

### Task 6: Update Control Tower header for version display [AC-5]
- File: `apps/control-tower/src/components/Header.tsx` (modify)
  or equivalent component file
- Change: Read `process.env.WALTER_VERSION` (set in compose via
  `WALTER_VERSION=$(cat VERSION)` in the bootstrap script). Display in header.
  If `process.env.WALTER_UPDATE_AVAILABLE` is set (written by a background
  check), show the badge.
- Verify: Local compose run with `WALTER_VERSION=0.2.0` shows "v0.2.0" in
  the Control Tower header.

### Task 7: Write `tests/cli/version.bats` [AC-6]
- File: `tests/cli/version.bats` (new)
- Change: Tests: `walter-os version` exits 0, output matches semver regex,
  `_version_is_newer` logic (4 test cases: newer/older/equal/pre-release).
- Verify: `bats tests/cli/version.bats` passes.

## References

- `bin/walter-os` — CLI for new subcommand
- `apps/control-tower/` — Phase U Control Tower (header modification)
- `docs/decisions/0008-control-tower-stack.md` — Control Tower architecture
- `git-cliff` documentation: https://git-cliff.org
