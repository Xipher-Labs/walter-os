# Spec: walter-founder-skills

**Slug**: `walter-founder-skills`
**Status**: Approved
**Target release**: v0.2.0
**Created**: 2026-05-12

## Problem

The v0.2.0 maturity audit revealed six gaps in the founder toolkit:

| Domain | Current maturity | Gap |
|---|---|---|
| Customer discovery | 2/5 | No structured interview guide or synthesis output |
| Sales / pricing | 1/5 | No pricing framework, no outreach tooling |
| Sales / outreach | 1/5 | No cold outreach sequence drafting |
| Content writing | 2/5 | No brand-voice-aware content generation |
| Personal effectiveness | 3/5 | No structured weekly review loop |
| Competitive intel | n/a | No competitor change tracking |

Each gap corresponds to a skill that should exist in `skills/` and
auto-trigger when the operator mentions relevant keywords.

## Decisions

- **State location**: operator-private state goes in `~/.config/walter-os/state/`
  (out-of-repo). Weekly review files and competitor snapshots are never committed.
- **OKR format**: free text for v0.2.0. No structured schema — the skill
  prompts the operator to provide KR text; synthesis is done via LLM.
- **Composition target**: each skill must reference at least one other
  existing Walter-OS skill in its "How it composes" section.
- **Depersonalization**: no skill file may contain operator-identifying
  patterns (`example work org`, `example medical app`, `example civic app`, `operator-handle`, `operator.email`, `operator@`).

## Acceptance Criteria

- [AC-1] `skills/customer-interview-synthesizer/SKILL.md` exists with valid YAML frontmatter.
- [AC-2] `skills/pricing-experiment/SKILL.md` exists with valid YAML frontmatter.
- [AC-3] `skills/cold-outreach-sequencer/SKILL.md` exists with valid YAML frontmatter.
- [AC-4] `skills/content-writer/SKILL.md` exists with valid YAML frontmatter.
- [AC-5] `skills/weekly-review-coach/SKILL.md` exists with valid YAML frontmatter.
- [AC-6] `skills/competitor-radar/SKILL.md` exists with valid YAML frontmatter.
- [AC-7] Each SKILL.md has sections: "When to use", "When NOT to use", "Outputs", "Example".
- [AC-8] `tests/oss/founder-skills.bats` contains 31 tests and all pass.
- [AC-9] No SKILL.md contains operator-personal identifiers.
- [AC-10] Each skill description field is under 500 characters and includes auto-trigger keywords.
- [AC-11] `skills/INDEX.md` lists all skills grouped by category.

## Non-goals

- Real-time monitoring (competitor-radar is batch, weekly).
- Multi-participant retrospectives (weekly-review-coach is solo).
- Generating or scheduling social media posts (content-writer is draft only).
- Enterprise SPIN/Challenger sales methodology (post-PMF scope).
- Structured OKR schema validation (deferred to v0.3.0).
