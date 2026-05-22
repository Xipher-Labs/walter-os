# Walter-OS v1.0 Stability Charter

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-10

## Problem

Walter-OS is currently at v0.4.5-alpha. The README says "breaking changes are
normal until v1.0" and instructs adopters to pin to a specific commit or tag.
This is honest, but it means that every adopter who builds a workflow on top
of Walter-OS must treat the upgrade path as a manual review exercise every
time. Without a clear v1.0 stability promise, the framework cannot position
itself as a reliable foundation — which is a prerequisite both for broader OSS
adoption and for the IdeaOS commercial product built on top.

The question "what is v1.0?" must be answered explicitly before the project
can credibly pursue the operator's 6-month roadmap (v1.0 stable → 500-1000
stars → IdeaOS MVP).

## Proposed solution

Define v1.0 as a stability milestone, not a feature milestone. v1.0 means:
"the interfaces listed in the stability surface are frozen for the v1.x line,
with a documented deprecation policy for any change that breaks them." It does
NOT mean "all features are implemented" — the OSS Trust roadmap will continue
after v1.0.

## Stability surface (what is frozen at v1.0)

The following interfaces constitute the v1.0 stability promise:

### Layer 1 — Agent contract (highest priority)

- The `AGENTS.md` cascade mechanism: the three-level global → context →
  repository hierarchy, conflict resolution (most-specific-wins), and the
  overlay path (`~/.config/walter-os/overlay/`).
- The section names and semantic meaning of sections in the global `AGENTS.md`
  (adding new sections is allowed; removing or renaming existing sections
  requires deprecation).
- The `WALTER_BRANCH_FLOW` environment variable and its two allowed values
  (`single-tier`, `three-stage`).
- The `WALTER_CONTEXT` environment variable for context selection.

### Layer 2 — Skills format

- The `SKILL.md` file format: presence of a `## When to use` or equivalent
  trigger section, a `## Workflow` section. Adding new sections is allowed.
- The skills directory structure: `skills/<skill-name>/SKILL.md`.
- Skills discovery: the agent finds skills via symlinks in `~/.claude/skills/`.

### Layer 3 — CLI interface

- `walter-os baseline-hooks` — command name and behavior (reads hooks,
  writes `hook-checksums.json`).
- `walter-os doctor` — command name and basic PASS/FAIL output contract.
- `walter-os profile` — command name and `high-risk`/`default` argument.
- `install.sh --upgrade` — idempotent re-install behavior.

### Layer 4 — Hook behavior

- `hooks/approval-gate.sh` — the "blocked for ALL tiers" list is frozen.
  Items can be added (more restrictive); items cannot be removed without a
  deprecation cycle.
- `hooks/branch-flow-guard.sh` — the block on direct push to main/staging/
  production is frozen.

### NOT in the stability surface (can change without deprecation)

- The service composition in `setup/walter-host/` (Docker Compose files,
  service versions, configuration).
- The MCP catalog (`mcp/servers.json`) — servers can be added, updated, or
  removed as the ecosystem evolves.
- The skills catalog content — existing skills can be updated; skill content
  is not a frozen API.
- Internal scripts in `bin/`, `scripts/`, and `setup/`.
- The Walter Council agent definitions.
- Control Tower UI.

## Deprecation policy

For any change to the stability surface:
1. The change is flagged as "deprecated" in the release notes of the minor
   version preceding the breaking change.
2. The deprecated behavior continues to work for one full minor version.
3. The breaking change ships in the next minor version.

Example: if v1.3.0 deprecates a section name in AGENTS.md, the old name still
works in v1.3.x. It is removed in v1.4.0.

For MAJOR changes (changes to the cascade mechanism itself, changes to the
approval-gate blocked list that make it more permissive), the deprecation
window is two minor versions.

## v1.0 trigger conditions

v1.0 is cut when ALL of the following are true:

1. Depersonalization deep cleanup complete (spec: `depersonalization-deep-cleanup.md`).
   AGENTS.md passes the full depersonalization test suite.
2. Cursor adapter complete (spec: `cursor-adapter-completion.md`).
   `walter-os doctor --cursor` reports PASS on a clean install.
3. Walter-OS Lite complete (spec: `walter-os-lite-entry-tier.md`).
   `lite.md` installs in under 60 seconds, verified on macOS and Ubuntu 24.04.
4. AGENTS.md cascade documented as a standalone spec document.
5. CLA or DCO enforcement active (ADR-0019 implemented).
6. OSS Trust roadmap items through Layer B complete (per
   `docs/specs/oss-trust-roadmap.md` — items A-1 through B-3).
7. The conformance test suite covers all items in the stability surface above.
   Specifically: `tests/oss/conformance.bats` must pass with at minimum one
   test per stability surface item.
8. No P0 or P1 security findings open (per the severity gate framework in
   `docs/specs/pr-review-severity-gate.md`).
9. `report.log` and all other runtime artifacts removed from the repo.
10. CHANGELOG documents a stable v1.0 entry.

## Release cadence post-v1.0

- **Patch releases (v1.x.y)**: bug fixes, security patches, documentation
  updates. No deprecation required.
- **Minor releases (v1.x.0)**: new features, new skills, new services, new
  CLI subcommands. May include deprecations (with one-version notice).
- **Major releases (v2.0.0)**: breaking changes to the stability surface.
  Two-version deprecation required.

Cadence target (informational, not contractual): patch releases as needed,
minor releases approximately quarterly, major releases no more than annually.

## Acceptance Criteria

- [AC-1] This spec and ADR-0021 exist and define the stability surface,
  deprecation policy, and v1.0 trigger conditions as above.
- [AC-2] `tests/oss/conformance.bats` exists with at least one test per
  stability surface item (12 minimum tests).
- [AC-3] The README "Status" section is updated to distinguish the current
  alpha state from the stability promise that v1.0 will carry.
- [AC-4] `CHANGELOG.md` has a "v1.0.0 — Stability Charter" section that
  links to this spec and lists the stability surface.

## Non-goals

- Feature-completeness. v1.0 is a stability milestone.
- Committing to a specific date for v1.0.
- Freezing the service stack (`setup/walter-host/`) — it evolves independently.

## Open questions

- Q1: Should the conformance suite be a separate repository or live in-tree?
  Recommendation: in-tree at `tests/oss/conformance.bats` for v1.0; extract
  to a separate tool if third parties want to test their AGENTS.md implementations.

## References

- `docs/decisions/0021-v1-0-stability-charter.md` — the ADR
- `docs/specs/oss-trust-roadmap.md` — parallel security workstream
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-10
