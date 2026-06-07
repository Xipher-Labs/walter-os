# Control Tower Team Readiness

## Problem

Control Tower already shows agent state, alerts, service health, spend, and
metrics, but it still assumes the operator remembers which safe CLI/docs path to
use for common operating modes. That is fine for a solo homelab operator. It is
not enough for a small startup or a team of up to roughly 10 people where a
second device, a teammate, or post-merge verification has to be handled
repeatably.

## Goals

- Add a dense, read-only Control Tower surface for operator/team readiness.
- Distinguish solo operator, second-device, and teammate onboarding paths.
- Surface safe diagnostic commands for service health, post-merge checks, and
  model/tool readiness.
- Link each path to existing docs instead of duplicating runbooks in the UI.
- Keep the panel scannable inside the current Control Tower layout.

## Non-Goals

- Do not redesign Control Tower again.
- Do not add mutating APIs, user provisioning, token creation, or access-rule
  changes.
- Do not install optional team apps.
- Do not depend on release-doctor output until that command has merged.
- Do not add mobile-specific layout guarantees in this slice.

## Decisions

### D1 — Read-only operating paths first

This slice introduces an `OperatorReadiness` dashboard panel backed by static
repo-owned data. It does not call shell commands or mutate services. Each row
points to commands the operator can run intentionally:

- `walter-os doctor`
- `walter-os onboard device --dry-run`
- `walter-os onboard teammate --dry-run`
- `walter-os post-merge-check --commit <sha>`
- `walter-os status --models`

### D2 — Three onboarding states

The panel separates:

| State | Meaning | Primary command |
|---|---|---|
| Solo operator | Existing one-person operating baseline | `walter-os doctor` |
| Second device | Same operator adding another machine | `walter-os onboard device --dry-run` |
| Teammate | Another person sharing the same Walter-VM | `walter-os onboard teammate --dry-run` |

This keeps the second-device flow from being confused with teammate
authorization work.

### D3 — Existing docs are the source of truth

Control Tower links to docs such as the onboarding planner, multi-device sync,
troubleshooting, model routing, and post-merge feedback loop. The UI is a
launcher and status-orientation surface, not another runbook copy.

### D4 — No release doctor dependency yet

`walter-os release doctor` is tracked separately by issue #307. This first
slice does not reference it so the Control Tower readiness PR can be reviewed
and merged independently of the release doctor PR.

## Acceptance Criteria

- AC1: Control Tower renders an operator readiness panel on the overview page.
- AC2: The panel distinguishes solo operator, second-device, and teammate
  readiness paths.
- AC3: The panel surfaces service-health, post-merge, and model/tool readiness
  checks using read-only commands already available on `main`.
- AC4: Every referenced doc path exists in the repository.
- AC5: Unit coverage verifies the readiness data contract and dashboard wiring.
- AC6: Lint and typecheck pass for the Control Tower package.

## Related

- Issue: #308
- Parent: #266
- Onboarding planner: `docs/operational/onboarding-planner.md`
- Post-merge primitive: `docs/specs/post-merge-feedback-loop.md`
