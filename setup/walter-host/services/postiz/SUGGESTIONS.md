# Postiz — Operator Customization Guide

## What ships by default

Social media scheduling and publishing platform (AGPL-3.0).
- Version: `ghcr.io/gitroomhq/postiz-app:v2.21.7` (pinned semver).
- Internal port: `127.0.0.1:5000` → container 3000.
- Postgres 16 + Redis 7 included in per-service compose.
- Local file storage for uploads (bind-mount or named volume).

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | ~300-400 MB | Next.js app + BullMQ |
| RAM (active queue) | ~500-700 MB | Post queue processing |
| Disk (app) | minimal | Stateless |
| Disk (uploads) | varies | Media files; ~50 MB/month at light usage |
| Disk (Postgres) | ~100 MB/month | Post history, scheduled items |

## Common customizations

- **Connect OAuth channels**: See `docs/operational/postiz-runbook.md` for
  step-by-step OAuth app registration per platform (X, LinkedIn, Instagram,
  TikTok, YouTube).

- **Analytics webhook (n8n integration)**:
  Set `POSTIZ_WEBHOOK_URL` to your n8n workflow ingest URL. Postiz sends
  a POST request on every publish/engagement event. See:
  `docs/operational/postiz-analytics-export.md`.

- **Disable public registration**: Default `compose.yml` does not set
  `DISABLE_REGISTRATION`. Add it to prevent self-registration:
  ```yaml
  DISABLE_REGISTRATION: "true"
  ```

- **External S3 for uploads**: For large media files, replace local storage:
  ```yaml
  STORAGE_PROVIDER: s3
  STORAGE_ACCESS_KEY: ${S3_ACCESS_KEY}
  STORAGE_SECRET_KEY: ${S3_SECRET_KEY}
  STORAGE_BUCKET: postiz
  STORAGE_ENDPOINT: https://s3.${WALTER_DOMAIN}
  ```

- **Metabase integration**: Point Metabase's social-pg data source at the
  Postiz database to query post history and engagement stats.

## When to override

- **High media volume (>1 GB/month)**: Switch to S3-compatible storage.
- **Multi-user team**: Enable SMTP for user invites (`SMTP_*` env vars).
- **Custom domain**: Ensure `MAIN_URL`, `FRONTEND_URL`, and
  `NEXT_PUBLIC_BACKEND_URL` all use your actual domain.

## Tradeoffs

- **Postiz vs Buffer/Hootsuite**: Postiz is self-hosted (data stays local),
  free under AGPL, but requires ops overhead. Managed tools are simpler
  but have per-seat pricing.
- **AGPL license**: If you fork Postiz and offer it as a SaaS, you must
  open-source your changes. Internal self-hosting has no such obligation.

## References

- Postiz repo: https://github.com/gitroomhq/postiz-app
- Postiz docs: https://docs.postiz.com
- Runbook: `docs/operational/postiz-runbook.md`
- Analytics export: `docs/operational/postiz-analytics-export.md`
