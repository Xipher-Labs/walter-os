# Plane PR Sync

## Problem

Walter-OS can create Plane work and open PRs, but the link between a Plane issue
and a Forgejo PR is still manual. Small teams need a deterministic primitive that
webhooks, n8n, or cron can call to keep Plane and PR state aligned.

## Goals

- Add `scripts/agents/plane-pr-sync.sh` as an idempotent sync primitive.
- Add `scripts/agents/plane-pr-sync-trigger.sh` as a small event adapter that
  n8n, webhooks, or cron can call without rebuilding argv in workflow JSON.
- Support `link` and `merged` events.
- Post a Plane comment with a stable marker and move the issue to `review` or
  `done`.
- Add a Forgejo PR comment through `tea` when available, including the stable
  `walter-plane-issue:<id>` marker for future webhook redeliveries.
- Never merge, push, approve, or mutate git history.

## Non-goals

- Do not add a full n8n workflow JSON yet.
- Do not parse arbitrary PR bodies.
- Do not expose a public webhook listener in this PR. Public webhooks must verify
  the Forgejo/Gitea HMAC signature before invoking this script.
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
- AC7: `plane-pr-sync-trigger.sh` maps Forgejo/Gitea `pull_request` payloads to
  the sync primitive, treats closed-unmerged PRs as no-op, rejects unsupported
  events/actions, and rejects newline-bearing payload fields.

## Trigger Wrapper

`plane-pr-sync-trigger.sh` is intentionally a CLI adapter, not a public HTTP
listener. It expects the caller to supply the trusted Plane issue ID and the
Forgejo/Gitea event type:

```bash
scripts/agents/plane-pr-sync-trigger.sh \
  --event pull_request \
  --issue "$PLANE_ISSUE_ID" \
  --payload-file "$FORGEJO_PAYLOAD_JSON"
```

Supported `pull_request.action` mappings:

| Action | Sync event |
|---|---|
| `opened`, `reopened`, `synchronized` | `link` |
| `closed` with `pull_request.merged == true` | `merged` |
| `closed` with `pull_request.merged != true` | no-op |

The wrapper never parses arbitrary PR bodies to discover the Plane issue. n8n or
cron must pass the Plane issue from trusted workflow state, a prior Plane event,
or another operator-controlled source. For future public Forgejo webhooks, first
verify the webhook HMAC, then resolve the Plane issue from the
`walter-plane-issue:<id>` marker written by the `link` comment.

## Related

- Issue: #237
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-12
