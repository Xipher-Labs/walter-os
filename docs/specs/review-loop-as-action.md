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
rounds (where available), collects findings, and outputs structured JSON.

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
  - `base-branch` (required): The base branch for the diff.
  - `severity-gate-config` (optional): Path to a severity gate config file
    (references `docs/specs/pr-review-severity-gate.md`).
  - `run-codex` (optional, default: `true`): Whether to run the Codex round.
  - `run-copilot` (optional, default: `true`): Whether to request Copilot review.
- [AC-2] The action's outputs include:
  - `findings-json`: A JSON array of `{round, tool, finding, severity}` objects.
  - `rounds-completed`: A JSON array listing which rounds ran (`copilot-round-1`,
    `codex-round-2`, `collaborative-round-3`).
  - `status`: One of `clean`, `findings`, `escalate`.
- [AC-3] The action handles Copilot unavailability gracefully: if the
  `gh api` call to request Copilot review fails (any HTTP 4xx/5xx), it logs
  the failure at INFO level and skips to Round 2. The action does not fail.
- [AC-4] The action handles Codex CLI unavailability gracefully: if
  `command -v codex` returns non-zero, it logs at WARN level and skips Round 2.
- [AC-5] `.github/workflows/pr-review.yml` in this repo uses the action:
  it calls `.github/actions/walter-review-loop` on every PR against `main`,
  posts the `findings-json` as a PR comment, and fails the workflow if
  `status == "escalate"`.
- [AC-6] A test at `tests/github-actions/review-loop.bats` (or equivalent)
  validates the action's shell scripts without requiring actual GitHub API
  calls (mock the `gh api` response).
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
