# Plane PR Sync

## Problem

Walter-OS can create Plane work and open PRs, but the link between a Plane issue
and a Forgejo PR is still manual. Small teams need a deterministic primitive that
webhooks, n8n, or cron can call to keep Plane and PR state aligned.

## Goals

- Add `scripts/agents/plane-pr-sync.sh` as an idempotent sync primitive.
- Add `scripts/agents/plane-pr-sync-trigger.sh` as a small event adapter that
  n8n, webhooks, or cron can call without rebuilding argv in workflow JSON.
- Add `scripts/agents/plane-pr-sync-webhook.sh` as a signed Forgejo/Gitea
  `pull_request` webhook adapter for public webhook entrypoints.
- Support `link` and `merged` events.
- Post a Plane comment with a stable marker and move the issue to `review` or
  `done`.
- Add a Forgejo PR comment through `tea`, including the stable
  `walter-plane-issue:<id>` marker required by future webhook redeliveries.
- Never merge, push, approve, or mutate git history.

## Non-goals

- Do not add a full n8n workflow JSON yet.
- Do not parse arbitrary PR bodies.
- Do not expose a public webhook listener in this PR. The signed adapter is a
  CLI bridge for n8n or another HTTP entrypoint; it does not listen on a port.
- Do not update `.walter/` feature ledgers until #227 lands.

## Acceptance Criteria

- AC1: `link` persists or finds the matching `walter-plane-issue:<id>` marker
  in Forgejo PR comments before it comments on Plane or moves the issue to
  `review`.
- AC2: `merged` comments on Plane with the merge SHA, moves the issue to `done`,
  and comments on the Forgejo PR.
- AC3: Missing Plane environment fails before any state change.
- AC4: Unknown events fail closed.
- AC5: Inputs containing newlines are rejected.
- AC6: The script never calls merge or push commands.
- AC7: `plane-pr-sync-trigger.sh` maps Forgejo/Gitea `pull_request` payloads to
  the sync primitive, treats closed-unmerged PRs as no-op, rejects unsupported
  events/actions, and rejects newline-bearing payload fields.
- AC8: `plane-pr-sync-webhook.sh` verifies the Forgejo/Gitea HMAC-SHA256
  signature against the original raw request body before JSON parsing, comment
  fetches, or Plane/Forgejo mutation.
- AC9: A valid signed `pull_request` `closed` event with `merged == true`
  resolves exactly one distinct `walter-plane-issue:<id>` marker from PR comment
  bodies and moves the linked Plane issue to `done`.
- AC10: Missing or invalid HMAC signatures fail before any Plane or Forgejo
  mutation.
- AC11: Closed-unmerged PR events are a no-op before marker lookup.
- AC12: Missing markers or multiple distinct Plane issue markers fail closed.
- AC13: Payload fields containing control characters are rejected before sync.
- AC14: The signed adapter calls `plane-pr-sync.sh` via argv arrays and never
  calls merge, push, or approval commands.
- AC15: Signed webhooks require `WALTER_FORGEJO_WEBHOOK_REPOS`; events from
  repos outside the allowlist fail closed.
- AC16: Signed webhooks require `WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS`; Plane
  issue markers from comments by other authors are ignored.

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
or another operator-controlled source.

## Signed Webhook Adapter

`plane-pr-sync-webhook.sh` handles the public Forgejo/Gitea merge-webhook path.
It is still a CLI adapter, not an HTTP server. n8n or another webhook entrypoint
must pass the event header, signature header, and original raw request body:

```bash
scripts/agents/plane-pr-sync-webhook.sh \
  --event "$FORGEJO_EVENT" \
  --signature "$FORGEJO_SIGNATURE" \
  --payload-file "$RAW_FORGEJO_PAYLOAD"
```

The adapter verifies `X-Gitea-Signature` / `X-Forgejo-Signature` as an
HMAC-SHA256 over the raw payload bytes before it parses JSON, fetches PR
comments, or calls the Plane sync primitive. The webhook secret is read from
`WALTER_FORGEJO_WEBHOOK_SECRET` by default; use `--secret-env` only to point at
another environment variable name. Do not pass the secret on argv.

Set `WALTER_FORGEJO_WEBHOOK_REPOS` to a comma-separated allowlist of
`owner/repo` names accepted by this webhook secret. The adapter fails closed
when the allowlist is missing or the payload repo is not listed. This prevents an
org-level webhook or reused secret from moving Plane issues from an unexpected
repository.

Set `WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS` to a comma-separated allowlist of
Forgejo/Gitea logins allowed to bind Plane issue markers. This should be the
automation account used by `plane-pr-sync.sh link`, not a human contributor
account. Markers written by other authors are ignored.

After signature verification, only `pull_request.action == "closed"` with
`pull_request.merged == true` is actionable. Closed-unmerged events are no-op.
For merged events, the adapter fetches PR comments with `tea issues view` and
requires exactly one distinct `walter-plane-issue:<id>` marker from comment
bodies by trusted authors. Repeated copies of the same marker are accepted for
webhook redelivery, but multiple distinct markers fail closed. PR title/body
text and comments by untrusted authors are not marker sources and cannot spoof
the issue binding.

For test fixtures or an n8n workflow that already fetched comments safely, pass
`--comments-file "$COMMENTS_JSON"` to avoid a live `tea` call. The production
path should prefer `tea` so the marker source is Forgejo state written by the
trusted `link` flow.

`plane-pr-sync.sh link` treats the Forgejo marker as required state. If `tea` is
missing, comments cannot be inspected, or the marker comment cannot be written,
the command fails before moving Plane to `review`. Existing comments are only
idempotent when they contain the matching `walter-plane-issue:<id>` marker;
sync markers without the Plane issue binding do not satisfy the trust boundary.
When `WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS` contains a non-empty
comma-separated list, existing comments from authors outside that allowlist do
not satisfy marker persistence; the link flow will write its own
automation-authored marker instead.

## Related

- Issue: #237
- Issue: #302
- Issue: #305
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-12
