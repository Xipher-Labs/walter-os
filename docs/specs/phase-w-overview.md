# Phase W — Walter Open Source Preparation

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Branch**: `v0.2.0-walter-oss`

## Problem

Walter-OS v0.1.0 is a functional, hardened, single-operator toolkit. Council v2
(Phases F–V) has shipped, giving the system full observability, memory brokering,
resilience, trust controls, a browser UI, and DevRel analytics. The repo is public,
but the README's own warning says it clearly: this is not forkable. Paths, domains,
Argentine legal references, example work org stack details, and example civic app/example medical app project
context are baked into the core files. Any third party who clones the repo gets a
working example of one operator's setup and nothing they can actually run.

The gap between "interesting patterns to read" and "framework I can adopt" is
entirely caused by personalization leakage into the OSS core: hardcoded domains,
context files that list specific projects by name, skills scoped to a single country's
regulatory regime, and an install.sh that assumes a specific machine layout. Until
those are extracted, Walter-OS cannot grow a community, cannot accept contributions
from others running different stacks, and cannot be cited as a reusable framework.

Phase W closes that gap for v0.2.0. The goal is not to build a SaaS or multi-tenant
product — Walter-OS remains a single-operator framework. The goal is to make the
single-operator experience adoptable by anyone, not just the operator.

## Proposed solution

Phase W is seven parallel work items that together produce a clean, adoptable
v0.2.0 release. The items split into three themes:

**Infrastructure (run anywhere):** W-1 replaces the per-service `deploy.sh`
patchwork with a single all-in-one Docker Compose that any operator can bring up
with five env vars. W-6 rewrites install.sh as an interactive wizard that guides
a new operator through the full bootstrap sequence. W-7 adds versioning and a
release process so adopters can track upstream changes.

**Personalization extraction (W-5):** The critical-path item. All hardcoded domain
references, country-specific context, and project-specific names move out of the
OSS core and into a personal overlay pattern. The repo ships example context
templates; operators maintain their own overlay outside the repo.

**Feature expansion (W-2, W-3, W-4):** W-2 wires the existing LiteLLM integration
into new natural-language CLI commands. W-3 delivers a `project-pivot` skill that
replaces what were going to be fixed industry templates with a runtime-derived
configuration for any domain. W-4 delivers a provider-choice wizard so operators
can swap out any of the seven core service categories without touching YAML by hand.

## Work items

| Item | Slug | Theme | Effort |
|---|---|---|---|
| W-1 | `phase-w-1-docker-compose` | Infrastructure | L |
| W-2 | `phase-w-2-cli-ai` | Feature | M |
| W-3 | `phase-w-3-pivot-skill` | Feature | M |
| W-4 | `phase-w-4-provider-choice` | Feature | M |
| W-5 | `phase-w-5-depersonalization` | Critical path | L |
| W-6 | `phase-w-6-install-wizard` | Infrastructure | M |
| W-7 | `phase-w-7-versioning-release` | Infrastructure | S |

Effort: S = 1–2 days, M = 3–5 days, L = 5–8 days.

## Acceptance Criteria (phase-level)

- [W-AC-1] A new operator can clone the repo, run `./install.sh`, answer the
  wizard prompts, and have a working Walter-OS installation with no personal
  references to the operator/example work org/xipherlabs in any config file.
- [W-AC-2] `docker compose up -d` in the repo root (or a nominated compose dir)
  brings up all core services and they pass health checks.
- [W-AC-3] `grep -r "maintainer-domain\|project-a\|project-b" --include="*.md"
  --include="*.sh" --include="*.yml" --include="*.yaml"` on OSS-targeted files
  returns zero matches (excluding `docs/specs/` historical records and
  `contexts/_examples/` which are explicitly labeled personal examples).
- [W-AC-4] `VERSION` file at repo root matches the git tag on the v0.2.0 release.
- [W-AC-5] `walter providers configure` can reconfigure any of the seven provider
  categories without manual YAML edits.
- [W-AC-6] `project-pivot` skill produces a valid AGENTS.md draft for at least
  four representative domain/compliance combinations without any country-specific
  hardcoding.

## Non-goals

- Multi-tenant: single operator only. v0.3.0 if ever.
- Public documentation site: defer to v0.3.0.
- Removing Argentine-specific capabilities entirely: the regulatory skill stays,
  parameterized for any jurisdiction. Country-specific examples move to the
  operator overlay, not deleted.
- Auto-migration of existing operator configs: install wizard handles new installs;
  existing operators upgrade manually per the migration guide produced by W-6.

## Sequencing dependencies

```
W-5 (depersonalization) must complete before W-6 (install wizard)
  because W-6 install.sh references the new overlay paths.

W-1 (docker compose) must complete before W-6 (install wizard)
  because W-6 step 2 orchestrates docker compose up.

W-7 (versioning) can run in parallel with everything.
W-2, W-3, W-4 can run in parallel with each other and with W-5/W-6.
W-5 should start first — it has the widest blast radius in the repo.
```

## Open questions

- Should the all-in-one compose be at `compose.yml` (repo root) or
  `setup/vm/compose.all.yml`? Root is more discoverable for new adopters.
  Repo root chosen in spec; reviewer can flag if it conflicts with anything.
- Postiz + Metabase marked opt-in. Should they be separate compose profiles
  (Docker Compose `--profile devrel`) or separate files? Profiles chosen —
  avoids file proliferation.

## References

- `docs/specs/walter-council-v2.md` — Council v2 (prerequisite, now shipped)
- `docs/decisions/0010-oss-license.md` — license choice
- `docs/decisions/0011-depersonalization-strategy.md` — overlay strategy
- Individual W-N specs in `docs/specs/phase-w-N-*.md`
