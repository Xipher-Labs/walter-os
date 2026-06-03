# Post-Merge Feedback Loop

## Problem

Walter-OS can score PR readiness before merge, but it does not yet have a
structured post-merge loop. After a PR lands, the operator still has to manually
inspect CI, deployment workflows, telemetry alerts, and repeat-failure state
before deciding whether to wait, investigate, open a fix PR, or recommend a
rollback.

## Goals

- Add `walter-os post-merge-check` as the first read-only AD-13 primitive.
- Classify post-merge evidence into `healthy`, `investigate`,
  `rollback-recommended`, or `human-escalation`.
- Consume observable evidence: GitHub Actions runs for a merge commit, optional
  telemetry alerts, and fix-attempt counters.
- Enforce a max-fix-attempts cap before future automation can loop.
- Return JSON output for later n8n, Plane, or feature-ledger integration.

## Non-Goals

- Do not open fix PRs in this slice.
- Do not revert commits or run rollback commands.
- Do not update `.walter/features/**` ledgers until #227 lands.
- Do not bypass the approval-gate hard-limit floor.

## Decisions

### D1 — Read-only first slice

The initial primitive only classifies evidence. It exits with deterministic
codes that automation can use later:

| Decision | Exit | Meaning |
|---|---:|---|
| `healthy` | 0 | No action needed. |
| `investigate` | 1 | Wait or inspect; a future fix PR may be appropriate. |
| `rollback-recommended` | 2 | High-impact signal; operator should consider rollback. |
| `human-escalation` | 3 | Fix-attempt cap reached; stop automated looping. |

Non-decision errors use codes outside that range. Runtime or dependency
failures, such as missing `jq`/`gh` or GitHub API failures, exit `4`; malformed
CLI usage exits `64`. Automation must treat those as tooling failures, not as
post-merge health decisions.

### D2 — Conservative rollback recommendations

The CLI recommends rollback only for high-impact failed workflows
(`deploy`, `release`, `migration`, `production`) or high/critical telemetry
alerts. Ordinary CI failures return `investigate`; they do not trigger rollback
recommendations by themselves.

### D3 — Future automation composes around the CLI

Future PRs can use this primitive from n8n, Plane automation, or the eventual
feature-state ledger. That later layer may open fix PRs or update state, but
those mutating steps stay out of this slice.

## Acceptance Criteria

- AC1: All completed successful/skipped/neutral runs with no high/critical
  alerts return `healthy`.
- AC2: Failed non-deploy runs return `investigate`.
- AC3: High-impact failed runs or high/critical telemetry alerts return
  `rollback-recommended`.
- AC4: Failed evidence with `fix_attempts >= max_fix_attempts` returns
  `human-escalation`.
- AC5: `--json` emits `decision`, `next_action`, `counts`, and `findings`.
- AC6: `walter-os help` documents `post-merge-check`.

## Related

- Issue: #238
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-13
- Prior primitive: `docs/specs/pr-score.md` AD-11
