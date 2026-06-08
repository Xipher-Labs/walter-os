# Walter-OS Services Inventory

Generated: 2026-05-11
Source: `setup/walter-host/services/*/compose.yml` (read-only audit for compose.yml authoring)

This document captures every service, its image+version, volumes, network exposure,
inter-service dependencies, bootstrap requirements, and environment variables.
It is the source of truth for startup ordering in the all-in-one `compose.yml`.

---

## Startup Order (dependency graph)

```
Layer 0 — infrastructure (no deps):
  postgres (shared)  ←  all app postgres clients
  caddy              ←  all HTTP ingress
  seaweedfs          ←  posthog (S3 object storage, internal-only)

Layer 1 — datastores requiring postgres:
  plane-db           ←  plane-api
  forgejo-db         ←  forgejo
  infisical-db       ←  infisical-backend
  litellm-db         ←  litellm
  n8n-pg             ←  n8n
  postiz-pg          ←  postiz   [profile: devrel]
  penpot-postgres    ←  penpot-backend  [profile: design]
  synapse-db         ←  synapse

Layer 2 — datastores: redis / mongo:
  plane-redis        ←  plane-api
  plane-mq           ←  plane-api (RabbitMQ)
  infisical-redis    ←  infisical-backend
  postiz-redis       ←  postiz   [profile: devrel]
  penpot-redis       ←  penpot-backend  [profile: design]
  rocketchat-mongo   ←  rocketchat

Layer 3 — core app services (depend on layers 0-2):
  plane-api          ←  plane-web, plane-worker, plane-beat-worker, plane-proxy
  forgejo
  infisical-backend
  litellm
  n8n
  prometheus         ←  grafana
  loki               ←  promtail, grafana
  grafana
  synapse            ←  element-web
  postiz             (marketing core — promoted from devrel in v0.2.0)
  metabase           (marketing core — promoted from devrel in v0.2.0)
  posthog-clickhouse ←  posthog, posthog-worker, posthog-plugin-server
  posthog            ←  posthog-worker, posthog-plugin-server, posthog-asyncmigrationscheck
  control-tower      (marketing core — inlined from standalone compose in v0.2.0)

Layer 4 — optional / profile-gated:
  penpot-*           [profile: design]
  drawio             [profile: design]
  hermes-agent       [profile: hermes-agent]
  openclaw           [profile: assistant]
  rocketchat         [profile: comms]
  chatgpt-codex-router  (LiteLLM-internal subscription bridge — port 1456)
  claude-sub-router     (LiteLLM-internal subscription bridge — port 1457)
  gemini-sub-router     (LiteLLM-internal subscription bridge — port 1458)

Layer 5 — network / VPN (no app deps):
  wg-easy            (WireGuard)
  headscale
  syncthing

Layer 6 — monitoring:
  uptime-kuma
  node-exporter
  cadvisor
  promtail

Layer 7 — meta:
  homepage
  control-tower      (requires built image walter-control-tower:latest)
```

---

## Service Details

### postgres (shared — all-in-one only)

| Field | Value |
|---|---|
| Image | `postgres:16-alpine` |
| Port (internal) | 5432 |
| Volumes | `postgres_data:/var/lib/postgresql/data` |
| Network | `walter_net` |
| Healthcheck | `pg_isready -U postgres` |
| Bootstrap | Create per-service DBs + users on first run |
| Env vars required | `POSTGRES_PASSWORD` |
| Note | In per-service composes, each service runs its own postgres container. In the all-in-one, one shared instance with separate databases replaces all per-service postgres containers. |

### caddy

| Field | Value |
|---|---|
| Image | `caddy:2-alpine` |
| Port (host) | 80, 443 |
| Volumes | `caddy_data:/data`, `caddy_config:/config`, `./setup/caddy/Caddyfile:/etc/caddy/Caddyfile:ro` |
| Network | `walter_net` |
| Healthcheck | `wget -qO- http://localhost:2019/metrics` (Caddy admin API) |
| Bootstrap | Caddyfile rendered from template via `envsubst` |
| Env vars required | `WALTER_DOMAIN` |
| Note | Single ingress point. All other services bind `127.0.0.1:<port>` and Caddy proxies. In all-in-one, services are on the docker network and Caddy reaches them by service name. |

### plane (project management)

| Field | Value |
|---|---|
| Per-service image | `makeplane/plane-{frontend,backend,admin,space,live,proxy}:stable` |
| Containers | plane-web, plane-admin, plane-space, plane-live, plane-api, plane-worker, plane-beat-worker, plane-migrator, plane-db (postgres), plane-redis, plane-mq (RabbitMQ), plane-minio, plane-proxy |
| Port (proxy→host) | 8090 → plane.${WALTER_DOMAIN} via Caddy |
| Volumes | `plane_pgdata`, `plane_redisdata`, `plane_uploads`, `plane_rabbitmq_data` |
| Network | `walter_net` |
| Startup deps | plane-db (healthy), plane-redis (started), plane-mq (started) |
| Migrator | Runs once (`restart: "no"`) — applies DB migrations on first boot |
| Bootstrap | Create workspace "walter-os" via Plane API after first up |
| Env vars required | `PLANE_POSTGRES_USER`, `PLANE_POSTGRES_PASSWORD`, `PLANE_POSTGRES_DB`, `PLANE_RABBITMQ_USER`, `PLANE_RABBITMQ_PASSWORD`, `PLANE_RABBITMQ_VHOST`, `PLANE_AWS_ACCESS_KEY_ID`, `PLANE_AWS_SECRET_ACCESS_KEY`, `PLANE_SECRET_KEY`, `PLANE_FILE_SIZE_LIMIT` |
| Hardcoded domain | `plane.${WALTER_DOMAIN}` — must be replaced with `plane.${WALTER_DOMAIN}` |
| Note | In all-in-one, plane-db is replaced by the shared postgres instance (separate `plane` database). Minio kept per-service because S3 interface is specific to Plane. |

### forgejo (git hosting)

| Field | Value |
|---|---|
| Image | `codeberg.org/forgejo/forgejo:15` |
| Port | 3000 → git.${WALTER_DOMAIN} via Caddy |
| Volumes | `forgejo_data:/data` |
| Network | `walter_net` |
| Startup deps | forgejo-db (healthy) — postgres |
| Bootstrap | Create admin user via Forgejo API (`/api/v1/admin/users`) |
| Env vars required | `FORGEJO_DB_PASS`, `WALTER_DOMAIN` |
| Hardcoded domain | `git.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |
| Config env | `FORGEJO__database__*`, `FORGEJO__server__*`, `FORGEJO__service__*`, `FORGEJO__security__INSTALL_LOCK=true` |
| Note | `INSTALL_LOCK=true` prevents the setup wizard from running. SSH port 22 optional (not in core all-in-one). |

### infisical (secrets manager)

| Field | Value |
|---|---|
| Image | `infisical/infisical:v0.159.25` |
| Port | 8080 → secrets.${WALTER_DOMAIN} via Caddy |
| Volumes | (none — stateless app; state in postgres + redis) |
| Network | `walter_net` |
| Startup deps | infisical-db (healthy), infisical-redis (healthy) |
| Migration | Runs inline at startup: `npm run migration:latest` then server |
| Bootstrap | Create workspace "walter-os" + Machine Identity "walter-agent" via API |
| Env vars required | `INFISICAL_ENCRYPTION_KEY`, `INFISICAL_AUTH_SECRET`, `INFISICAL_DB_PASS`, `INFISICAL_REDIS_PASS` |
| Hardcoded domain | `secrets.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |
| Healthcheck | `wget --quiet --spider http://localhost:8080/api/status` (60s start_period) |
| Note | ENCRYPTION_KEY and AUTH_SECRET are crypto material — must be randomly generated once and never changed after first run (data becomes unreadable). Generate with `openssl rand -hex 16` and `openssl rand -base64 32`. |

### litellm (LLM gateway)

| Field | Value |
|---|---|
| Image | `ghcr.io/berriai/litellm:v1.83.14-stable` |
| Port | 4000 → llm.${WALTER_DOMAIN} via Caddy |
| Volumes | `./setup/litellm/config.yaml:/app/config.yaml:ro` |
| Network | `walter_net` |
| Startup deps | litellm-db (healthy) |
| Bootstrap | Set master key via env; create virtual key for openclaw |
| Env vars required | `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `LITELLM_DB_PASS`, `LITELLM_UI_PASS`, `ANTHROPIC_API_KEY` (optional), `OPENAI_API_KEY` (optional), `GEMINI_API_KEY` (optional) |
| Config file | `setup/litellm/config.yaml` — must be present before compose up |
| Note | UI_USERNAME uses `${WALTER_INITIAL_USER:-admin}` — set `WALTER_INITIAL_USER` in env to customize. |

### grafana (dashboards)

| Field | Value |
|---|---|
| Image | `grafana/grafana:13.0.1` |
| Port | 3000 → grafana.${WALTER_DOMAIN} via Caddy |
| Volumes | `grafana_data:/var/lib/grafana`, `./setup/grafana/provisioning:/etc/grafana/provisioning:ro` |
| Network | `walter_net` |
| Startup deps | prometheus (healthy), loki (started) |
| Bootstrap | Admin password set via `GF_SECURITY_ADMIN_PASSWORD`; confirmed via API in bootstrap.sh |
| Env vars required | `GF_ADMIN_USER`, `GF_ADMIN_PASSWORD`, `WALTER_TELEGRAM_BOT_TOKEN` (optional), `WALTER_TELEGRAM_CHAT_ID` (optional) |
| Hardcoded domain | `grafana.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |
| Plugins | `grafana-assistant-app` (installed at startup via `GF_INSTALL_PLUGINS`) |
| Provisioning | Config files in `setup/grafana/provisioning/` (datasources, dashboards, alerting) — must exist before compose up |

### prometheus (metrics)

| Field | Value |
|---|---|
| Image | `prom/prometheus:v3.11.3` |
| Port | 9090 (internal only) |
| Volumes | `prometheus_data:/prometheus`, `./setup/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro` |
| Network | `walter_net` |
| Startup deps | none |
| Bootstrap | Config file must exist at `setup/prometheus/prometheus.yml` |
| Env vars required | none (config-driven) |
| Retention | 30d / 10GB |
| Note | Per-service compose uses host bind mounts at `/mnt/walter-vm-data/observability/prometheus`. In all-in-one, named volumes replace host mounts for portability. |

### loki (log aggregation)

| Field | Value |
|---|---|
| Image | `grafana/loki:3.7.1` |
| Port | 3100 (internal only) |
| Volumes | `loki_data:/loki`, `./setup/loki/loki.yml:/etc/loki/loki.yml:ro` |
| Network | `walter_net` |
| Startup deps | none |
| Healthcheck | none (distroless image, no shell) |
| Config file | `setup/loki/loki.yml` — must exist before compose up |

### promtail (log shipper)

| Field | Value |
|---|---|
| Image | `grafana/promtail:3.6.10` |
| Volumes | `/var/log:/var/log:ro`, `/var/lib/docker/containers:/var/lib/docker/containers:ro`, `/var/run/docker.sock:/var/run/docker.sock:ro`, `./setup/promtail/promtail.yml:/etc/promtail/promtail.yml:ro` |
| Network | `walter_net` |
| Startup deps | loki (started) |
| Config file | `setup/promtail/promtail.yml` — must exist before compose up |

### node-exporter (host metrics)

| Field | Value |
|---|---|
| Image | `prom/node-exporter:v1.11.1` |
| Port | 9100 (internal only) |
| Volumes | `/proc:/host/proc:ro`, `/sys:/host/sys:ro`, `/:rootfs:ro` |
| Network | `walter_net` |
| Note | `pid: host` required. Textfile collector at `/var/lib/walter-council` for agent metrics. |

### cadvisor (container metrics)

| Field | Value |
|---|---|
| Image | `gcr.io/cadvisor/cadvisor:v0.55.1` |
| Port | 8080 (internal only) |
| Privileges | `privileged: true`, device `/dev/kmsg` |
| Network | `walter_net` |

### n8n (workflow automation)

| Field | Value |
|---|---|
| Image | `n8nio/n8n:2.18.7` |
| Port | 5678 → n8n.${WALTER_DOMAIN} via Caddy |
| Volumes | `n8n_data:/home/node/.n8n`, `./n8n-files:/files` |
| Network | `walter_net` |
| Startup deps | n8n-pg (healthy) |
| Bootstrap | No API bootstrap needed; first user created via web UI |
| Env vars required | `N8N_PG_PASS`, `N8N_ENCRYPTION_KEY`, `WALTER_DOMAIN`, `WALTER_TIMEZONE` |
| Hardcoded domain | `n8n.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |

### wg-easy (WireGuard VPN)

| Field | Value |
|---|---|
| Image | `ghcr.io/wg-easy/wg-easy:14` |
| Port | 51820/udp (public), 51821 → vpn.${WALTER_DOMAIN} (web UI) |
| Volumes | `wg_config:/etc/wireguard` |
| Network | `walter_net` |
| Privileges | `cap_add: [NET_ADMIN, SYS_MODULE]`, `sysctls: net.ipv4.ip_forward=1` |
| Bootstrap | none (config via web UI) |
| Env vars required | `WG_PASSWORD_HASH`, `WALTER_DOMAIN` |
| Hardcoded domain | `vpn.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |

### headscale (Tailscale control plane)

| Field | Value |
|---|---|
| Image | `headscale/headscale:0.26.0` |
| Port | 8085 → headscale.${WALTER_DOMAIN}, 9095 (metrics) |
| Volumes | `./setup/headscale/config.yaml:/etc/headscale/config.yaml:ro`, `headscale_data:/var/lib/headscale` |
| Network | `walter_net` |
| Admin UI | `goodieshq/headscale-admin:0.25.6` on port 8086 |
| Bootstrap | Create namespace via headscale CLI (`docker exec headscale headscale namespaces create default`) |
| Config file | `setup/headscale/config.yaml` — rendered from `setup/headscale/config.yaml.template` before root compose starts |
| Note | Headscale config embeds `server_url`; after changing `WALTER_DOMAIN`, re-render only this file with `WALTER_DOMAIN=example.com envsubst '$WALTER_DOMAIN' < setup/headscale/config.yaml.template > setup/headscale/config.yaml`, then restart `headscale` if it is running. |

### syncthing (file sync hub)

| Field | Value |
|---|---|
| Image | `lscr.io/linuxserver/syncthing:2.0.16` |
| Ports | 8384 → sync.${WALTER_DOMAIN}, 22000/tcp+udp (device sync) |
| Volumes | `syncthing_config:/config`, `syncthing_data:/sync` |
| Network | `walter_net` |
| Env vars | `PUID=1000`, `PGID=1000`, `WALTER_TIMEZONE` |
| Healthcheck | `curl -fsS http://127.0.0.1:8384/rest/noauth/health` |
| Bootstrap | Device pairing via Syncthing web UI after first start |
| Note | Per-service compose bind-mounts `/mnt/walter-vm-data/sync`. In all-in-one, use named volume `syncthing_data` for portability. |

### uptime-kuma (uptime monitoring)

| Field | Value |
|---|---|
| Image | `louislam/uptime-kuma:2.3.2` |
| Port | 3001 → status.${WALTER_DOMAIN} via Caddy |
| Volumes | `uptime_kuma_data:/app/data` |
| Network | `walter_net` |
| Bootstrap | Auto-import monitor list via Uptime Kuma API at bootstrap time [AC-6] |
| Env vars | none required |
| Note | No healthcheck in per-service compose — add one in all-in-one. |

### postiz (social media scheduling) — marketing core

| Field | Value |
|---|---|
| Image | `ghcr.io/gitroomhq/postiz-app:v2.21.7` |
| Port | 3000 → postiz.${WALTER_DOMAIN} via Caddy |
| RAM | ~500 MB (app + redis combined) |
| Volumes | `postiz_uploads:/uploads` |
| Network | `walter_net` |
| Hostname | `postiz.${WALTER_DOMAIN}` |
| Startup deps | postgres (healthy), postiz-redis (healthy) |
| Env vars required | `POSTIZ_PG_PASS`, `POSTIZ_JWT_SECRET`, `WALTER_DOMAIN` |
| Per-service dir | `setup/walter-host/services/postiz/` (compose.yml, .env.template, SUGGESTIONS.md) |
| Note | Promoted from `--profile devrel` to always-on core in v0.2.0. Internal port is 3000 (not 5000 as previously documented). |

### metabase (BI dashboards) — marketing core

| Field | Value |
|---|---|
| Image | `metabase/metabase:v0.53.11` |
| Port | 3001 → metabase.${WALTER_DOMAIN} via Caddy |
| RAM | ~1 GB |
| Volumes | `metabase_data:/metabase-data` |
| Network | `walter_net` |
| Hostname | `metabase.${WALTER_DOMAIN}` |
| Startup deps | metabase-pg (healthy), social-pg (healthy) |
| Env vars required | `METABASE_DB_PASS`, `SOCIAL_PG_PASS`, `WALTER_DOMAIN` |
| Bootstrap | Navigate to `https://metabase.${WALTER_DOMAIN}` and complete the setup wizard. |
| Per-service dir | `setup/walter-host/services/metabase/` (compose.yml, .env.template, SUGGESTIONS.md) |
| Note | **All-in-one deploy** (root `compose.yml`): uses shared `walter-pg` Postgres. **Per-service deploy** (`setup/walter-host/services/metabase/compose.yml`): dedicated metabase-pg (app metadata) + social-pg (analytics data from n8n). Promoted from `--profile devrel` to always-on core in v0.2.0. |

### seaweedfs (S3-compatible object storage) — marketing core

| Field | Value |
|---|---|
| Image | `chrislusf/seaweedfs:4.03@sha256:d24be3bc1d6e8e305c095c446cb9a00d40e3afdac82fb2a1cc96f2d42c4a8e80` |
| Port | 127.0.0.1:8333 (S3 API), 127.0.0.1:9333 (master — internal) |
| RAM | ~300 MB |
| Volumes | `seaweedfs_data:/data` |
| Network | `walter_net` (internal only — no Caddy vhost) |
| Startup deps | none |
| Env vars required | none (auth disabled by default; see SUGGESTIONS.md for how to enable) |
| Per-service dir | `setup/walter-host/services/seaweedfs/` (compose.yml, .env.template, SUGGESTIONS.md) |
| Note | Internal S3 API used by PostHog for session recording V2 storage (SESSION_RECORDING_V2_S3_ENDPOINT). Events live in ClickHouse. No public-facing Caddy vhost — access from within the Docker network only. Container name: `seaweedfs-main`. |

### chatgpt-codex-router (Codex CLI subscription bridge)

| Field | Value |
|---|---|
| Image | Built from `setup/walter-host/services/chatgpt-codex-router/Dockerfile` |
| Port | 127.0.0.1:1456 (OpenAI-compatible API) |
| RAM | ~80–250 MB (Node.js + Codex CLI subprocess) |
| Volumes | `${HOME}/.codex:/home/appuser/.codex:rw` (OAuth creds from host; `${HOME}` is the host home directory) |
| Network | LiteLLM's Docker network (internal only — no Caddy vhost) |
| Startup deps | none |
| Env vars required | `CCR_APIKEY` (Bearer token for LiteLLM auth; generate: `openssl rand -hex 32`) |
| Per-service dir | `setup/walter-host/services/chatgpt-codex-router/` (docker-compose.yml, Dockerfile, server.js, package.json, RUNBOOK.md, .env.template, SUGGESTIONS.md) |
| Note | OpenAI-compatible thin bridge wrapping the Codex CLI. Runs as non-root `appuser` (uid 1001). Referenced by LiteLLM via `http://chatgpt-codex-router:1456/v1`. |

### claude-sub-router (Claude Code CLI subscription bridge)

| Field | Value |
|---|---|
| Image | Built from `setup/walter-host/services/claude-sub-router/Dockerfile` |
| Port | 127.0.0.1:1457 (OpenAI-compatible API) |
| RAM | ~80–250 MB (Node.js + Claude Code CLI subprocess) |
| Volumes | `${HOME}/.claude:/home/appuser/.claude:rw` (OAuth tokens from host; `${HOME}` is the host home directory) |
| Network | LiteLLM's Docker network (internal only — no Caddy vhost) |
| Startup deps | none |
| Env vars required | `CSR_APIKEY` (Bearer token for LiteLLM auth; generate: `openssl rand -hex 32`) |
| Per-service dir | `setup/walter-host/services/claude-sub-router/` (docker-compose.yml, Dockerfile, server.js, package.json, RUNBOOK.md, .env.template, SUGGESTIONS.md) |
| Note | Wraps `@anthropic-ai/claude-code` CLI. Runs as non-root `appuser` (uid 1001). Supported models: sonnet, opus, haiku, claude-sonnet-4-6, claude-opus-4-5. |

### gemini-sub-router (Gemini CLI subscription bridge)

| Field | Value |
|---|---|
| Image | Built from `setup/walter-host/services/gemini-sub-router/Dockerfile` |
| Port | 127.0.0.1:1458 (OpenAI-compatible API) |
| RAM | ~80–250 MB (Node.js + Gemini CLI subprocess) |
| Volumes | `${HOME}/.gemini:/home/appuser/.gemini:rw` (OAuth creds from host; `${HOME}` is the host home directory) |
| Network | LiteLLM's Docker network (internal only — no Caddy vhost) |
| Startup deps | none |
| Env vars required | `GSR_APIKEY` (Bearer token for LiteLLM auth; generate: `openssl rand -hex 32`) |
| Per-service dir | `setup/walter-host/services/gemini-sub-router/` (docker-compose.yml, Dockerfile, server.js, package.json, RUNBOOK.md, .env.template, SUGGESTIONS.md) |
| Note | Wraps `@google/gemini-cli`. Runs as non-root `appuser` (uid 1001). Uses OAuth from host `~/.gemini`. Pattern docs: `setup/walter-host/services/subscription-router-pattern/SUGGESTIONS.md`. |

### posthog (product analytics) — marketing core

| Field | Value |
|---|---|
| Image | `posthog/posthog@sha256:ffb55d524fc78cb431b267218df4ff0c380e1980bcc8fa32ab9b73c4629799ef` |
| Port | 8000 → posthog.${WALTER_DOMAIN} via Caddy |
| RAM | ~3–4 GB (all four PostHog processes combined) |
| Volumes | (stateless app; state in postgres + ClickHouse + Redis) |
| Network | `walter_net` |
| Hostname | `posthog.${WALTER_DOMAIN}` |
| Startup deps | postgres (healthy), posthog-clickhouse (healthy), posthog-redis (healthy) |
| Bootstrap | Navigate to `https://posthog.${WALTER_DOMAIN}` and complete the setup wizard. |
| Env vars required | `POSTHOG_SECRET`, `POSTHOG_DB_PASS`, `CLICKHOUSE_PASSWORD`, `WALTER_DOMAIN` |
| Image pin date | 2026-05-12 (commit e9a9a1a) — update by pulling `posthog/posthog:latest` and re-recording digest |
| Note | New service in v0.2.0. Plugin-server uses separate `posthog/posthog-node` image (sha-30c8ab7). |

### posthog-clickhouse — marketing core

| Field | Value |
|---|---|
| Image | `clickhouse/clickhouse-server@sha256:adb9fcf85e17f0dda74742a17bf6957549adc99e97fddfcab3a2a82cf9b62bfe` (tag: 26.3-alpine) |
| Port | 9000, 8123 (internal only — not exposed via Caddy) |
| RAM | ~1–2 GB |
| Volumes | `posthog_clickhouse_data:/var/lib/clickhouse`, `posthog_clickhouse_logs:/var/log/clickhouse-server` |
| Network | `walter_net` |
| Env vars required | `CLICKHOUSE_PASSWORD` |

### control-tower (Walter Council UI) — marketing core

| Field | Value |
|---|---|
| Image | `walter-control-tower:latest` (locally built from the repo root with `apps/control-tower/Dockerfile`) |
| Port | (none — Caddy proxies tower.${WALTER_DOMAIN} → control-tower:3000; no host port) |
| RAM | ~200 MB |
| Volumes | `/var/lib/walter-council:ro`, `/var/log/walter-council:ro`, `/root/.config/walter-os:ro` |
| Network | `walter_net` |
| Hostname | `tower.${WALTER_DOMAIN}` (Tailscale-only — TAILSCALE_ENFORCE=true) |
| Startup deps | litellm (healthy), grafana (healthy) |
| Bootstrap | Build image first from the repo root: `docker build -f apps/control-tower/Dockerfile -t walter-control-tower:latest .` |
| Env vars required | `CONTROL_TOWER_ADMIN_TOKEN`, `LITELLM_API_KEY`, `PLANE_API_URL`, `PLANE_API_TOKEN`, `PLANE_WORKSPACE_SLUG`, `PLANE_PROJECT_ID`, `GRAFANA_SA_TOKEN` |
| Note | Inlined from standalone `setup/walter-host/services/control-tower/compose.yml` in v0.2.0. Standalone file retained for independent deployments. Access is Tailscale-only by application enforcement. |

### penpot (design tool) [profile: design]

| Field | Value |
|---|---|
| Images | `penpotapp/frontend:latest`, `penpotapp/backend:latest`, `penpotapp/exporter:latest` |
| Port | 9001 → penpot.${WALTER_DOMAIN} via Caddy |
| Volumes | `penpot_assets:/opt/data/assets` |
| Network | `walter_net` |
| Startup deps | penpot-postgres (healthy), penpot-redis (started) |
| Env vars required | `PENPOT_DB_PASS`, `PENPOT_SECRET_KEY`, `WALTER_DOMAIN` |
| Hardcoded domain | `penpot.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |

### drawio (diagrams) [profile: design]

| Field | Value |
|---|---|
| Image | `jgraph/drawio:latest` |
| Port | 8083 → draw.${WALTER_DOMAIN} via Caddy |
| Volumes | none |
| Network | `walter_net` |
| Env vars required | `WALTER_DOMAIN` |
| Hardcoded domain | `draw.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |

### hermes-agent (AI assistant — alternative to OpenClaw) [profile: hermes-agent]

| Field | Value |
|---|---|
| Image | `walter-os/hermes-agent:${HERMES_AGENT_BASE_VERSION}-stt` (local flavor of `nousresearch/hermes-agent:${HERMES_AGENT_BASE_VERSION}`) |
| Subdomain | `hermes.${WALTER_DOMAIN}` |
| Profile | `hermes-agent` |
| Port (API) | 127.0.0.1:8642 → hermes.${WALTER_DOMAIN} via Caddy (dashboard: 9119) |
| RAM baseline | 1 GB (base), 3 GB (with browser automation tools) |
| Disk baseline | 2 GB (base), 5 GB (with browser automation tools) |
| Volumes | `hermes_data:/opt/data` |
| Network | `litellm_net` (external), `hermes_net` (bridge) |
| Startup deps | litellm (for LLM routing via Walter-Bridge) |
| Bootstrap | Copy `.env.template` to `.env`, set `LITELLM_HERMES_KEY`, run `docker compose --profile hermes-agent up -d` |
| Env vars required | `LITELLM_HERMES_KEY` |
| Per-service dir | `setup/walter-host/services/hermes-agent/` (Dockerfile, compose.yml, .env.template, SUGGESTIONS.md, README.md) |
| Note | Alternative to OpenClaw. MIT licensed. Skill-learning loop off by default. 20+ platform integrations. See docs/operational/agent-runtimes-comparison.md. |

### openclaw (personal AI assistant) [profile: assistant]

| Field | Value |
|---|---|
| Image | `node:24-slim` (installs `openclaw@2026.5.7` npm package at runtime) |
| Port | 18789 → claw.${WALTER_DOMAIN} via Caddy (Phase 2 — Phase 1 is loopback only) |
| Volumes | `openclaw_data:/workspace` |
| Network | `litellm_net` (LiteLLM access), `openclaw_net` (future Synapse bridges) |
| Startup deps | litellm (started) |
| Bootstrap | Requires `docker exec -it openclaw openclaw onboard` on first run |
| Env vars required | `LITELLM_OPENCLAW_KEY`, `OPENCLAW_TELEGRAM_BOT_TOKEN`, `OPENCLAW_OPERATOR_CHAT_ID`, `OPENCLAW_GATEWAY_TOKEN` |
| Note | Phase 1: Telegram-only. Phase 2: Matrix bridges via Synapse. See `docs/specs/openclaw.md` and `docs/specs/openclaw-phase2-matrix-bridges.md`. |
| Migration status | Phase 1 accepted (2026-05-12). Version pinned to `2026.5.7`. `@latest` removed (pre-OSS audit). |

### synapse (Matrix homeserver) [profile: comms]

| Field | Value |
|---|---|
| Image | `matrixdotorg/synapse:v1.119.0` |
| Port | 8008 → matrix.${WALTER_DOMAIN} via Caddy |
| Volumes | `synapse_data:/data`, `./setup/synapse/config:/data/config:ro` |
| Network | `walter_net` |
| Startup deps | synapse-db (healthy) |
| Bootstrap | **CRITICAL**: requires `docker run ... generate` to produce `homeserver.yaml` before first compose up. Config is not auto-generated on startup. |
| Env vars required | `SYNAPSE_DB_PASS`, `WALTER_DOMAIN` |
| Config file | `setup/synapse/homeserver.yaml` — MUST be generated first via `docker run --rm -e SYNAPSE_SERVER_NAME=... -e SYNAPSE_REPORT_STATS=no -v $(pwd)/setup/synapse/data:/data matrixdotorg/synapse:v1.119.0 generate` |
| Element Web | `vectorim/element-web:v1.11.95` on port 8081, needs `./setup/synapse/element/config.json:ro` |
| Postgres locale | `POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"` (critical — Synapse requires this) |
| Note | Most complex bootstrap dependency. Excluded from core profile; gated behind `--profile comms`. |

### rocketchat (team chat) [profile: comms]

| Field | Value |
|---|---|
| Image | `rocket.chat:7.10.4` |
| Port | 3002 → chat.${WALTER_DOMAIN} via Caddy |
| Volumes | `rocketchat_mongo:/data/db` |
| Network | `walter_net` |
| Startup deps | rocketchat-mongo (healthy — MongoDB with replica set) |
| Bootstrap | MongoDB replica set must be initialized: `rs.initiate()` |
| Env vars required | `RESEND_API_KEY`, `WALTER_DOMAIN` |
| Hardcoded domain | `chat.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |
| Note | Requires MongoDB (not postgres). Uses replica set (`rs0`). The healthcheck auto-initiates the replica set. |

### homepage (service dashboard)

| Field | Value |
|---|---|
| Image | `ghcr.io/gethomepage/homepage:latest` |
| Port | 3010 → home.${WALTER_DOMAIN} via Caddy |
| Volumes | `./setup/homepage/config:/app/config`, `/var/run/docker.sock:/var/run/docker.sock:ro` |
| Network | `walter_net` |
| Bootstrap | Config files in `setup/homepage/config/` (services.yaml, widgets.yaml, etc.) |
| Env vars | `HOMEPAGE_ALLOWED_HOSTS=home.${WALTER_DOMAIN},...` |
| Hardcoded domain | `home.${WALTER_DOMAIN}` — must use `${WALTER_DOMAIN}` |

### control-tower (Walter Council UI) [original standalone entry — see marketing core section above]

See the updated entry in the marketing core section. This service was inlined into the root `compose.yml` in v0.2.0 from `setup/walter-host/services/control-tower/compose.yml`.

---

## Config Files Required Before `compose up`

These files must exist on disk before `docker compose up` will work correctly:

| File | Service | Notes |
|---|---|---|
| `setup/caddy/Caddyfile` | caddy | Generated from `setup/caddy/Caddyfile.template` via `envsubst` |
| `setup/litellm/config.yaml` | litellm | Minimal version shipped in repo |
| `setup/prometheus/prometheus.yml` | prometheus | Shipped in repo |
| `setup/loki/loki.yml` | loki | Shipped in repo |
| `setup/promtail/promtail.yml` | promtail | Shipped in repo |
| `setup/grafana/provisioning/` | grafana | Datasource + dashboard provisioning YAML |
| `setup/headscale/config.yaml` | headscale | Generated from `setup/headscale/config.yaml.template` via `envsubst` |
| `setup/synapse/data/homeserver.yaml` | synapse | **Must be generated via `docker run ... generate`** |
| `setup/synapse/element/config.json` | element-web | Shipped in repo |
| `setup/homepage/config/` | homepage | services.yaml, widgets.yaml, settings.yaml |

---

## Services Excluded from All-In-One (no compose.yml)

| Service | Reason |
|---|---|
| alerting | Shell scripts + cron (no Docker service) |
| beeper-self-hosted | Work in progress / not containerized |
| restic | Backup scripts (`restic-backup.sh`, `setup.sh`) — runs as host cron, not a service |

---

## Environment Variable Master List

Minimum required for `docker compose up` of core services:

```bash
# Bootstrap (5 required vars)
WALTER_DOMAIN=
WALTER_ADMIN_EMAIL=
WALTER_INITIAL_USER=
WALTER_INITIAL_PASSWORD=
WALTER_TIMEZONE=

# Postgres shared instance
POSTGRES_PASSWORD=

# Plane
PLANE_POSTGRES_PASSWORD=
PLANE_RABBITMQ_PASSWORD=
PLANE_RABBITMQ_USER=
PLANE_RABBITMQ_VHOST=
PLANE_SECRET_KEY=
PLANE_AWS_ACCESS_KEY_ID=      # Minio
PLANE_AWS_SECRET_ACCESS_KEY=  # Minio

# Forgejo
FORGEJO_DB_PASS=

# Infisical (crypto — generate once, never change)
INFISICAL_ENCRYPTION_KEY=     # openssl rand -hex 16
INFISICAL_AUTH_SECRET=        # openssl rand -base64 32
INFISICAL_DB_PASS=
INFISICAL_REDIS_PASS=

# LiteLLM
LITELLM_MASTER_KEY=
LITELLM_SALT_KEY=
LITELLM_DB_PASS=
LITELLM_UI_PASS=
ANTHROPIC_API_KEY=            # optional — enables Anthropic models
OPENAI_API_KEY=               # optional
GEMINI_API_KEY=               # optional

# Grafana
GF_ADMIN_PASSWORD=            # derived from WALTER_INITIAL_PASSWORD at bootstrap

# n8n
N8N_PG_PASS=
N8N_ENCRYPTION_KEY=           # openssl rand -hex 32

# WireGuard
WG_PASSWORD_HASH=             # generate: wg-easy generates this

# Optional (Telegram alerting)
WALTER_TELEGRAM_BOT_TOKEN=
WALTER_TELEGRAM_CHAT_ID=
```
