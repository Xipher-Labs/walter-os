# Walter-OS Lite — Zero-Friction Entry Tier

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-03

## Problem

Walter-OS has a four-tier install system (Tier I through IV). The system is
well-designed, but it has an adoption friction problem: the first thing a new
visitor encounters in the README is a description of the full stack (25+
services, Docker, VM provisioning) before they understand what the framework
actually does for them day-to-day. Tier I (the $0, 5-minute path that
delivers real value with no VM, no Docker) is described in the README but not
elevated as the primary entry point. A visitor who scans the README can
reasonably conclude "this requires a Hetzner VM to be useful" and leave.

A secondary problem: Tier I still requires `git clone`, `install.sh`, `yq`,
`jq`, `gh`, and a personal overlay scaffold. That is the right experience
for a committed adopter, but it is too many steps for an evaluator who just
wants to see whether the agent-discipline model works for them.

The market-entry strategy calls for reducing evaluation friction from 4 hours
to 4 minutes. That requires an additional sub-tier below Tier I: a single
copy-paste block that drops into a Claude Code or Codex CLI session with no
installation at all.

## Proposed solution

Create "Walter-OS Lite" — a single Markdown file that, when pasted into a
Claude Code or Codex CLI conversation, installs the minimum Walter-OS contract
disciplines in the current session. It is not a permanent install; it is a
structured prompt that teaches the agent the core disciplines for that session.
A companion file can optionally write a minimal `.claude/AGENTS.md` to the
current repo for persistence.

Lite is NOT a replacement for Tier I. It is a zero-friction evaluation door
that leads to Tier I. The README redesign makes Lite the hero entry point at
the top, with the Tier table immediately below it.

## Acceptance Criteria

- [AC-1] A file `setup/agent-install/lite.md` exists. Its fenced block, when
  pasted into Claude Code or Codex CLI, installs these minimum disciplines in
  the current session without any prerequisite tools:
  - Rigor classification (tiny/small/major) before starting work
  - Conventional commit format (feat/fix/chore/docs/refactor)
  - Branch flow (feature/<slug> → main, no direct push to main)
  - TDD gate (RED → GREEN → REFACTOR before calling any task done)
  - Single-round review (self-review checklist) before calling PR ready
- [AC-2] The fenced block fits in a single Claude Code context paste (target:
  under 500 tokens). It is self-contained — no external URLs, no file reads,
  no shell commands required.
- [AC-3] The `lite.md` file includes a clear upgrade path: at the bottom of
  the pasted block, the agent mentions that Tier I installs these disciplines
  permanently via `install.sh` and points to `setup/agent-install/tier-1.md`.
- [AC-4] A companion file `setup/agent-install/lite-persist.md` exists. Its
  fenced block, when pasted after `lite.md`, writes a minimal
  `.walter-os-lite/AGENTS.md` into the current repo directory. This file is
  gitignore-able (added to `.gitignore` by the block) and makes the Lite
  disciplines persist across Claude Code sessions in that directory without a
  full Tier I install.
- [AC-5] The README's install section is restructured so that the Lite entry
  appears first, in a prominent callout block, before the Tier I-IV table.
  The Lite section has a single-line pitch: "Start here. No install. 30 seconds."
- [AC-6] `walter-os doctor --lite` (new subcommand or extension of existing
  doctor) confirms whether the current directory has a Lite AGENTS.md
  installed. Returns PASS with the disciplines list, or NONE with the
  installation callout.
- [AC-7] A bats test `tests/oss/lite-format.bats` verifies that `lite.md`
  (a) contains a single fenced block, (b) the block is under 600 lines,
  (c) the block contains no shell commands that require external tools.

## Non-goals

- Lite is not a permanent configuration. It does not modify `~/.claude/`.
- Lite does not install skills, MCPs, slash commands, or the Walter Council.
  Those are Tier II and above.
- Lite does not require a personal overlay. The disciplines it installs are
  generic enough to work without one.
- Lite does not replace or compete with the Tier I-IV table. It is additive.
- The README restructuring covers the Quick Start and Install sections only.
  Other README sections are out of scope.

## Open questions

- Q1: Should `lite.md` produce a file in the current repo, or operate
  entirely in-session (no file writes)? Recommendation: default to in-session
  only; `lite-persist.md` handles the optional persistence case. Operator
  decides.
- Q2: Should the Lite AGENTS.md be gitignored by default or committed?
  Recommendation: gitignored by default (Lite is for personal evaluation, not
  team-wide enforcement — that is Tier II). Operator decides.

## References

- `setup/agent-install/tier-1.md` — Tier I for comparison
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-2
- `README.md` "Install via agent" section — the section to restructure
