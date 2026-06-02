# Plane PR Sync

## Problem

Walter-OS can create Plane work and open PRs, but the link between a Plane issue
and a Forgejo PR is still manual. Small teams need a deterministic primitive that
webhooks, n8n, or cron can call to keep Plane and PR state aligned.

## Goals

- Add `scripts/agents/plane-pr-sync.sh` as an idempotent sync primitive.
- Support `link` and `merged` events.
- Post a Plane comment with a stable marker and move the issue to `review` or
  `done`.
- Add a Forgejo PR comment through `tea` when available.
- Never merge, push, approve, or mutate git history.

## Non-goals

- Do not add a full n8n workflow JSON yet.
- Do not parse arbitrary PR bodies.
- Do not update `.walter/` feature ledgers until #227 lands.

## Acceptance Criteria

- AC1: `link` comments on Plane, moves the issue to `review`, and comments on
  the Forgejo PR.
- AC2: `merged` comments on Plane with the merge SHA, moves the issue to `done`,
  and comments on the Forgejo PR.
- AC3: Missing Plane environment fails before any state change.
- AC4: Unknown events fail closed.
- AC5: Inputs containing newlines are rejected.
- AC6: The script never calls merge or push commands.

## Related

- Issue: #237
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-12
