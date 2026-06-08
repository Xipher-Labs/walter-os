# Review Loop as a Reusable GitHub Action

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-06

## Problem

Walter-OS documents a 3-round review loop (Copilot → Codex → collaborative)
in the global `AGENTS.md` (lines 187-264). This loop is one of the most
concretely useful and marketable patterns in the framework. It is currently
expressed as:
1. Prose instructions in AGENTS.md that an agent reads and follows.
2. Specific shell commands embedded in the prose (the `gh api` call for
   Copilot, the `CODEX_HOME` bypass pattern for Codex).

The loop as written is effective but requires the operator to trust that the
agent will follow prose instructions correctly. There is no automated,
reusable artifact that other projects can adopt without adopting Walter-OS
itself. The operator's strategic plan identifies extracting this loop as a
GitHub Action as "a marketing and adoption win."

This spec defines what the extracted action would look like.

## Proposed solution

Create a GitHub Action at `.github/actions/walter-review-loop/` that
implements the 3-round review loop as a composable workflow step. The action
takes a PR number and base branch as inputs, runs the Copilot and Codex review
rounds where available, and emits v1 status metadata for downstream workflows.
Structured finding parsing is deferred: `findings-json` is a placeholder in
the v1 action and remains `[]` until Copilot/Codex output parsing lands.

The action can then be referenced from `.github/workflows/pr-review.yml` in
this repo (eating our own cooking) and documented as a standalone reusable
action that other projects can call from their own workflows.

**Realistic scope note:** Copilot review invocation via the REST API is
currently walter-os-specific behavior. The Codex review step requires the
`codex` CLI. A GitHub Action cannot guarantee these tools are available in
every environment. The action must handle graceful degradation when Copilot
is unavailable (PR too large, capacity error) and when the Codex CLI is not
installed. In the degraded case, the action runs only the available rounds and
documents which rounds ran.

## Acceptance Criteria

- [AC-1] `.github/actions/walter-review-loop/action.yml` exists with these
  inputs:
  - `pr-number` (required): The PR number to review.
  - `base-branch` (optional, default: `main`): The base branch for the diff.
  - `severity-gate-config` (optional): V1 placeholder for future severity-gate
    parsing. The v1 action does not read this input.
  - `run-codex` (optional, default: `true`): Whether to run the Codex round.
  - `run-copilot` (optional, default: `true`): Whether to request Copilot review.
- [AC-2] The action's outputs include:
  - `findings-json`: V1 placeholder, currently always `[]`.
  - `rounds-completed`: A JSON array listing which rounds ran (`copilot-round-1`,
    `codex-round-2`, `collaborative-round-3`).
  - `status`: V1 coarse verdict. `escalate` means no rounds ran; `findings`
    means at least one automated round ran. Severity-based `clean` /
    `findings` / `escalate` is deferred until structured findings parsing
    lands.
- [AC-3] The action handles Copilot unavailability gracefully: if the direct
  REST call to request Copilot review fails (any HTTP 4xx/5xx), it emits a
  GitHub Actions warning and skips to Round 2. The action does not fail.
- [AC-4] The action handles Codex CLI unavailability gracefully: if
  `command -v codex` returns non-zero, it logs at WARN level and skips Round 2.
- [AC-5] `.github/workflows/pr-review.yml` in this repo uses the action:
  it calls `.github/actions/walter-review-loop` on every PR against `main` and
  writes the rounds/status outputs to the workflow step summary. PR comments
  and hard failure on `status == "escalate"` are deferred until structured
  findings parsing is implemented.
- [AC-6] A test at `tests/github-actions/review-loop.bats` (or equivalent)
  validates the action's structure and v1 shell-contract invariants without
  requiring actual GitHub API calls. End-to-end mocked execution of the
  composite action shell steps is deferred.
- [AC-7] The action's README (`README.md` inside the action directory) is
  usable as a standalone document — it does not require knowledge of Walter-OS
  to understand the action's purpose and usage.

## Non-goals

- Publishing the action to the GitHub Marketplace. That is operator-territory.
- Implementing the Codex CLI. It is an external tool.
- Implementing a fourth review round or extending the protocol.
- Running the review loop for non-GitHub repositories.

## Open questions

- Q1: Should the action use `composite` type (shell steps) or `docker`
  container action type? Recommendation: `composite` — no Docker dependency,
  faster startup, easier to fork and modify.
- Q2: Should the Codex bypass pattern (`CODEX_HOME=/tmp/codex-minimal`) be
  built into the action, or left to the caller to configure? Recommendation:
  built-in as the default when `~/.codex/config.toml` has parse errors,
  with a documented bypass env var.

## References

- `AGENTS.md` lines 187-264 — the current prose description of the review loop
- `docs/specs/pr-review-severity-gate.md` — severity gate framework
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-6
