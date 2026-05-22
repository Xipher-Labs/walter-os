# 0021. v1.0 Stability Charter

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/walter-os-v1-0-stability-charter.md`

## Context

Walter-OS is at v0.4.5-alpha. The README explicitly warns: "breaking changes
are normal until v1.0. Pin to a specific commit or tag in production." This
is honest but limits adoption — teams that want to build on Walter-OS cannot
reasonably commit if the interface is undefined.

The operator's strategic plan sets a goal: v1.0 stable → 500-1000 GitHub
stars → IdeaOS MVP. This sequence is predicated on v1.0 being a meaningful
milestone that the community can rely on.

## Decision

**Define v1.0 as a stability milestone with an explicit stability surface,
a deprecation policy, and trigger conditions that must ALL be met before
the v1.0 tag is cut.**

The stability surface, deprecation policy, and trigger conditions are defined
in full in `docs/specs/walter-os-v1-0-stability-charter.md`. The key points
are recorded here as a permanent decision record.

### Stability surface (frozen at v1.0)

The following interfaces are frozen for the v1.x release line:

- The AGENTS.md cascade mechanism (three-level hierarchy, overlay path,
  most-specific-wins resolution).
- Section names and semantic meaning in the global AGENTS.md.
- `WALTER_BRANCH_FLOW` and `WALTER_CONTEXT` environment variables.
- The `SKILL.md` format and skills directory structure.
- Core CLI commands: `baseline-hooks`, `doctor`, `profile`, `install.sh --upgrade`.
- The approval-gate blocked-for-all-tiers list (additions allowed, removals require
  deprecation).

The service composition (`setup/walter-host/`), MCP catalog, skills content,
and Council agent definitions are NOT in the stability surface.

### Deprecation policy

Changes to the stability surface require:
- One-minor-version notice for minor breaking changes.
- Two-minor-version notice for major breaking changes (changes to the cascade
  mechanism, changes to the approval-gate list that make it more permissive).
- Breaking changes are never introduced in patch releases.

### v1.0 trigger conditions (all must be met)

1. Depersonalization complete (passes full depersonalization test suite).
2. Cursor adapter complete (`doctor --cursor` passes on clean install).
3. Walter-OS Lite complete (60-second install verified on macOS and Ubuntu 24.04).
4. AGENTS.md cascade documented as standalone vendor-neutral spec.
5. CLA or DCO enforcement active.
6. OSS Trust roadmap items through Layer B complete.
7. Conformance test suite covers all stability surface items.
8. No open P0 or P1 security findings.
9. `report.log` and all runtime artifacts removed.
10. CHANGELOG has a v1.0 stable entry.

### Release cadence post-v1.0

- Patch: bug fixes, security patches, docs. No deprecation.
- Minor: new features, skills, services, CLI subcommands. May include deprecations.
- Major: breaking changes to the stability surface. Two-minor-version notice.

Target cadence (informational): patches as needed, minors approximately
quarterly, majors no more than annually.

## Consequences

**Positive:**
- Adopters have a clear signal for when to upgrade from pinned commits to
  following the release branch.
- The trigger conditions give the operator a concrete checklist to drive
  toward v1.0 rather than an indefinite "when it's ready."
- The stability promise supports IdeaOS's positioning ("built on stable
  walter-os v1.0").

**Negative:**
- The operator commits to a deprecation cycle. This adds process overhead
  for future changes to the stability surface.
- The trigger conditions include the OSS Trust roadmap items through Layer B,
  which involves external tooling (nsjail/firejail on Linux, audit chain).
  This makes v1.0 dependent on security infrastructure that is non-trivial.

**Reversible:**
- The stability surface can be extended (more items frozen) without breaking
  compatibility. It can be shrunk (items removed from the surface) only through
  a major version bump with the full deprecation cycle.

## Migration

No migration required. This ADR takes effect when it is accepted. Implementers
reference it when working on items in the v1.0 trigger conditions list.

## References

- `docs/specs/walter-os-v1-0-stability-charter.md` — full stability charter
- `docs/specs/oss-trust-roadmap.md` — OSS Trust items (trigger condition 6)
- `docs/specs/walter-os-oss-readiness-roadmap.md` — roadmap context
