# PR Score

## Problem

Walter-OS PRs already collect checks, review rounds, title lint, issue links, and
risk signals, but the operator has to inspect those signals manually. That slows
down merge decisions and makes it harder for small teams to see whether a PR is
blocked, needs human review, or is a clean candidate for policy-driven merge.

## Goals

- Add `walter-os pr-score` as an operator-facing readiness score.
- Use observable PR evidence: checks, review state, title format, linked issue
  references, verification notes, sensitive file paths, and optional preview
  evidence.
- Return a clear decision: `block`, `human-review`, or `policy-auto-merge`.
- Support JSON output for future automation.

## Non-goals

- Do not merge PRs.
- Do not relax the hard-limit floor from `approval-gate.sh`.
- Do not deploy preview environments or mint preview credentials. PR Score only
  consumes existing `preview-plan.json` and `preview-report.json` evidence.

## Acceptance Criteria

- AC1: A clean low-risk fixture scores at least 90 and returns
  `policy-auto-merge`.
- AC2: Failing checks or an invalid title return `block`.
- AC3: Sensitive paths such as `.github/workflows/`, `hooks/`, `install.sh`,
  `AGENTS.md`, or `mcp/servers.json` force `human-review`.
- AC4: `--json` returns machine-readable `score`, `decision`, `components`,
  `preview`, and `findings`.
- AC5: `walter-os help` documents the new command.
- AC6: `--preview-report` awards preview evidence only when the report preserves
  the AD-10 safety invariants (`production_secrets: rejected`, credentials not
  minted, deploy not performed, hard-limit floor preserved).
- AC7: `--preview-plan` without a report is incomplete preview evidence and
  returns `human-review`; invalid explicit preview evidence returns `block`.

## Related

- Issue: #236
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-11
