# DevRel Analytics Stack — Phase V spec

> **Status**: APPROVED for auto-dispatch after Phase U converges.
> **Owner**: the operator
> **Created**: 2026-05-11
> **Updated**: 2026-05-11 (refined with n8n orchestrator + tool decisions + work/ context scope)
> **Refs**: `docs/specs/walter-council-v2.md` (Phase V)
> **Context primary use case**: `work/` (example work org DevRel). Loaded only when cwd matches `~/work/*`.
> **Not loaded in**: `projects-personal/` (example civic app, example medical app, hackathons), `personal/`. Those projects don't run a DevRel pipeline.

---

## Problem

example work org produce contenido DevRel (threads X, blog posts, YouTube scripts, LinkedIn posts) vía Postiz + `devrel-writer` agent + nanobanana. Pero el sistema **no tiene feedback loop**:

- Cero ingestion de métricas de performance.
- Cero attribution de "qué hook / formato / hora funcionó".
- Cero feedback al `devrel-writer` para condicionar nuevo contenido en patterns que funcionaron.
- Operator revisa cada plataforma manualmente (X Analytics, LinkedIn dashboard, YouTube Studio, GitHub insights, Plausible) — overhead lineal con el número de canales.

Plus el espacio comercial está partido:
- **Organic**: Postiz/Mixpost OSS cubren bien.
- **Ads**: Metricool/Sprout/Synter SaaS dominan. OSS unified para Google + Meta + X juntos NO existe.

Resultado actual: el sistema **publica pero no aprende**. Plata y tiempo invertido sin medición ni attribution.

---

## Non-goals

- No es growth-hacking dashboard. Es instrumento de medición + insight.
- No publica automáticamente basado en analytics. Decisión final sigue siendo del operator.
- No es analytics de producto (example civic app/example medical app) — `projects-personal/` no carga este stack.
- No persigue engagement como goal. La métrica norte sigue siendo "did this help a developer ship faster" (cualitativa, no medible directo).
- No reemplaza al operator-judgment. Es asistencia, no piloto automático.

---

## Decisions (todas locked en esta iteración)

### Decision 1 — Stack arquitectónico: n8n orchestrator + Postgres + Grafana

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│   PLATAFORMAS   │    │ N8N WORKFLOWS    │    │   POSTGRES      │    │ VISUALIZACIÓN    │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤    ├──────────────────┤
│ YouTube API     │───▶│ cron 6h pull     │───▶│ analytics_events│───▶│ Grafana panels   │
│ Google Ads API* │───▶│ cron 6h + OAuth  │───▶│  (append-only)  │    │ embedded in      │
│ Meta Graph API  │───▶│ cron 6h + token  │───▶│                 │───▶│ Control Tower    │
│ X Ads (CSV)     │───▶│ folder watch     │───▶│ content_pieces  │    │ tab "Content"    │
│ Plausible API   │───▶│ cron 1h          │───▶│                 │    │                  │
│ GitHub API      │───▶│ cron 24h         │───▶│ ad_spend_events │    │                  │
│ Bluesky stream  │───▶│ streaming        │───▶│                 │    │                  │
└─────────────────┘    └──────────────────┘    └─────────────────┘    └──────────────────┘
                              │                         │
                              ▼                         ▼
                       ┌──────────────┐         ┌────────────────┐
                       │ Anomaly det. │         │ devrel-analyst │
                       │ → Telegram   │         │ skill queries  │
                       └──────────────┘         │ Postgres direct│
                                                └────────────────┘

* Google Ads API también cubre YouTube Ads metrics (read-only, sufficient for analytics).
```

Razones:
- **n8n** ya está en Walter-VM stack (default profile).
- **Visual workflows** = operator puede modificar sin tocar código.
- **OAuth refresh nativo** + retry + error handling built-in.
- **Composable** con otros workflows (n8n ya orquesta otras cosas).
- **Versionable**: workflows export a JSON, commit a git.
- **Postgres** ya existe en walter-vm. Schema append-only escala lineal.
- **Grafana** ya está embebido en Control Tower (Phase U).

### Decision 2 — Tool selection con OSS-first + paid alternatives documentadas

Walter-OS va a ser OSS eventually → cada tool tiene **chosen (OSS)** + **alternativas pagas** documentadas para forkeadores que prefieran SaaS.

#### Organic social management

| Capability | **Chosen (OSS, self-host)** | Paid alternatives | Decision rationale |
|---|---|---|---|
| Multi-platform scheduling + publishing | **Postiz** (30k★, AGPL-3.0, v2.21.7 released 2 weeks ago) | Buffer, Later, Hootsuite, Metricool ($25/mo) | Already deployed; very active; covers ALL platforms we need free |
| Web analytics | **Plausible** (self-hosted) | Fathom, Simple Analytics | Already running |

**Mixpost was evaluated and dropped** (2026-05-11): Mixpost Lite (free OSS) only supports Facebook Pages + X + Mastodon. Instagram, LinkedIn, YouTube, TikTok, Threads, Bluesky require Mixpost Pro ($299 one-time). Postiz already covers all those platforms free under AGPL-3.0. No business case for dual install. See `docs/operational/phase-v-tools-availability.md` for the comparison.

#### Ads management — Singer taps stack

| Capability | **Chosen (OSS, self-host)** | Paid alternatives | Decision rationale |
|---|---|---|---|
| Google Ads ingestion (incl. YouTube Ads metrics) | **tap-google-ads** (Singer, AGPL-3.0) | Metricool ($25/mo), Synter ($199/mo) | Mature Python tap, well-maintained, YouTube Ads metrics flow through Google Ads API |
| Meta Ads + Meta Organic ingestion | **tap-facebook** (Singer, AGPL-3.0) | (covered above) | Singer ecosystem, OAuth handled |
| LinkedIn Ads ingestion | **tap-linkedin-ads** (Singer, AGPL-3.0, v2.6.0 Jan 2026) — **Tier 3, paperwork-gated** | (covered above) | OSS, mature; LinkedIn Marketing Developer Platform approval is the barrier (1-15 días), not code |
| X Ads | **CSV manual export → n8n folder watch** (free) | X API v2 Basic ($200/mo) | $200/mo prohibitivo for measurement-only; CSV path is operator 5min/week |
| Google Analytics 4 (if needed) | **tap-google-analytics** (Singer, AGPL-3.0) | (covered above) | Optional — only if blog/landing analytics depth needed beyond Plausible |

**Adspirer MCP was evaluated and dropped** (2026-05-11): the repo `amekala/ads-mcp` is NOT MIT-licensed OSS — it's a thin client pointing to hosted SaaS at `mcp.adspirer.com` (proprietary backend, no license file, 43 stars). The data point "MIT, 273 stars" from initial research was incorrect. Singer ecosystem (taps) is the genuine OSS alternative: each tap is a Python CLI that pulls platform data into a JSON stream, easily wired into n8n via `Execute Command` node or scheduled cron + Singer state files.

**Singer integration pattern**:
```
n8n cron 6h
  → spawn tap-google-ads with state file from previous run
  → pipe JSON output to small Python script that maps Singer → analytics_events schema
  → COPY to Postgres
  → update state file (incremental sync)
```

Each tap takes 4-8h to wire (OAuth config + state management + schema mapping). 4 taps × ~6h avg = ~24h total ads integration (within Phase V budget of 51-68h).

#### Insights + feedback loop

| Capability | **Chosen (OSS)** | Paid alternatives | Decision rationale |
|---|---|---|---|
| Analytics insights | **`devrel-analyst` skill** (Walter-OS native) | Sprout AI, HubSpot | Custom skill que conoce el `devrel-writer` agent — feedback loop natural |
| Anomaly detection | **n8n workflow → Telegram bot** | PagerDuty, Datadog | Reuse alerts pipeline de Phase F |

### Decision 3 — Platforms tier matrix (sequencing)

**Tier 1 — Quick wins (week 1, ~5h)**:
- YouTube Data API (free, immediate approval)
- Plausible (self-host, no API key)
- GitHub (free PAT, immediate)
- Bluesky firehose (free, no approval)

**Tier 2 — Auth flow gated (week 2-3, ~10h dev + waiting)**:
- Google Ads API + YouTube Ads (3-5 days dev token approval)
- Meta Ads + Meta Organic (5-15 days App Review + Business Verification)
- X via CSV path (immediate, but operator weekly task)
- TikTok (1-7 days approval)

**Tier 3 — Paperwork heavy (week 4+, ~5h dev + may take month)**:
- LinkedIn Marketing Developer Platform (approval notoriously hard, may reject)

**Tier 4 — Deferred / skip**:
- X API v2 paid path (only if Tier 1+2 don't give enough signal AND budget approved)

### Decision 4 — Schema

```sql
CREATE TABLE analytics_events (
  id            BIGSERIAL PRIMARY KEY,
  occurred_at   TIMESTAMPTZ NOT NULL,
  ingested_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  platform      TEXT NOT NULL,       -- 'twitter', 'youtube', 'plausible', etc.
  content_id    TEXT NOT NULL,       -- tweet ID, video ID, slug
  event_type    TEXT NOT NULL,       -- 'impression', 'engagement', 'click', 'conversion'
  metric_value  NUMERIC NOT NULL,
  metadata      JSONB,
  UNIQUE (platform, content_id, event_type, occurred_at)
);

CREATE TABLE content_pieces (
  id            TEXT PRIMARY KEY,        -- `<platform>:<external_id>`
  title         TEXT,
  url           TEXT,
  published_at  TIMESTAMPTZ,
  tags          TEXT[],
  hook          TEXT,                    -- first sentence, para hook-pattern analysis
  word_count    INTEGER,
  has_image     BOOLEAN DEFAULT false,
  has_code      BOOLEAN DEFAULT false,
  has_video     BOOLEAN DEFAULT false,
  created_by    TEXT,                    -- 'devrel-writer-agent', 'operator-manual'
  draft_path    TEXT                     -- link al draft en wiki/devrel/drafts/
);

-- New for ads
CREATE TABLE ad_spend_events (
  id            BIGSERIAL PRIMARY KEY,
  occurred_at   TIMESTAMPTZ NOT NULL,
  platform      TEXT NOT NULL,           -- 'google', 'meta', 'x', 'youtube' (YT is google sub)
  campaign_id   TEXT NOT NULL,
  ad_group_id   TEXT,
  ad_id         TEXT,
  spend_usd     NUMERIC NOT NULL,
  impressions   INTEGER,
  clicks        INTEGER,
  conversions   INTEGER,
  metadata      JSONB,
  UNIQUE (platform, ad_id, occurred_at)
);
```

Materialized views: por week + platform + content piece + ad campaign para fast queries del analyst skill.

---

## Context loading rules

Para mantener context-bounded execution:

- **work/**: Phase V stack carga (skills `devrel-analyst`, n8n workflows DevRel, Grafana panels DevRel, schema `analytics_events`).
- **projects-personal/**: Phase V stack NO carga. Esos proyectos usan otros analytics (product analytics, no DevRel).
- **personal/**: NO carga.

Aplicar a `contexts/work/AGENTS.md`:

```markdown
## DevRel analytics (Phase V — work/ only)

When working on example work org DevRel content:
- Query past performance via `devrel-analyst` skill before drafting new content.
- The skill reads from Postgres `analytics_events` + `content_pieces`.
- Examples:
  - "Show top 5 threads by engagement last 30 days"
  - "What hook patterns worked best for Solana RPC content"
  - "Compare CTR of threads with code vs without"
```

---

## Acceptance criteria

### Part A — Tier 1 ingestion (week 1)

- [AC-1] n8n workflow `yt-data-api-pull` corre cron 6h, escribe `analytics_events` con platform=youtube.
- [AC-2] n8n workflow `plausible-pull` corre cron 1h, escribe events platform=plausible.
- [AC-3] n8n workflow `github-pull` corre cron 24h, escribe stars/traffic/clones.
- [AC-4] n8n workflow `bluesky-stream` runs continuously, ingests post engagement.
- [AC-5] Tabla `analytics_events` populada with >100 events después de 24h running.

### Part B — Tier 2 ingestion (week 2-3)

- [AC-6] `tap-google-ads` integrated en n8n via Execute Command + cron 6h. Workflow ingests Google Ads + YouTube Ads metrics into `ad_spend_events`. State file managed in `~/.config/walter-os/singer-state/google-ads.json`.
- [AC-7] `tap-facebook` workflow ingests Meta Ads + Meta Organic after App Review approved.
- [AC-8] `x-csv-ingest` workflow watches `~/sync/devrel/x-analytics-exports/` for new CSV, parses, writes `analytics_events`.
- [AC-9] `tiktok-pull` workflow ingests after approval (HTTP node + TikTok Ads API).

### Part C — Dashboard (week 4)

- [AC-10] Tab "Content" en Control Tower (apps/control-tower) muestra: top 5 piezas / month, heatmap horas óptimas, pipeline drafts, spend total, ROI por content.
- [AC-11] Grafana dashboard `walter-devrel-analytics.json` con drill-down por platform + ad campaign.
- [AC-12] CLI `walter-os content stats --since 30d` imprime summary.

### Part D — Insights + feedback loop (week 4)

- [AC-13] Skill `devrel-analyst` invocable desde CLI + desde otros agents. Queries directas a Postgres.
- [AC-14] Weekly digest cron Lunes 09:00 ART commitea a `~/sync/wiki/devrel/insights/weekly-<YYYY-WW>.md` + Telegram notification.
- [AC-15] Anomaly detection: engagement >3σ del baseline 30d → emit `alert_emit info` con link a content piece.
- [AC-16] `devrel-writer` agent (work/ context) consulta `devrel-analyst` ANTES de escribir nuevo contenido similar a publicado. Patrón: `query_top_patterns(topic="solana-rpc", since="30d")`.

### Part E — Postiz upgrade verification (week 1)

- [AC-17] Postiz deployed version verified against latest stable (v2.21.7 as of 2026-05-11). Upgrade if behind.
- [AC-18] Postiz analytics export endpoint enabled — schema documented for `analytics_events` ingestion via direct API or Postiz webhooks → n8n.

(Mixpost dual-install dropped after availability research — see decision log.)

**Effort total estimado**: 51-68h TDD distribuidos en ~4-6 weeks (paperwork waits son lo más largo).

---

## Operator prereqs (post-merge)

Documentado en `docs/operational/council-v2-prereqs.md` sección "Phase V":

- V-prereq-1: Google Ads Developer Token aprobado (apply en Google Ads Manager → API Center, ~3-5 días)
- V-prereq-2: Meta Business Verification + App Review approved (`ads_read` scope, ~5-15 días)
- V-prereq-3: **LinkedIn Marketing Developer Platform aprobado** — **APPLY NOW**, antes de que Phase V arranque. Multi-day gated, notoriously hard. Tier 3 in scope, but the application is the blocker, not code. Apply: https://learn.microsoft.com/en-us/linkedin/marketing/integrations
- V-prereq-4: Postiz deployed version verified ≥ v2.21.7 (upgrade vía `docker compose pull && docker compose up -d` si está atrás)
- V-prereq-5: n8n credentials configured per platform OAuth (6 native nodes: YouTube, Google Ads, Facebook, X, LinkedIn, GitHub; 5 via HTTP node: Instagram, Threads, TikTok, Bluesky, Plausible)
- V-prereq-6: Postgres DB `walter_devrel_analytics` provisioned **con extensiones `pg_partman` + `pg_cron`** — NO disponibles en image `postgres:17` oficial. Construir custom Dockerfile en `setup/vm/postgres/Dockerfile`:
  ```dockerfile
  FROM postgres:17
  RUN apt-get update && apt-get install -y \
      postgresql-17-partman \
      postgresql-17-cron \
      && rm -rf /var/lib/apt/lists/*
  ```
  Y en `postgresql.conf` agregar: `shared_preload_libraries = 'pg_cron'`.
- V-prereq-7: Grafana datasource Postgres apuntando a la nueva DB (built-in core, no plugin install)
- V-prereq-8: Telegram bot habilitado para alerts (ya existe de Phase F)
- V-prereq-9: Singer Python env preparado en walter-vm: `pip install singer-python tap-google-ads tap-facebook tap-linkedin-ads tap-google-analytics`. Singer state files dir: `~/.config/walter-os/singer-state/` (gitignored).

---

## Future (post-Phase-V)

- **Walter-OS goes OSS**: este spec ya está documentado con "chosen + paid alternatives" para que future forkeadores con menos OSS preference puedan elegir Metricool/Sprout/Synter en lugar.
- **Walter-OS marketplace**: paid users skip Tier 2/3 paperwork by using Synter API key → Walter-OS reads from Synter same schema.
- **More platforms**: Reddit Ads, Pinterest, Mastodon — easy via n8n HTTP node.

---

## Decision log (en este spec)

- 2026-05-11 — n8n elegido como orchestrator vs custom bash adapters. Razón: visual control + OAuth refresh + composable + already-in-stack.
- 2026-05-11 (revisado) — **Mixpost dropped**. Investigación tools availability mostró que Mixpost Lite (free) solo cubre Facebook Pages + X + Mastodon. Resto (IG, LinkedIn, YT, TikTok, Threads, Bluesky) detrás de Pro $299. Postiz (AGPL-3.0, 30k★, v2.21.7) cubre TODO gratis. No business case para dual install. Ref: `docs/operational/phase-v-tools-availability.md`.
- 2026-05-11 (revisado) — **Adspirer MCP dropped**. La data inicial ("MIT, 273 stars") fue incorrecta. Repo real (`amekala/ads-mcp`) es thin client a SaaS proprietary backend (`mcp.adspirer.com`), sin license file, 43 stars. **Reemplazado por Singer taps stack** (`tap-google-ads`, `tap-facebook`, `tap-linkedin-ads`, `tap-google-analytics`) — todos AGPL-3.0, maduros, ecosystem activo.
- 2026-05-11 — X via CSV path elegido. Razón: $200/mo API prohibitivo for measurement-only.
- 2026-05-11 — LinkedIn deferred a Tier 3. Razón: paperwork barrier alto. **Apply NOW** porque approval es gated multi-day.
- 2026-05-11 — Phase V context: work/ only. Razón: DevRel applies a example work org, no a projects-personal/personal.
- 2026-05-11 — analyst as **skill, not agent**. Promote a 7mo agent solo si proactive pattern-mining demuestra value en mes 1.
- 2026-05-11 — Postgres requiere custom Dockerfile con `pg_partman` + `pg_cron` extensions (no in official image). Documentado en V-prereq-6.

---

## Approvals required

Spec aprobado para auto-dispatch después que Phase U converja. Si el operator quiere cambios estructurales antes del dispatch, editar este file y avisar.
