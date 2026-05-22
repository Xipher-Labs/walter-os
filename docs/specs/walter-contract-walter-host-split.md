# walter-contract vs walter-host: Monorepo or Split?

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-09

## Problem

The operator's strategic plan proposes splitting the current `walter-os`
monorepo into two repositories:
- `xipher-labs/walter-contract` — the agent contract layer (AGENTS.md cascade,
  skills, hooks, Council definitions, MCP profiles, disciplines)
- `xipher-labs/walter-host` — the Docker Compose service stack (25+ services,
  bootstrap scripts, VM provisioning)

The motivation is that the contract layer is a lightweight framework (just
Markdown files and shell scripts) while the host stack is a heavy optional
component. Separating them would let the contract repo stand as a clean,
approachable standard without the intimidating 25-service stack alongside it.

This spec evaluates the split. The recommendation is stated explicitly.

## Recommendation: Do NOT split the repo at this time

**Recommendation: maintain the monorepo.** The audit finding that motivates the
split ("walter-host is described as optional but the Council depends on it") is
real — but the correct fix is documentation and narrative, not a repo split.
The costs of splitting now exceed the benefits.

### Rationale

**Cost 1 — Release coordination overhead.** Today, a change that touches both
a skill and the compose file that skill relies on goes into one PR with one
review cycle. After the split, cross-repo changes require coordinated PRs,
version pinning between repos, and a compatibility matrix. For a project with
one maintainer at v0.4.5-alpha, this is operationally expensive without
proportional benefit.

**Cost 2 — Broken install story.** Today, `install.sh` symlinks skills,
agents, commands, hooks, and MCP profiles in one step. After the split, a new
adopter would need to clone two repos and understand which one to clone first.
The four-tier install system explicitly collapses the complexity into one entry
point. Splitting the repo breaks that.

**Cost 3 — The Walter Council still couples the layers.** Even after a repo
split, the Council agents (in `walter-contract`) need a Plane URL and a
LiteLLM key (from `walter-host`) to function. The split does not eliminate
the coupling; it makes it a cross-repo coupling instead of an in-repo one.
The narrative inconsistency the audit identified would be replaced by a
dependency version table.

**Benefit 1 — Cleaner README landing page for the contract repo.** This is
real but achievable in the monorepo by reorganizing the README to lead with
the contract layer and move the host stack documentation to a dedicated
`docs/operational/walter-host/` section.

**Benefit 2 — Separate release cadences.** The contract layer changes faster
than the host stack. After the split, the contract could release weekly while
the host releases monthly. This is a real benefit but premature — at
v0.4.5-alpha, the release cadence is not yet predictable enough to justify the
coordination overhead.

**Benefit 3 — License differentiation.** The operator's strategic plan
proposes Apache-2.0 for the contract and AGPL-3.0 (or commercial) for the
host. This is possible without a repo split by using a `walter-host/LICENSE`
file that overrides the repo-level license for the `setup/walter-host/`
subtree. This is unconventional but legally sound. A repo split is the cleaner
approach for license differentiation but not strictly required.

### What to do instead of splitting

1. Restructure the README to lead with the contract layer. The host stack
   moves to a secondary section. First 500 lines of README should be
   navigable without knowing what Docker is.

2. Add a section "Walter-OS without walter-host" to the documentation that
   explicitly covers: using the Council with hosted Plane SaaS + hosted
   LiteLLM proxy instead of the VM stack, so the "Council requires
   walter-host" coupling is documented as a design choice with a bypass.

3. Add a `WALTER-HOST-README.md` in `setup/walter-host/` that serves as the
   entry point for host-stack adopters, making it possible to link directly
   to the host stack documentation without wading through the full README.

4. Revisit the split after v1.0 when: (a) the release cadence is established,
   (b) the license strategy is finalized, and (c) there are enough contributors
   that cross-repo coordination is an actual workload reduction rather than
   additional overhead.

## Acceptance Criteria

- [AC-1] This spec and ADR-0020 record the decision to maintain the monorepo
  with the rationale above, so future contributors understand why the split
  was considered and rejected.
- [AC-2] `README.md` is restructured so that the host stack section (`setup/
  walter-host/`) begins no earlier than line 500 of the file. The first 500
  lines introduce the contract layer, the tier install system, and the
  Lite entry tier.
- [AC-3] A new doc `docs/operational/council-without-walter-host.md` exists,
  covering how to use the Walter Council with hosted Plane (cloud.plane.so)
  and a hosted LiteLLM instance (self-hosted or API proxy) instead of the VM
  stack.
- [AC-4] `setup/walter-host/README.md` exists as the primary documentation
  entry point for the host stack, containing the architecture diagram, RAM
  budget table, and deployment prerequisites.

## Non-goals

- Implementing the split. This spec explicitly rejects it.
- Changing the license for the host stack subtree. That is ADR-0018 scope.
- Moving files between directories. The directory structure is not changing.

## Open questions

- Q1: Should the "revisit after v1.0" trigger be explicit (e.g., "re-evaluate
  at v1.0 stable release") or left implicit? Recommendation: explicit trigger
  in ADR-0020.

## References

- `docs/decisions/0020-repo-split-walter-contract-walter-host.md` — the ADR
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-9
- README.md — file to restructure
