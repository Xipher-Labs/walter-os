# Marketing Core Stack — Operational Guide

> Added in v0.2.0. Four services are now always-on in the default
> `docker compose up -d` — no profile flag required.

---

## What is the marketing core?

The marketing core is the set of services that support the operator's
outward-facing work: analytics, scheduling, BI, and agent management.
These services were previously opt-in (profile-gated or standalone);
as of v0.2.0 they are always-on because they are central to the OSS
launch narrative and a first-time evaluator should see them immediately.

---

## Services overview

| Service | URL | RAM | What it does |
|---|---|---|---|
| Postiz | `https://postiz.${WALTER_DOMAIN}` | ~300–500 MB | Social media scheduling — queue and publish content across Twitter/X, LinkedIn, Instagram, etc. |
| Metabase | `https://metabase.${WALTER_DOMAIN}` | ~1 GB | BI dashboards and SQL queries against any connected database. Walter-OS connects it to the shared `walter-pg` instance. |
| PostHog | `https://posthog.${WALTER_DOMAIN}` | ~3–4 GB (4 processes combined) | Product analytics + session replay. Tracks events from web/mobile apps, runs experiments, feature flags. |
| Control Tower | `https://tower.${WALTER_DOMAIN}` | ~200 MB | Walter Council UI — manage agent tasks, view Grafana dashboards, interact with LiteLLM, browse Plane issues. Tailscale-only access. |

---

## Resource requirements

| Component | Approx RAM |
|---|---|
| Postiz + postiz-redis | ~500 MB |
| Metabase | ~1 GB |
| PostHog (web + worker + plugin-server + asyncmigrationscheck) | ~3–4 GB |
| ClickHouse | ~1–2 GB |
| Control Tower | ~200 MB |
| **Total marketing core** | **~6 GB** |

**Minimum VM spec (v0.2.0+):** 8 GB RAM / 4 vCPU / 80 GB SSD.

The previous minimum (4 GB / 2 vCPU / 40 GB) is insufficient once
PostHog and ClickHouse are always-on. Operators on the previous spec
must upgrade before pulling v0.2.0.

### Disk

- ClickHouse event store: grows with event volume. Budget 10–20 GB for
  the first year at moderate traffic. Prune old data with `OPTIMIZE TABLE`
  or configure retention policies.
- Postiz uploads: minimal unless you store media files locally.
- Metabase: stateless (metadata in `walter-pg`).

### Upgrade path

If 8 GB RAM is tight, the first optimization is to disable
`posthog-asyncmigrationscheck` after the first run (it's `restart: "no"`
and only runs once). PostHog's event ingestion does not require a dedicated
Kafka broker for single-node setups — the web process handles ingestion
directly.

---

## PostHog — first-run instructions

1. Navigate to `https://posthog.${WALTER_DOMAIN}`.
2. Complete the setup wizard (create admin account).
3. Create your first project and note the Project API Key.
4. To instrument an app: paste the JavaScript snippet or use one of
   PostHog's SDKs with `api_host: https://posthog.${WALTER_DOMAIN}`.
5. Session replay: enable in `Project Settings → Session Recording`.

### Image pinning note

PostHog does not publish semver releases for its Docker image. The image is
pinned to a SHA digest (commit `e9a9a1a`, 2026-05-12). To update:

```bash
docker pull posthog/posthog:latest
docker inspect --format='{{index .RepoDigests 0}}' posthog/posthog
```

Record the digest and update all four `posthog/posthog@sha256:...` entries
in `compose.yml`. Same process for `posthog/posthog-node` (plugin-server).

---

## Metabase — first-run instructions

1. Navigate to `https://metabase.${WALTER_DOMAIN}`.
2. Complete the setup wizard (create admin account).
3. Add a database connection: host `postgres`, port `5432`, database `metabase`,
   user `metabase`, password `${METABASE_DB_PASS}`.
4. (Optional) Connect additional databases: `walter` (for Infisical/LiteLLM data),
   `plane` (for project metrics).

**Version note**: Pinned at v0.53.11. Upgrading to v0.59.x requires a DB migration
and is tracked as a follow-up — do not upgrade in place without reviewing the
Metabase migration guide.

---

## Postiz — first-run instructions

1. Navigate to `https://postiz.${WALTER_DOMAIN}`.
2. Create an account (registration is open on first boot).
3. Connect your social channels (Twitter/X, LinkedIn, Instagram, etc.)
   via the Channels page.
4. Create a content calendar and schedule posts.

**Webhook integration**: Set `POSTIZ_WEBHOOK_URL` to your n8n ingest URL
to receive posting events and trigger n8n workflows.

---

## Control Tower — first-run instructions

Control Tower requires a locally-built image. The image is NOT pulled from
a registry — it is built from `apps/control-tower/` in this repo.

### Build step (mandatory prerequisite)

```bash
# 1. Build the Control Tower image first (compose build uses the build: stanza)
docker compose build control-tower

# 2. Start the full stack
docker compose up -d
```

Run `docker compose build control-tower` before `docker compose up -d`. If the
image does not exist, the container will fail to start with "image not found".

### Access

Control Tower is Tailscale-only by design. The `TAILSCALE_ENFORCE=true`
environment variable causes the app to check that the requesting IP is in
the Tailscale CGNAT range (`100.64.0.0/10`). Requests from public IPs are
rejected with a 403.

To access:
1. Connect to Tailscale (or Headscale).
2. Navigate to `https://tower.${WALTER_DOMAIN}`.

### Required services

Control Tower needs working Grafana and LiteLLM before it can show dashboards
or run agent tasks. Start the full stack first:

```bash
docker compose up -d
# Wait for grafana and litellm to be healthy, then:
docker compose up -d control-tower
```

---

## Postgres init.sql

PostHog needs a dedicated database on the shared `walter-pg` instance.
`setup/postgres/init.sql` includes the idempotent `CREATE USER posthog`
and `CREATE DATABASE posthog` statements. The password is synced by
`bootstrap.sh` via `ALTER USER posthog PASSWORD '...'` using the
`POSTHOG_DB_PASS` env var.

---

## Refs

- Spec: `docs/specs/walter-marketing-core-reconcile.md`
- Hosting min specs: `docs/operational/hosting-providers-comparison.md`
- Services inventory: `setup/SERVICES-INVENTORY.md`
- PostHog self-host docs: https://posthog.com/docs/self-host
- Metabase docs: https://www.metabase.com/docs/latest/
- Postiz docs: https://docs.postiz.com/
