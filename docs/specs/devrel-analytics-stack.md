# DevRel Analytics Stack — Phase V Spec

> **Status**: APPROVED for auto-dispatch after Phase U converges.
> **Owner**: the operator
> **Created**: 2026-05-11
> **Updated**: 2026-05-11 (refined with n8n orchestrator, tool decisions, and work-context scope)
> **Refs**: `docs/specs/walter-council-v2.md` (Phase V)
> **Primary context use case**: `work/` (example work organization DevRel). Loaded only when cwd matches `~/work/*`.
> **Not loaded in**: `projects-personal/`, `hackathons/`, or `personal/`. Those projects do not run a DevRel pipeline.

---

## Problem

The example work organization publishes DevRel content through Postiz, the `devrel-writer` agent, and nanobanana: X threads, blog posts, YouTube scripts, LinkedIn posts, and similar material. The system **does not have a feedback loop**:

- No ingestion of performance metrics.
- No attribution for which hook, format, or publishing hour worked.
- No feedback to `devrel-writer` so it can condition new content on patterns that performed well.
- The operator manually checks each platform: X Analytics, LinkedIn dashboard, YouTube Studio, GitHub insights, and Plausible. Operational overhead grows linearly with the number of channels.

The commercial space is split:

- **Organic**: Postiz and Mixpost cover scheduling reasonably well.
- **Ads**: Metricool, Sprout, and Synter dominate. There is no strong OSS unified tool for Google, Meta, and X together.

Current result: the system **publishes but does not learn**. Time and money are spent without measurement or attribution.

---

## Non-Goals

- This is not a growth-hacking dashboard. It is a measurement and insight instrument.
- It does not publish automatically based on analytics. Final decision remains with the operator.
- It is not product analytics for unrelated projects; `projects-personal/` does not load this stack.
- It does not optimize for engagement as the primary goal. The north-star metric remains qualitative: "did this help a developer ship faster?"
- It does not replace operator judgment. It assists; it is not autopilot.

---

## Decisions

All decisions are locked for this iteration.

### Decision 1 — Architecture: n8n orchestrator + Postgres + Grafana

```text
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│   PLATFORMS     │    │ N8N WORKFLOWS    │    │   POSTGRES      │    │ VISUALIZATION    │
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

* Google Ads API also covers YouTube Ads metrics and is sufficient for read-only analytics.
```

Rationale:

- **n8n** is already in the Walter-VM stack and default profile.
- **Visual workflows** let the operator modify ingestion without touching code.
- **Native OAuth refresh**, retries, and error handling are built in.
- **Composable** with existing workflows, because n8n already orchestrates other tasks.
- **Versionable**: workflows export to JSON and can be committed.
- **Postgres** already exists on walter-vm. An append-only schema scales linearly.
- **Grafana** is already embedded in Control Tower from Phase U.

### Decision 2 — OSS-first tool selection with paid alternatives documented

Walter-OS is intended to be OSS. Each tool decision documents both the **chosen OSS path** and **paid alternatives** for forks that prefer SaaS.

#### Organic social management

| Capability | Chosen OSS self-hosted option | Paid alternatives | Decision rationale |
|---|---|---|---|
| Multi-platform scheduling and publishing | **Postiz** (30k stars, AGPL-3.0, v2.21.7 released two weeks before this spec) | Buffer, Later, Hootsuite, Metricool ($25/mo) | Already deployed, very active, covers all required platforms without paid tiers |
| Web analytics | **Plausible** (self-hosted) | Fathom, Simple Analytics | Already running |

**Mixpost was evaluated and dropped** on 2026-05-11. Mixpost Lite, the free OSS edition, only supports Facebook Pages, X, and Mastodon. Instagram, LinkedIn, YouTube, TikTok, Threads, and Bluesky require Mixpost Pro ($299 one-time). Postiz already covers all those platforms free under AGPL-3.0. There is no business case for a dual install. See `docs/operational/phase-v-tools-availability.md` for the comparison.

#### Ads management — Singer taps stack

| Capability | Chosen OSS self-hosted option | Paid alternatives | Decision rationale |
|---|---|---|---|
| Google Ads ingestion, including YouTube Ads metrics | **tap-google-ads** (Singer, AGPL-3.0) | Metricool ($25/mo), Synter ($199/mo) | Mature Python tap; YouTube Ads metrics flow through Google Ads API |
| Meta Ads + Meta Organic ingestion | **tap-facebook** (Singer, AGPL-3.0) | Same SaaS category as above | Singer ecosystem; OAuth handled |
| LinkedIn Ads ingestion | **tap-linkedin-ads** (Singer, AGPL-3.0, v2.6.0 Jan 2026); **Tier 3, paperwork-gated** | Same SaaS category as above | OSS and mature; LinkedIn Marketing Developer Platform approval is the barrier, not code |
| X Ads | **CSV manual export → n8n folder watch** | X API v2 Basic ($200/mo) | $200/mo is prohibitive for measurement-only. CSV export is a five-minute weekly operator task. |
| Google Analytics 4, if needed | **tap-google-analytics** (Singer, AGPL-3.0) | Same SaaS category as above | Optional; only needed if blog or landing-page analytics must go deeper than Plausible |

**Adspirer MCP was evaluated and dropped** on 2026-05-11. The repo `amekala/ads-mcp` is not MIT-licensed OSS; it is a thin client pointing to hosted SaaS at `mcp.adspirer.com`, with proprietary backend, no license file, and 43 stars. The initial research data point "MIT, 273 stars" was wrong. The Singer ecosystem is the genuine OSS alternative: each tap is a Python CLI that pulls platform data into a JSON stream and can be wired into n8n with an `Execute Command` node or scheduled cron plus Singer state files.

Singer integration pattern:

```text
n8n cron 6h
  → spawn tap-google-ads with state file from previous run
  → pipe JSON output to small Python script that maps Singer → analytics_events schema
  → COPY to Postgres
  → update state file (incremental sync)
```

Each tap takes roughly 4-8 hours to wire: OAuth config, state management, and schema mapping. Four taps at about six hours each is roughly twenty-four hours of ads integration, within the Phase V budget of 51-68 hours.

#### Insights + feedback loop

| Capability | Chosen OSS option | Paid alternatives | Decision rationale |
|---|---|---|---|
| Analytics insights | **`devrel-analyst` skill** (Walter-OS native) | Sprout AI, HubSpot | Custom skill understands the `devrel-writer` agent and creates a natural feedback loop |
| Anomaly detection | **n8n workflow → Telegram bot** | PagerDuty, Datadog | Reuses the Phase F alerting pipeline |

### Decision 3 — Platform tier matrix

**Tier 1 — Quick wins, week 1, about 5 hours**:

- YouTube Data API: free, immediate approval.
- Plausible: self-hosted, no API key.
- GitHub: free PAT, immediate.
- Bluesky firehose: free, no approval.

**Tier 2 — Auth-flow gated, weeks 2-3, about 10 hours of development plus waiting**:

- Google Ads API + YouTube Ads: 3-5 days for developer-token approval.
- Meta Ads + Meta Organic: 5-15 days for App Review and Business Verification.
- X through CSV path: immediate, but requires a weekly operator task.
- TikTok: 1-7 days for approval.

**Tier 3 — Paperwork heavy, week 4+, about 5 hours of development and possibly a month of waiting**:

- LinkedIn Marketing Developer Platform: approval is notoriously hard and may reject.

**Tier 4 — Deferred or skipped**:

- X API v2 paid path, only if Tier 1 and Tier 2 do not provide enough signal and budget is approved.

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
  hook          TEXT,                    -- first sentence, for hook-pattern analysis
  word_count    INTEGER,
  has_image     BOOLEAN DEFAULT false,
  has_code      BOOLEAN DEFAULT false,
  has_video     BOOLEAN DEFAULT false,
  created_by    TEXT,                    -- 'devrel-writer-agent', 'operator-manual'
  draft_path    TEXT                     -- link to the draft in wiki/devrel/drafts/
);

CREATE TABLE ad_spend_events (
  id            BIGSERIAL PRIMARY KEY,
  occurred_at   TIMESTAMPTZ NOT NULL,
  platform      TEXT NOT NULL,           -- 'google', 'meta', 'x', 'youtube' (YouTube is a Google subchannel)
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

Materialized views aggregate by week, platform, content piece, and ad campaign for fast analyst-skill queries.

---

## Context Loading Rules

Keep execution context-bounded:

- **work/**: Phase V stack loads, including `devrel-analyst`, DevRel n8n workflows, DevRel Grafana panels, and the `analytics_events` schema.
- **projects-personal/**: Phase V stack does not load. Those projects use product analytics, not DevRel analytics.
- **personal/**: Phase V stack does not load.

Apply this to `contexts/work/AGENTS.md`:

```markdown
## DevRel analytics (Phase V — work/ only)

When working on example work organization DevRel content:
- Query past performance via the `devrel-analyst` skill before drafting new content.
- The skill reads from Postgres `analytics_events` + `content_pieces`.
- Examples:
  - "Show top 5 threads by engagement last 30 days"
  - "What hook patterns worked best for Solana RPC content?"
  - "Compare CTR of threads with code vs without code"
```

---

## Acceptance Criteria

### Part A — Tier 1 ingestion, week 1

- [AC-1] n8n workflow `yt-data-api-pull` runs every 6 hours and writes `analytics_events` with `platform=youtube`.
- [AC-2] n8n workflow `plausible-pull` runs every hour and writes events with `platform=plausible`.
- [AC-3] n8n workflow `github-pull` runs every 24 hours and writes stars, traffic, and clones.
- [AC-4] n8n workflow `bluesky-stream` runs continuously and ingests post engagement.
- [AC-5] Table `analytics_events` is populated with more than 100 events after 24 hours of runtime.

### Part B — Tier 2 ingestion, weeks 2-3

- [AC-6] `tap-google-ads` is integrated in n8n through Execute Command + 6-hour cron. Workflow ingests Google Ads and YouTube Ads metrics into `ad_spend_events`. State file is managed at `~/.config/walter-os/singer-state/google-ads.json`.
- [AC-7] `tap-facebook` workflow ingests Meta Ads and Meta Organic after App Review approval.
- [AC-8] `x-csv-ingest` workflow watches `~/sync/devrel/x-analytics-exports/` for new CSV files, parses them, and writes `analytics_events`.
- [AC-9] `tiktok-pull` workflow ingests after approval through an HTTP node plus TikTok Ads API.

### Part C — Dashboard, week 4

- [AC-10] Control Tower tab "Content" in `apps/control-tower` shows top five pieces per month, optimal-hour heatmap, draft pipeline, total spend, and ROI by content.
- [AC-11] Grafana dashboard `walter-devrel-analytics.json` supports drill-down by platform and ad campaign.
- [AC-12] CLI `walter-os content stats --since 30d` prints a summary.

### Part D — Insights + feedback loop, week 4

- [AC-13] Skill `devrel-analyst` is invocable from CLI and from other agents. It queries Postgres directly.
- [AC-14] Weekly digest cron runs Mondays at 09:00 ART, commits to `~/sync/wiki/devrel/insights/weekly-<YYYY-WW>.md`, and sends a Telegram notification.
- [AC-15] Anomaly detection emits `alert_emit info` with a content-piece link when engagement is more than 3 standard deviations above the 30-day baseline.
- [AC-16] The `devrel-writer` agent in `work/` context queries `devrel-analyst` before writing new content similar to published content. Example pattern: `query_top_patterns(topic="solana-rpc", since="30d")`.

### Part E — Postiz upgrade verification, week 1

- [AC-17] Deployed Postiz version is verified against latest stable (v2.21.7 as of 2026-05-11). Upgrade if behind.
- [AC-18] Postiz analytics export endpoint is enabled, and the schema is documented for `analytics_events` ingestion through direct API or Postiz webhooks → n8n.

Mixpost dual-install was dropped after availability research; see the decision log.

**Estimated total effort**: 51-68 hours of TDD work distributed over roughly 4-6 weeks. Paperwork waits are the longest part.

---

## Operator Prereqs After Merge

Documented in `docs/operational/council-v2-prereqs.md`, section "Phase V":

- V-prereq-1: Google Ads Developer Token approved. Apply through Google Ads Manager → API Center. Expected wait: 3-5 days.
- V-prereq-2: Meta Business Verification + App Review approved for `ads_read`. Expected wait: 5-15 days.
- V-prereq-3: **LinkedIn Marketing Developer Platform approved**. Apply now, before Phase V starts. Multi-day gated and notoriously hard. Tier 3 is in scope, but the application is the blocker, not code. Apply at: https://learn.microsoft.com/en-us/linkedin/marketing/integrations
- V-prereq-4: Deployed Postiz version verified as at least v2.21.7. Upgrade with `docker compose pull && docker compose up -d` if behind.
- V-prereq-5: n8n credentials configured for each platform OAuth. Six native nodes: YouTube, Google Ads, Facebook, X, LinkedIn, GitHub. Five through HTTP node: Instagram, Threads, TikTok, Bluesky, Plausible.
- V-prereq-6: Postgres DB `walter_devrel_analytics` provisioned **with `pg_partman` and `pg_cron` extensions**. They are not available in the official `postgres:17` image. Build a custom Dockerfile at `setup/vm/postgres/Dockerfile`:
  ```dockerfile
  FROM postgres:17
  RUN apt-get update && apt-get install -y \
      postgresql-17-partman \
      postgresql-17-cron \
      && rm -rf /var/lib/apt/lists/*
  ```
  Add this to `postgresql.conf`: `shared_preload_libraries = 'pg_cron'`.
- V-prereq-7: Grafana Postgres datasource points to the new DB. This uses built-in core support; no plugin install.
- V-prereq-8: Telegram bot enabled for alerts. It already exists from Phase F.
- V-prereq-9: Singer Python env prepared on walter-vm: `pip install singer-python tap-google-ads tap-facebook tap-linkedin-ads tap-google-analytics`. Singer state directory: `~/.config/walter-os/singer-state/`, gitignored.

---

## Future

- **Walter-OS goes OSS**: this spec already documents "chosen + paid alternatives" so future forks with less OSS preference can choose Metricool, Sprout, or Synter instead.
- **Walter-OS marketplace**: paid users can skip Tier 2 and Tier 3 paperwork by using a Synter API key; Walter-OS reads from Synter into the same schema.
- **More platforms**: Reddit Ads, Pinterest, Mastodon. These are straightforward through n8n HTTP nodes.

---

## Decision Log

- 2026-05-11: n8n chosen as orchestrator over custom bash adapters. Rationale: visual control, OAuth refresh, composability, and already in stack.
- 2026-05-11, revised: **Mixpost dropped**. Tool-availability research showed Mixpost Lite only covers Facebook Pages, X, and Mastodon. Instagram, LinkedIn, YouTube, TikTok, Threads, and Bluesky are behind Mixpost Pro at $299. Postiz covers all required platforms for free under AGPL-3.0. No business case for dual install. Ref: `docs/operational/phase-v-tools-availability.md`.
- 2026-05-11, revised: **Adspirer MCP dropped**. Initial data ("MIT, 273 stars") was incorrect. The real repo (`amekala/ads-mcp`) is a thin client to a proprietary SaaS backend (`mcp.adspirer.com`), has no license file, and has 43 stars. Replaced with Singer taps stack: `tap-google-ads`, `tap-facebook`, `tap-linkedin-ads`, and `tap-google-analytics`; all AGPL-3.0, mature, and part of an active ecosystem.
- 2026-05-11: X through CSV path chosen. Rationale: $200/mo API is prohibitive for measurement-only use.
- 2026-05-11: LinkedIn deferred to Tier 3. Rationale: high paperwork barrier. Apply now because approval is a multi-day gate.
- 2026-05-11: Phase V context is `work/` only. Rationale: DevRel applies to the example work organization, not `projects-personal/` or `personal/`.
- 2026-05-11: analyst implemented as a **skill, not an agent**. Promote to a seventh agent only if proactive pattern-mining demonstrates value in month one.
- 2026-05-11: Postgres requires a custom Dockerfile with `pg_partman` and `pg_cron` extensions. They are not in the official image. Documented in V-prereq-6.

---

## Approvals Required

This spec is approved for auto-dispatch after Phase U converges. If the operator wants structural changes before dispatch, edit this file and call that out before implementation starts.
