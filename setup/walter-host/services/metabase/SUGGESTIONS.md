# Metabase — Operator Customization Guide

## What ships by default

BI / dashboards for analytics and SQL exploration (AGPL-3.0 OSS edition).
- Version: `metabase/metabase:v0.53.11` (pinned semver).
- Internal port: `127.0.0.1:3001` → container 3000.
- Two Postgres 16 instances:
  - `metabase-pg`: Metabase app metadata (questions, dashboards, users).
  - `social-pg`: analytics data written by n8n workflows.
- JVM tuned to 1 GB heap (`JAVA_OPTS: -Xmx1024m`).
- Embedding disabled (internal use only).

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | ~600 MB - 1 GB | JVM minimum heap |
| RAM (active) | ~1-1.5 GB | Complex queries or many concurrent users |
| Disk (app) | ~50 MB/month | Dashboard definitions, saved questions |
| Disk (social-pg) | ~100 MB/month | At moderate n8n write volume |

## Common customizations

- **Connect data sources**: In Metabase admin → Databases → Add Database.
  Pre-configured: `metabase-pg` (Metabase internal), `social-pg` (analytics).
  Add more: `postgres` (Walter-OS shared Postgres), PostHog events via ClickHouse,
  LiteLLM usage data.

- **Adjust JVM heap** (for smaller VMs):
  ```yaml
  JAVA_OPTS: "-Xmx512m"
  ```
  Reduces RAM usage to ~400-600 MB at the cost of GC pressure under load.

- **Enable embedding** (for iframe embedding in internal dashboards):
  ```yaml
  MB_ENABLE_EMBEDDING: "true"
  ```
  Requires generating signed tokens per the Metabase embedding docs.

- **Add SMTP for user alerts**: Set `MB_EMAIL_SMTP_HOST`, `MB_EMAIL_SMTP_PORT`,
  `MB_EMAIL_SMTP_USERNAME`, `MB_EMAIL_SMTP_PASSWORD` for email notifications.

- **User provisioning**: Metabase OSS does not support SSO (SAML/OIDC).
  Invite users via the admin UI. For SSO, upgrade to Metabase Pro.

## When to override

- **>20 concurrent users**: Increase JVM heap (`-Xmx2048m`) and ensure the
  host has 4+ GB RAM available for Metabase.
- **Large dataset (>1 GB in social-pg)**: Add a query timeout to avoid long-
  running queries locking the UI:
  ```
  SELECT SET query_timeout = '30000';  -- Postgres session setting
  ```
- **Paid features needed** (SSO, column-level security, advanced permissions):
  Consider Metabase Pro ($500/month) or Metabase Cloud.

## Tradeoffs

- **Metabase vs Grafana**: Metabase excels at SQL-first ad-hoc exploration and
  business dashboards. Grafana is better for time-series metrics and DevOps
  dashboards. Use both: Grafana for infra/observability, Metabase for analytics.
- **OSS vs Pro**: OSS covers most solo/small-team use cases. Pro adds SSO,
  embedding, and support. The jump in cost is significant — evaluate at 10+ users.
- **Dependency on JVM**: Metabase requires Java, making it heavier than comparable
  tools (Redash is lighter if dashboards are simple).

## References

- Metabase docs: https://www.metabase.com/docs/latest/
- Metabase embedding: https://www.metabase.com/docs/latest/embedding/introduction
- Metabase pricing: https://www.metabase.com/pricing/
