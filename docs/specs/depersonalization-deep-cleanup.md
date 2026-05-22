# Depersonalization Deep Cleanup — Global AGENTS.md

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-02

## Problem

Walter-OS's global `AGENTS.md` is the single file read by every agent across
every tool (Claude Code, Codex CLI, Cursor) in every adopter's environment.
It must be a neutral framework contract, not one operator's personalized
setup. Through v0.3.0 the depersonalization work focused on structural
isolation (the overlay system, context templates, examples directory). It did
not complete the pass on the body of `AGENTS.md` itself.

Three categories of operator-personal content remain in the global contract:

**Category A — Hardcoded toolchain preferences.** The `## Tooling
preferences` section (lines 474-479) specifies: macOS Apple Silicon, zsh,
pnpm for Node, uv for Python, cargo for Rust, Cursor as primary editor,
OrbStack on Mac. These are presented as defaults that agents should follow —
which means any Claude Code session on a Linux machine, or any operator who
uses Yarn or Docker Desktop, gets incorrect guidance from the global contract.

**Category B — Domain-specific technology references in the global testing
strategy.** The testing strategy table (lines 373-383) uses three column
headers — "Rust / systems", "Next.js + Supabase", and "React Native + Solana"
— as if these are the universal project archetypes. It includes Solana
program testing rows (`anchor test`, `solana-test-validator`) as first-class
entries. The auto-escalation list (line 90) references "Solana TX, Stripe"
specifically. Solana and Stripe are one operator's domains; they should live
in a domain-specific skill or overlay example, not the global contract.

**Category C — Skills description in the Plugins section.** Line 72 lists
"Solana infrastructure" among the domains that Walter-OS native skills cover.
This is accurate (the skills exist) but implies Solana is a first-class
concern of the framework rather than one operator's optional skill set.

The existing `tests/oss/depersonalization.bats` test suite covers some tokens
but does not yet test for the specific patterns identified here.

## Proposed solution

Move all operator-personal content out of `AGENTS.md` and into the correct
tier: either an overlay example file (for toolchain preferences) or a
domain-specific skill description (for Solana/Stripe references). Strengthen
the depersonalization test suite to prevent regressions. The testing strategy
table in AGENTS.md should become a generic framework — "project archetype
examples" — with a callout that the actual columns are operator-defined in the
overlay. One concrete generic example column (e.g., "TypeScript web app") may
stay to illustrate the table format.

## Acceptance Criteria

- [AC-1] The `## Tooling preferences` section of `AGENTS.md` contains no
  references to macOS, Apple Silicon, zsh, pnpm, uv, OrbStack, or Cursor as
  prescribed defaults. Instead, it contains a short callout directing the
  operator to their overlay (`~/.config/walter-os/overlay/personal.env`) with
  a link to the example file.
- [AC-2] The testing strategy table in `AGENTS.md` no longer uses Solana,
  React Native, Anchor, or Supabase as column headers or row entries. The
  table either (a) provides one generic example column and instructs operators
  to add their stack in the overlay, or (b) is moved entirely out of AGENTS.md
  and into an overlay example file.
- [AC-3] The auto-escalation list in `AGENTS.md` no longer mentions specific
  technology names ("Solana TX", "Stripe"). It uses technology-neutral
  language: "any change in `auth/`, `crypto/`, or code that moves money".
- [AC-4] The skills plugin description no longer names "Solana infrastructure"
  as a listed domain in the global AGENTS.md. Domain-specific skill catalogs
  live in context or overlay files.
- [AC-5] An example overlay file `contexts/_examples/operator-preferences.example.md`
  exists and shows how an operator would specify their toolchain: OS, shell,
  package managers, editor, container runtime. The macOS/pnpm/OrbStack example
  values moved there from AGENTS.md.
- [AC-6] `tests/oss/depersonalization.bats` has at least four new test cases:
  (a) no "Solana" in global AGENTS.md, (b) no "OrbStack" in global AGENTS.md,
  (c) no "Apple Silicon" in global AGENTS.md, (d) no "pnpm" in global AGENTS.md
  as a prescription. Tests must run in CI.
- [AC-7] A new adopter who clones the repo, runs `install.sh`, and inspects
  `~/.claude/AGENTS.md` sees no technology-specific defaults except those
  described as "examples to override in your overlay".

## Non-goals

- Removing Solana skills from `skills/`. They are legitimate skills for
  operators who need them; they just should not be referenced in the global
  contract as universal defaults.
- Changing the overlay mechanism or install flow.
- Modifying context-level AGENTS.md files (work, personal, projects-personal).
  Those are templates that operators are expected to fill in; their placeholder
  status is intentional.
- Touching `skills/regulatory-research-argentina/SKILL.md` — it is a
  domain-specific skill, correctly placed; just not referenced from the global
  contract.

## Open questions

- Q1: Should the testing strategy table move entirely out of global AGENTS.md
  (operator defines it in overlay) or stay as a reduced generic table (one
  illustrative column)? Recommendation: move entirely, replace with one-line
  callout pointing to `contexts/_examples/testing-strategy.example.md`.
  Operator decides.
- Q2: Should `skills/solana-rpc-review/` and `skills/solana-program-review/`
  get a note in their SKILL.md that they are domain-specific and not loaded
  by default? Yes, this is good practice regardless of this spec.

## References

- `docs/decisions/0011-depersonalization-strategy.md` — overlay ADR
- `docs/specs/phase-w-5-depersonalization.md` — prior pass
- `tests/oss/depersonalization.bats` — existing test suite
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-1
