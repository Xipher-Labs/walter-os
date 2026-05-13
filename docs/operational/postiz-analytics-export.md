# Postiz Analytics Export — Integration Guide

> AC-18: Postiz analytics export endpoint enabled — schema documented
> Refs: docs/specs/devrel-analytics-stack.md

## Overview

Postiz exposes two paths for feeding analytics data into the
`analytics_events` Postgres table:

1. **Webhook on publish/engagement events** — recommended for real-time
2. **Direct Postiz API polling** — for scheduled ingestion via n8n

## Path 1: Webhook (recommended)

Postiz can POST a webhook payload to a configured URL on these events:
- `post.published` — when a scheduled post goes live
- `post.analytics` — engagement update (likes, shares, views, clicks)

### Setup

1. In Postiz UI: Settings → Webhooks → Add Webhook
2. URL: `https://n8n.${WALTER_DOMAIN}/webhook/postiz-analytics-ingest`
3. Events: `post.published`, `post.analytics`
4. Secret: generate + store in Infisical as `POSTIZ_WEBHOOK_SECRET`

Or via env var in compose.yml:
```yaml
POSTIZ_WEBHOOK_URL: https://n8n.${WALTER_DOMAIN}/webhook/postiz-analytics-ingest
```

### Webhook payload schema

```json
{
  "event": "post.analytics",
  "timestamp": "2026-05-11T12:00:00Z",
  "post": {
    "id": "postiz-post-uuid",
    "integration": "twitter",
    "externalId": "tweet-id-12345",
    "title": "Thread title or first 100 chars",
    "publishedAt": "2026-05-10T15:00:00Z",
    "url": "https://twitter.com/status/12345"
  },
  "analytics": {
    "impressions": 5000,
    "engagements": 280,
    "likes": 150,
    "reposts": 45,
    "replies": 22,
    "clicks": 180
  }
}
```

### n8n ingestion workflow

Create a Webhook trigger workflow in n8n:
1. Webhook node: POST at `/webhook/postiz-analytics-ingest`
2. Code node: map payload → `analytics_events` rows
3. Postgres node: upsert into `analytics_events`

Schema mapping:
```
post.integration → platform
post.externalId  → content_id (prefixed: `<platform>:<externalId>`)
analytics.impressions → event_type='impression', metric_value=N
analytics.engagements → event_type='engagement', metric_value=N
analytics.likes       → event_type='like', metric_value=N
```

## Path 2: Postiz REST API polling (n8n cron)

Postiz exposes a REST API for post analytics. Token from Settings → API Keys.

```
GET /api/analytics/posts?from=2026-05-01&to=2026-05-11
Authorization: Bearer <postiz-api-key>
```

Response: array of posts with `analytics` sub-object (same schema as webhook).

n8n workflow: Schedule Trigger (1h) → HTTP node → Code map → Postgres upsert.

## content_pieces sync

When Postiz publishes a post, create/update a `content_pieces` row:

```sql
INSERT INTO content_pieces (id, title, url, published_at, tags, hook, created_by)
VALUES (
  '<platform>:<external_id>',
  '<post title or first 100 chars>',
  '<post url>',
  '<published_at>',
  ARRAY['<postiz-tag-1>', '<postiz-tag-2>'],
  '<first sentence of post>',
  'postiz-scheduler'
)
ON CONFLICT (id) DO UPDATE SET
  url = EXCLUDED.url,
  published_at = EXCLUDED.published_at,
  updated_at = NOW();
```

## Analytics export Postiz API docs

- Postiz API: https://docs.postiz.com/api (v2.21.7+)
- Webhook events: Settings → Webhooks in Postiz UI
- Phase V spec: docs/specs/devrel-analytics-stack.md (AC-18)
