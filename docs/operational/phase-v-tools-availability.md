# Phase V Tools — Availability Report

> Date: 2026-05-11
> Purpose: Pre-flight verification for Phase V (DevRel analytics) implementer dispatch
> Author: research subagent (Opus 4.7)

## Verdict — at a glance

| Tool | Verdict | One-line reason |
|---|---|---|
| Mixpost (Lite / CE) | YELLOW | Active + MIT, but Lite supports only **3** platforms (FB Pages, X, Mastodon). Most Phase V platforms locked behind Pro ($299) / Enterprise ($1199). |
| Postiz (already deployed) | GREEN | Very active, AGPL-3.0, latest `v2.21.7` (2026-04-27). Postiz is the better social-mgmt fit than Mixpost Lite. |
| Adspirer MCP | RED | Repo is **docs/configs only**; tool runs as hosted SaaS at `mcp.adspirer.com`. No self-host. License: proprietary. |
| tap-linkedin-ads | GREEN | v2.6.0, Singer/AGPL-3.0, last commit 2026-01-27. Python 3, stable. |
| n8n native nodes | YELLOW | 6/11 native; 5/11 require community node or HTTP fallback. |
| Postgres `pg_partman` + `pg_cron` | YELLOW | Neither ships in the official `postgres` image. Need a custom image or a community image (`qonicsinc/postgres-pgcron`, `dbsystel/postgresql-partman-container`). |
| Grafana Postgres datasource | GREEN | Built-in core plugin since Grafana 5.x. No install needed. |

---

## Tools status — detail

### Mixpost

- **Repo**: `https://github.com/inovector/mixpost` (the Laravel package — Lite source) and `https://github.com/inovector/MixpostApp` (standalone Lite app with docker-compose).
- **License**: MIT (Lite). Pro / Enterprise are commercial, separate codebases.
- **Last activity**: `inovector/mixpost` pushed 2026-03-16; `inovector/MixpostApp` pushed 2025-05-28. Mixpost Lite is being maintained, but the standalone App repo is slower-moving.
- **Stars**: mixpost 3.2k, MixpostApp 127.
- **Install**: docker-compose path via `MixpostApp` repo + community guides. `.env.example` provided. Stack = PHP/Laravel + MySQL + Redis. No license key required for Lite.
- **Platform coverage (CRITICAL)**:
  - **Lite (free)**: Facebook Pages, X, Mastodon only.
  - **Pro ($299 one-time)**: + Instagram, LinkedIn, YouTube, TikTok, Pinterest, **Threads, Bluesky**, Google Business Profile + Advanced Analytics + AI Assistant.
  - **Enterprise ($1,199 one-time)**: + Subscription mgmt + white-label.
- **Concerns**:
  1. Phase V Tier-1/Tier-2 (Instagram, LinkedIn, YouTube, TikTok, Threads, Bluesky) ALL require Pro. Lite is essentially useless for Walter-OS scope.
  2. License keys = one-time payment ($299), no annual, so it's a finite spend if you go Pro. But it's not OSS.
  3. **Postiz already covers this scope** at $0 self-hosted (AGPL-3.0). Mixpost adds nothing unless you want a second pane of glass.
- **Recommendation**: **Skip Mixpost.** Double-down on Postiz. Mixpost Lite's platform coverage is too narrow; Mixpost Pro overlaps 100% with Postiz at a cost.

### Postiz

- **Repo**: `https://github.com/gitroomhq/postiz-app`
- **License**: AGPL-3.0 (note: viral copyleft — fine for self-host, blocks redistributing as a hosted service without source).
- **Last release**: `v2.21.7` released 2026-04-27 (just two weeks ago).
- **Last commit**: 2026-05-11 (today).
- **Stars**: 30.2k.
- **Verdict**: Extremely active OSS project. Confirm current Walter-VM deployed version against `v2.21.7` before Phase V — upgrade path is via `docker-compose pull && up -d`. Postiz already supports YouTube, X, LinkedIn, Instagram, TikTok, Facebook, Threads, Bluesky, Pinterest, Reddit, Mastodon, Dribbble, Slack, Discord.
- **Recommendation**: Treat Postiz as **the** social posting layer for Phase V. Confirm version before implementer dispatch.

### Adspirer MCP

- **What the operator description suggests vs reality**: Operator expected "OSS, MIT licensed, ~273 stars".
- **What's actually in `amekala/ads-mcp`** (the public repo people are linking as "Adspirer OSS"):
  - License: **proprietary** ("See Terms of Service for usage terms"). NOT MIT.
  - Stars: 43 (not 273).
  - Last push: 2026-05-10. Active.
  - Repo contents are **docs, CLAUDE.md, plugin/extension configs only**. The MCP itself runs at `mcp.adspirer.com` as hosted SaaS. The `.mcp.json` in the repo points to `https://mcp.adspirer.com/mcp` — it's a thin client wrapper to a remote, gated service.
- **Older `amekala/adspirer-mcp-server` repo**: 4 stars, last push 2025-11-09, no license. Looks abandoned in favor of the hosted product.
- **Concerns**:
  1. Not self-hostable. Phase V would be operationally dependent on a third-party SaaS for ad-spend ingestion.
  2. Proprietary license = no ability to audit or extend the server-side code.
  3. Sending Google Ads / Meta Ads / GA4 OAuth tokens to a third party introduces a supply-chain risk surface that contradicts Walter-OS's "self-host where possible" posture.
- **Alternatives (all found in same research session)**:
  - **`irinabuht12-oss/google-meta-ads-ga4-mcp`** — MIT, 250+ tools (150 Google Ads / 80 Meta / 20 GA4). Needs deeper vet (single-author, recent repo).
  - **`google-marketing-solutions/google_ads_mcp`** — Google-published, Google Ads only.
  - **`markifact/markifact-mcp`** — 300+ tools across 5 platforms, license/repo posture needs verification.
  - **Singer/Meltano taps** — `tap-google-ads`, `tap-facebook` (Meta), `tap-google-analytics`. Mature, AGPL-3.0, scheduled-batch ingest into Postgres rather than agentic MCP. **Probably the right answer for Phase V** if the goal is analytics dashboards (not agent-driven campaign edits).
- **Recommendation**: **DROP Adspirer.** Replace with Singer taps for the analytics path (analytics_events table → materialized views → Grafana). If you specifically need agentic ad-edit capability later, do a separate vet on `irinabuht12-oss/google-meta-ads-ga4-mcp` (single-author repo — needs supply-chain audit).

### tap-linkedin-ads

- **Repo**: `https://github.com/singer-io/tap-linkedin-ads`
- **License**: AGPL-3.0.
- **Version**: `2.6.0` (in `setup.py`), last commit 2026-01-27. No GitHub Releases but versioned via setup.py.
- **Python**: Python 3 only. Deps: `backoff==2.2.1`, `requests==2.32.5`, `singer-python==6.3.0`.
- **Install**: `pip install tap-linkedin-ads` (PyPI).
- **OAuth**: LinkedIn Marketing Developer Platform — `access_token`, `accounts` (account IDs), `start_date` in `config.json`. Requires a LinkedIn Developer App with `r_ads`, `r_ads_reporting`, `rw_organization_admin` scopes (operator needs to apply for Marketing Developer Platform access — not auto-granted).
- **Minimum config example**:
  ```json
  {
    "access_token": "<linkedin_oauth_token>",
    "accounts": "1234567890,9876543210",
    "start_date": "2026-01-01T00:00:00Z",
    "user_agent": "walter-os-tap-linkedin-ads"
  }
  ```
- **Concerns**: LinkedIn Marketing Developer Platform access is **gated** — application + approval can take days/weeks. Flag this as a Tier-3 dependency upfront; operator should apply during Phase V planning, not at implementation time.

### n8n native node coverage

| Platform | Native | Community | HTTP fallback only |
|---|---|---|---|
| YouTube | Yes (`n8n-nodes-base.youtube`) | — | — |
| Google Ads | Yes | — | — |
| Facebook (Graph API + Lead Ads) | Yes (`Facebook Graph API`, `Facebook Lead Ads Trigger`) | — | — |
| Instagram | No (only via Facebook Graph API node) | `n8n-nodes-meta-publisher`, Upload-Post, PostPulse | partial |
| Threads | No | `n8n-nodes-meta-publisher`, Upload-Post | yes |
| X / Twitter | Yes (`n8n-nodes-base.twitter`) | — | — |
| TikTok | No | Upload-Post, PostPulse | yes |
| Bluesky | No | Upload-Post, PostPulse | yes (AT Protocol REST) |
| LinkedIn | Yes | — | — |
| Plausible | No | — | yes (HTTP node, simple REST) |
| GitHub | Yes | — | — |

**Summary**: 6 native (YouTube, Google Ads, Facebook, X, LinkedIn, GitHub) + 5 needing community/HTTP (Instagram, Threads, TikTok, Bluesky, Plausible).

Recommendation: For Phase V, **publish flows go through Postiz** (which already supports all 11), not through n8n native nodes. Use n8n native nodes for **ingestion** (pulling analytics: YouTube Analytics API, Google Ads reports, LinkedIn organic, GitHub traffic). For non-native ingestion (TikTok, Threads, Bluesky analytics), use n8n's HTTP node with platform-specific OAuth credentials stored as n8n credentials.

Note on community nodes: only work on self-hosted n8n, not n8n Cloud. Walter-VM is self-hosted, so this is fine.

### Postgres extensions

- **`pg_partman`** (partitioning) and **`pg_cron`** (scheduled SQL): NOT in the official `postgres:17` Alpine image.
- **Options**:
  1. **Custom Dockerfile** based on `postgres:17` + apt-install both extensions (~15 lines, fully under Walter-OS control).
  2. **`qonicsinc/postgres-pgcron`** — community image with PG 17.5 + pg_cron 1.6 + pg_partman 5.2.4. Pro: ready to go. Con: third-party trust, supply-chain audit needed.
  3. **`dbsystel/postgresql-partman-container`** — based on `bitnami/postgresql`, ships `pg_partman` + `pg_jobmon` (no `pg_cron`). PG 14–18 supported. Maintained by Deutsche Bahn Systel (more trustworthy provenance).
- **Recommendation**: Option 1 — custom Dockerfile in `walter-vm/docker/postgres/`. Pin extension versions explicitly. Add the build to walter-vm's compose stack. Avoids supply-chain trust on community images for a high-blast-radius component (your analytics DB).
- **Concern**: `pg_cron` requires `shared_preload_libraries = 'pg_cron'` and a designated DB to run cron jobs. Must be configured at server start, not via runtime SQL. Document this in the runbook.

### Grafana Postgres datasource

- **Built-in core plugin** since Grafana 5.x. No install needed.
- Configure via Grafana provisioning YAML in `walter-vm/grafana/provisioning/datasources/postgres.yaml`.
- Plugin name: `grafana-postgresql-datasource` (built-in).
- No concerns.

---

## Pre-Phase-V action items for operator

1. **Drop Mixpost from Phase V scope.** Postiz already covers everything Mixpost Lite supports plus the platforms Lite locks behind Pro. Update Phase V spec to remove Mixpost.
2. **Verify deployed Postiz version on Walter-VM** against latest `v2.21.7` (2026-04-27). Plan upgrade if >2 minor versions behind.
3. **Replace Adspirer in spec** with Singer taps (`tap-google-ads`, `tap-facebook`, `tap-google-analytics`, `tap-linkedin-ads`). Goal = analytics dashboards, not agentic campaign edits.
4. **Apply for LinkedIn Marketing Developer Platform access today** (Tier-3 blocker, multi-day approval).
5. **Build custom Postgres image** (`postgres:17` + `pg_partman` + `pg_cron`) before implementer dispatch. Add to `walter-vm/docker/postgres/Dockerfile`. Pre-commit hook should reject untested image upgrades.
6. **Decide on ad-platform agentic MCP separately** from Phase V analytics. If desired later, vet `irinabuht12-oss/google-meta-ads-ga4-mcp` (single-author repo — needs full supply-chain audit per `daily-supply-chain-audit` skill).
7. **n8n credentials inventory**: pre-create credentials for the 6 native nodes (YouTube, Google Ads, Facebook, X, LinkedIn, GitHub) before implementer starts. Non-native platforms post via Postiz, so n8n doesn't need their credentials.

---

## Risks / blockers

- **RED: Adspirer self-host expectation was wrong.** The "OSS repo" is a docs/config repo for a hosted SaaS. Phase V spec should reflect this — pivot to Singer taps OR explicitly accept third-party SaaS dependency (and budget for it).
- **YELLOW: Mixpost Lite scope mismatch.** If the operator's mental model was "Mixpost = full OSS social manager", that's wrong — Lite is 3 platforms only. Postiz already wins this comparison.
- **YELLOW: LinkedIn Marketing Developer Platform gate.** Multi-day approval. If not started early, Tier-3 LinkedIn ad ingestion will block Phase V completion.
- **YELLOW: pg_partman/pg_cron require custom image + server-start config.** Easy work, but easy to forget — document in walter-vm runbook before implementer touches Postgres.
- **GREEN: Postiz, Grafana datasource, tap-linkedin-ads, n8n native nodes** — all confirmed available with no blockers.

---

## Sources

- [inovector/mixpost (GitHub)](https://github.com/inovector/mixpost)
- [inovector/MixpostApp (GitHub)](https://github.com/inovector/MixpostApp)
- [Mixpost Pricing](https://mixpost.app/pricing)
- [gitroomhq/postiz-app (GitHub)](https://github.com/gitroomhq/postiz-app)
- [amekala/ads-mcp (GitHub) — "Adspirer" OSS](https://github.com/amekala/ads-mcp)
- [amekala/adspirer-mcp-server (GitHub)](https://github.com/amekala/adspirer-mcp-server)
- [irinabuht12-oss/google-meta-ads-ga4-mcp](https://github.com/irinabuht12-oss/google-meta-ads-ga4-mcp)
- [markifact/markifact-mcp](https://github.com/markifact/markifact-mcp)
- [google-marketing-solutions/google_ads_mcp](https://github.com/google-marketing-solutions/google_ads_mcp)
- [singer-io/tap-linkedin-ads](https://github.com/singer-io/tap-linkedin-ads)
- [n8n Credentials docs](https://docs.n8n.io/integrations/builtin/credentials/)
- [n8n integrations index](https://n8n.io/integrations/)
- [Grafana PostgreSQL datasource docs](https://grafana.com/docs/grafana/latest/datasources/postgres/)
- [qonicsinc/postgres-pgcron (Docker Hub)](https://hub.docker.com/r/qonicsinc/postgres-pgcron)
- [dbsystel/postgresql-partman-container (GitHub)](https://github.com/dbsystel/postgresql-partman-container)
