# OSS Additional Apps Evaluation — Walter-OS v0.2.x

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Branch**: `v0.2.0-walter-oss`

## Scope

Evaluation of ~75 candidate self-hosted applications for inclusion in Walter-OS
v0.2.x. Decisions follow four categories:

- **ADD-CORE** — mandatory, ships in `compose.yml` default profile
- **ADD-PROFILE** — opt-in via `--profile <name>` in compose
- **RECOMMEND-EXTERNAL** — users directed to upstream, not bundled
- **SKIP** — not recommended; reason documented

Constraints applied throughout:
- Single-operator scope; no multi-tenant or team-centric features needed
- Resource ceiling: a $7–12/mo VPS (2 vCPU / 4 GB RAM) must remain functional
  with core services running
- Maximum 8 new services total across ADD-CORE + ADD-PROFILE
- Active maintenance required (updated Docker image within 6 months)
- Prefer apps that replace a paid subscription (net cost savings for adopter)

---

## Categorization Table

| App | Category | Decision | Rationale | Effort |
|---|---|---|---|---|
| **Outline** | Knowledge/Notes | ADD-PROFILE (`knowledge`) | Best Notion-alternative for collaborative KB; Postgres-native (shared instance); OIDC-ready for Authentik integration; active maintenance; replaces $8–16/mo Notion | med |
| **Wiki.js** | Knowledge/Notes | SKIP | Requires separate DB config by default; heavier than Outline; Outline better fit | low |
| **BookStack** | Knowledge/Notes | SKIP | MySQL-only; adds a second DB engine; less agent-friendly API | low |
| **Hedgedoc** | Knowledge/Notes | SKIP | Good for real-time collaborative markdown but single-operator has no collaborators; Forgejo wikis cover the use case | low |
| **Trilium** | Knowledge/Notes | SKIP | Excellent personal KB but no team/agent API; not worth the compose slot when Outline covers shared KB | low |
| **Joplin Server** | Knowledge/Notes | SKIP | Sync server for Joplin desktop client; Syncthing already handles this pattern; no agent API | low |
| **AppFlowy** | Knowledge/Notes | SKIP | Promising but self-host story is still maturing; resource heavy; revisit v0.3.0 | low |
| **Paperless-ngx** | Document Management | ADD-PROFILE (`documents`) | Best-in-class OCR + tagging + full-text search; active community; replaces paid cloud document services; Postgres-native; agent-accessible REST API | med |
| **Docspell** | Document Management | SKIP | Solid alternative but lower adoption; Paperless-ngx wins on community size | low |
| **Mayan EDMS** | Document Management | SKIP | Enterprise scope; RAM footprint too high for target VPS | low |
| **Nextcloud** | Storage/Files | SKIP | Monolithic; RAM/CPU overhead is disproportionate for single-operator; CalDAV/CardDAV needs covered by Radicale below | med |
| **OwnCloud** | Storage/Files | SKIP | Same issues as Nextcloud; community edition increasingly limited | low |
| **Seafile** | Storage/Files | SKIP | Syncthing already covers file sync; Seafile adds no meaningful capability delta | low |
| **Filebrowser** | Storage/Files | ADD-PROFILE (`files`) | Tiny footprint (<50 MB RAM); simple web UI for volume browsing; useful for operators without direct SSH; replaces basic FTP/SFTP GUI tools | low |
| **MinIO** | Storage/Files | ADD-PROFILE (`storage`) | S3-compatible object storage; enables Restic backup targets, Paperless-ngx blob storage, and future Penpot asset storage; no RAM-heavy alternative | med |
| **Immich** | Photos | SKIP | Excellent product but requires dedicated GPU or heavy CPU for AI tagging; 2–4 GB RAM baseline; inappropriate for $7 VPS | high |
| **PhotoPrism** | Photos | SKIP | Same GPU/RAM concern as Immich | high |
| **LibrePhotos** | Photos | SKIP | Less active maintenance than Immich; same resource concerns | med |
| **Authentik** | Auth/SSO | ADD-PROFILE (`auth`) | Best modern OSS SSO; OIDC + SAML + MFA; ~300 MB RAM baseline; integrates cleanly with Caddy via forward auth; unlocks SSO across Plane, Forgejo, Outline, n8n; replaces $3–8/user/mo Okta/Auth0 | med |
| **Authelia** | Auth/SSO | SKIP | Good but OIDC provider support narrower than Authentik; Authentik wins for the breadth needed | low |
| **Keycloak** | Auth/SSO | SKIP | Enterprise scope; 512 MB RAM minimum; Java stack; overkill for single-operator | low |
| **Pomerium** | Auth/SSO | SKIP | Zero-trust proxy role already covered by Caddy + WireGuard/Headscale | low |
| **Linkwarden** | Bookmarks | ADD-PROFILE (`knowledge`) | Active development; auto-archives pages locally (Wayback insurance); tags + full-text; Postgres-native; replaces Pocket/Raindrop ($3–5/mo); bundles well with Outline in same profile | low |
| **Karakeep** | Bookmarks | SKIP | Good read-later UX but lower adoption; Linkwarden covers the use case with broader features | low |
| **Wallabag** | Bookmarks | SKIP | Older project; PHP stack adds maintenance burden; Linkwarden preferred | low |
| **Shiori** | Bookmarks | SKIP | Minimal footprint but no archive capability; Linkwarden wins on value | low |
| **Listmonk** | Email/Newsletters | ADD-PROFILE (`devrel`) | Already fits the DevRel profile alongside Postiz; replaces Mailchimp ($13+/mo); Go binary, tiny footprint; Postgres-native; perfect for newsletter operations | low |
| **Mailcow** | Email/Newsletters | RECOMMEND-EXTERNAL | Full mail stack is outside Walter-OS scope; operating your own MX is a significant ops commitment; point to Mailcow upstream for operators who need it | high |
| **Postfix + Dovecot** | Email/Newsletters | RECOMMEND-EXTERNAL | Same reasoning as Mailcow; DIY mail is out of scope | high |
| **Mailpit** | Email/Newsletters | SKIP | Dev SMTP catcher only; no production value; developers use it locally, not in an always-on VPS | low |
| **AdGuard Home** | DNS/Network | ADD-PROFILE (`network`) | DNS-level ad blocking + filtering + query logging; replaces Pi-hole with better UI; minimal RAM; useful for homelab context where the VPS also serves DNS | low |
| **Pi-hole** | DNS/Network | SKIP | AdGuard Home is a strict improvement in UX and maintenance | low |
| **Unbound** | DNS/Network | SKIP | Recursive resolver useful in combination with AdGuard Home, but adds complexity; recommend operators layer it manually if needed | low |
| **Radicale** | Calendar/Contacts | ADD-PROFILE (`personal`) | CalDAV + CardDAV in a 10 MB Python package; replaces Google Contacts/Calendar; no DB dependency; integrates with iOS/Android natively; low maintenance | low |
| **Baikal** | Calendar/Contacts | SKIP | PHP stack; Radicale is lighter and better maintained | low |
| **Sogo** | Calendar/Contacts | SKIP | Full groupware; far more than single-operator needs | low |
| **Ntfy** | Notifications | ADD-CORE | 20 MB RAM; HTTP-first push notifications; replaces Telegram-only alerting with a provider-agnostic channel; Walter Council alert_emit can target ntfy topics; perfectly sized for core profile | low |
| **Gotify** | Notifications | SKIP | Ntfy wins on HTTP simplicity and multi-subscriber support without client coupling | low |
| **Vaultwarden** | Password Manager | ADD-PROFILE (`personal`) | Bitwarden-compatible; replaces $3–10/mo 1Password/Bitwarden; near-zero footprint; the spec already references it as the secrets truth for personal data | low |
| **Passbolt** | Password Manager | SKIP | Team-oriented; single-operator has no sharing use case; heavier stack | med |
| **Vikunja** | Project/Task | SKIP | Plane already covers task/PM; redundant | low |
| **Focalboard** | Project/Task | SKIP | Same; Plane is the canonical PM tool | low |
| **Kanboard** | Project/Task | SKIP | Same | low |
| **Tracks** | Project/Task | SKIP | GTD-specific; niche; not worth the slot | low |
| **Coolify** | Deploy/PaaS | SKIP | Walter-OS IS the PaaS layer; Coolify would replace compose + Caddy, not complement them; philosophical conflict | low |
| **Dokploy** | Deploy/PaaS | SKIP | Same reasoning as Coolify | low |
| **CapRover** | Deploy/PaaS | SKIP | Same reasoning | low |
| **Portainer** | Deploy/PaaS | RECOMMEND-EXTERNAL | Useful Docker management UI for operators unfamiliar with CLI; but it is a Walter-OS management peer, not a tenant service; point to Portainer CE upstream | low |
| **Stirling-PDF** | PDF/Documents | ADD-PROFILE (`documents`) | Comprehensive PDF tooling (merge, split, OCR, compress, sign); ~200 MB RAM; no cloud PDF tools needed; bundles naturally in `documents` profile with Paperless-ngx | low |
| **Gotenberg** | PDF/Documents | SKIP | API-only PDF generator; useful for developers building apps, not for a personal operator stack | low |
| **pgAdmin** | Database UI | SKIP | Grafana + Metabase already provide data visibility; pgAdmin is redundant and heavy | low |
| **Adminer** | Database UI | RECOMMEND-EXTERNAL | Single PHP file; useful for debugging but not worth a compose slot; operators can spin it up ad-hoc with `docker run` | low |
| **NocoDB** | Database UI | SKIP | Airtable alternative needs its own use case; no clear fit given Plane + Metabase already present | low |
| **Baserow** | Database UI | SKIP | Same as NocoDB | low |
| **Statusnook** | Status Pages | ADD-PROFILE (`network`) | Simple public status page; complements Uptime Kuma (internal) with public-facing status; Go binary, tiny; operators running public services need this; bundles in `network` profile | low |
| **Cachet** | Status Pages | SKIP | PHP/MySQL; Statusnook is strictly lighter | low |
| **Gatus** | Status Pages | SKIP | Overlaps Uptime Kuma (already in core); Statusnook covers the public-page gap without duplication | low |
| **Gitea** | Code/Dev | SKIP | Forgejo is a Gitea fork with better governance; redundant | low |
| **code-server** | Code/Dev | SKIP | VS Code in browser is useful but RAM-heavy; operators who need it have Cursor locally; not a Walter-OS concern | med |
| **Gitpod self-hosted** | Code/Dev | SKIP | Infrastructure scope far beyond Walter-OS VPS target | high |
| **Sourcegraph** | Code/Dev | SKIP | Multi-repo code search; overkill for personal operator scale; RAM footprint prohibitive | high |
| **Open WebUI** | AI/ML | ADD-PROFILE (`assistant`) | Best Ollama/LiteLLM UI; replaces ChatGPT web interface; bundles naturally in `assistant` profile alongside OpenClaw; Postgres-native; active development | low |
| **Pipelines** | AI/ML | SKIP | Open WebUI extension; include only if Open WebUI is added (automatic) | low |
| **LangFuse** | AI/ML | ADD-PROFILE (`assistant`) | LLM observability + prompt management + evals; replaces commercial LangSmith ($39+/mo); Postgres-native; integrates directly with LiteLLM via callback; bundles in `assistant` profile | med |
| **Phoenix Arize** | AI/ML | SKIP | Heavier than LangFuse; LangFuse covers the use case better for single-operator | med |
| **HelixML** | AI/ML | SKIP | Fine-tuning infrastructure; GPU required; out of scope for VPS target | high |
| **Duplicati** | Backup/Sync | SKIP | Syncthing + Restic already cover sync and backup; Duplicati adds no capability delta | low |
| **Borgbackup** | Backup/Sync | RECOMMEND-EXTERNAL | Excellent deduplicating backup; point operators to Borgbase upstream; no Docker compose slot needed (runs as a cron job, not a service) | low |
| **InfluxDB** | Time-series/IoT | SKIP | Prometheus already covers time-series; InfluxDB only wins for IoT sensor ingestion at volume, not a Walter-OS use case | med |
| **Telegraf** | Time-series/IoT | SKIP | Data collector for InfluxDB; follows InfluxDB decision | low |
| **Home Assistant** | Time-series/IoT | RECOMMEND-EXTERNAL | Legitimate use case for homelab operators; but it is a full platform, not a Walter-OS service; point to HA supervised install docs | high |
| **Node-RED** | Time-series/IoT | SKIP | n8n already covers automation; Node-RED is more IoT-oriented; not a priority given n8n is in core | low |

---

## Top 5 ADD-PROFILE Recommendations for v0.2.x

These five were selected by maximizing (paid-subscription replacement + agent
integration potential + resource efficiency) against (integration effort + maintenance
burden). All assume Phase W completion (all-in-one compose, profile pattern).

---

### 1. `--profile knowledge` — Outline + Linkwarden

**Why:** Replaces Notion ($8–16/mo) and Pocket/Raindrop ($3–5/mo) in a single
profile. Outline has a fully documented REST API that Walter Council agents can
write to (lesson capture, runbook generation, meeting notes). Linkwarden
auto-archives bookmarks locally, removing the "link rot" problem for a
researcher-pattern operator. Both use the existing Postgres instance.

**Compose additions:**

```yaml
# profiles: [knowledge]
outline:
  image: outlinewiki/outline:latest
  profiles: [knowledge]
  env_file: .env
  environment:
    DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/outline
    URL: https://outline.${WALTER_DOMAIN}
    SECRET_KEY: ${OUTLINE_SECRET_KEY}
    UTILS_SECRET: ${OUTLINE_UTILS_SECRET}
    REDIS_URL: redis://redis:6379
  depends_on: [postgres, redis]
  networks: [walter]

linkwarden:
  image: ghcr.io/linkwarden/linkwarden:latest
  profiles: [knowledge]
  environment:
    DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/linkwarden
    NEXTAUTH_SECRET: ${LINKWARDEN_SECRET}
    NEXTAUTH_URL: https://links.${WALTER_DOMAIN}
  depends_on: [postgres]
  volumes:
    - linkwarden-data:/data/data
  networks: [walter]
```

**Caddy routes:**
```
outline.{$WALTER_DOMAIN} { reverse_proxy outline:3000 }
links.{$WALTER_DOMAIN}   { reverse_proxy linkwarden:3000 }
```

**Storage estimate:** Outline: ~200 MB DB growth/year for active use.
Linkwarden: ~1–5 GB/year for archived pages. Two small volumes.

**Walter Council integration:** Tech-writer agent gains an Outline write target
for auto-generated runbooks. `knowledge-capture` skill (backlog) can push lessons
to Outline pages tagged by project. No new skill required for v0.2.x; integration
is REST-based and configurable via n8n workflow.

---

### 2. `--profile documents` — Paperless-ngx + Stirling-PDF

**Why:** Replaces paid cloud document storage and online PDF tools. Paperless-ngx
turns a folder of scans into a searchable, tagged archive with OCR. Stirling-PDF
handles the conversion/manipulation side (merge, compress, sign). Combined, they
eliminate the need for Adobe Acrobat ($13/mo) and any cloud document service for
personal or small-business operators. Paperless REST API is agent-accessible.

**Compose additions:**

```yaml
paperless:
  image: ghcr.io/paperless-ngx/paperless-ngx:latest
  profiles: [documents]
  environment:
    PAPERLESS_DBHOST: postgres
    PAPERLESS_DBNAME: paperless
    PAPERLESS_DBUSER: ${POSTGRES_USER}
    PAPERLESS_DBPASS: ${POSTGRES_PASSWORD}
    PAPERLESS_REDIS: redis://redis:6379
    PAPERLESS_URL: https://docs.${WALTER_DOMAIN}
    PAPERLESS_ADMIN_USER: ${WALTER_INITIAL_USER}
    PAPERLESS_ADMIN_PASSWORD: ${WALTER_INITIAL_PASSWORD}
    PAPERLESS_TIME_ZONE: ${WALTER_TIMEZONE}
  volumes:
    - paperless-data:/usr/src/paperless/data
    - paperless-media:/usr/src/paperless/media
    - paperless-export:/usr/src/paperless/export
    - paperless-consume:/usr/src/paperless/consume
  depends_on: [postgres, redis]
  networks: [walter]

stirling-pdf:
  image: frooodle/s-pdf:latest
  profiles: [documents]
  volumes:
    - stirling-data:/configs
  networks: [walter]
```

**Caddy routes:**
```
docs.{$WALTER_DOMAIN}   { reverse_proxy paperless:8000 }
pdf.{$WALTER_DOMAIN}    { reverse_proxy stirling-pdf:8080 }
```

**Storage estimate:** Depends entirely on document volume. Budget 5–20 GB for
active use. Paperless recommends dedicated volume; include in Restic backup scope.

**Walter Council integration:** Janitor agent can push files to the Paperless
consume directory for auto-ingestion. An n8n workflow watching the consume folder
is the zero-code integration path. No new skill required for v0.2.x.

---

### 3. `--profile auth` — Authentik

**Why:** The current stack has no SSO layer. Every service manages its own
credentials. Authentik adds OIDC + SAML + MFA in one service and integrates with
Caddy via forward_auth. Once in place, Forgejo, Outline, Plane, n8n, Grafana, and
LangFuse all get unified login. Eliminates per-service password management; replaces
Auth0 ($0–240+/mo depending on MAUs). Single most impactful infrastructure addition
for OSS operators who run several services.

**Compose addition:**

```yaml
authentik-server:
  image: ghcr.io/goauthentik/server:latest
  profiles: [auth]
  command: server
  environment:
    AUTHENTIK_REDIS__HOST: redis
    AUTHENTIK_POSTGRESQL__HOST: postgres
    AUTHENTIK_POSTGRESQL__NAME: authentik
    AUTHENTIK_POSTGRESQL__USER: ${POSTGRES_USER}
    AUTHENTIK_POSTGRESQL__PASSWORD: ${POSTGRES_PASSWORD}
    AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
  depends_on: [postgres, redis]
  networks: [walter]

authentik-worker:
  image: ghcr.io/goauthentik/server:latest
  profiles: [auth]
  command: worker
  environment:
    AUTHENTIK_REDIS__HOST: redis
    AUTHENTIK_POSTGRESQL__HOST: postgres
    AUTHENTIK_POSTGRESQL__NAME: authentik
    AUTHENTIK_POSTGRESQL__USER: ${POSTGRES_USER}
    AUTHENTIK_POSTGRESQL__PASSWORD: ${POSTGRES_PASSWORD}
    AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
  depends_on: [postgres, redis]
  networks: [walter]
```

**Caddy routes:**
```
auth.{$WALTER_DOMAIN} { reverse_proxy authentik-server:9000 }
```

Caddy forward_auth snippet (added to each protected service):
```
forward_auth authentik-server:9000 {
  uri /outpost.goauthentik.io/auth/caddy
  copy_headers X-authentik-username X-authentik-groups X-authentik-email
}
```

**Storage estimate:** ~50 MB DB growth/year for audit logs and user data.

**Walter Council integration:** Authentik's OIDC tokens can be used by Council
agents that call service APIs (Forgejo, Plane) as the authenticated identity. Long-
term: the `agent-identity` skill (backlog) would provision a machine account per
agent in Authentik. No new skill required for v0.2.x.

---

### 4. `--profile assistant` (extension) — Open WebUI + LangFuse

**Why:** OpenClaw (already in core assistant profile) is Walter-OS-specific. Open
WebUI gives operators a generic ChatGPT-equivalent UI over LiteLLM with no coding.
LangFuse closes the observability gap on LLM spend and prompt quality — currently
there is no per-prompt visibility beyond LiteLLM aggregates. Together they make the
`assistant` profile genuinely production-grade. LangFuse integrates with LiteLLM
via a single callback URL, requiring no code changes.

**Compose additions (extend existing `assistant` profile):**

```yaml
open-webui:
  image: ghcr.io/open-webui/open-webui:main
  profiles: [assistant]
  environment:
    OPENAI_API_BASE_URL: http://litellm:4000/v1
    OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
    WEBUI_URL: https://chat.${WALTER_DOMAIN}
  volumes:
    - open-webui-data:/app/backend/data
  networks: [walter]

langfuse-server:
  image: ghcr.io/langfuse/langfuse:latest
  profiles: [assistant]
  environment:
    DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/langfuse
    NEXTAUTH_SECRET: ${LANGFUSE_SECRET}
    NEXTAUTH_URL: https://langfuse.${WALTER_DOMAIN}
    SALT: ${LANGFUSE_SALT}
  depends_on: [postgres]
  networks: [walter]
```

**Caddy routes:**
```
chat.{$WALTER_DOMAIN}     { reverse_proxy open-webui:8080 }
langfuse.{$WALTER_DOMAIN} { reverse_proxy langfuse-server:3000 }
```

**Storage estimate:** Open WebUI: ~100 MB for conversation history. LangFuse:
grows with trace volume; budget 500 MB/year for active use.

**Walter Council integration:** LangFuse receives traces from LiteLLM via the
callback URL (env var `LITELLM_SUCCESS_CALLBACK=langfuse`). The `ai-spend-tripwire`
skill gains a second data source alongside LiteLLM's `/spend` endpoint. No new
skill required for v0.2.x.

---

### 5. `--profile personal` — Vaultwarden + Radicale

**Why:** These two together replace two major Google/Apple dependencies (Contacts,
Calendar) and a paid password manager (1Password/Bitwarden at $3–10/mo). Both are
near-zero resource consumers. Vaultwarden is already referenced in AGENTS.md as
the canonical secrets source for personal data — making it a managed service in
the stack closes the gap between "referenced" and "deployed". Radicale (CalDAV +
CardDAV) integrates natively with iOS, Android, macOS, and Thunderbird.

**Compose additions:**

```yaml
vaultwarden:
  image: vaultwarden/server:latest
  profiles: [personal]
  environment:
    DOMAIN: https://vault.${WALTER_DOMAIN}
    ADMIN_TOKEN: ${VAULTWARDEN_ADMIN_TOKEN}
  volumes:
    - vaultwarden-data:/data
  networks: [walter]

radicale:
  image: tomsquest/docker-radicale:latest
  profiles: [personal]
  volumes:
    - radicale-data:/data
    - radicale-config:/config
  networks: [walter]
```

**Caddy routes:**
```
vault.{$WALTER_DOMAIN} { reverse_proxy vaultwarden:80 }
dav.{$WALTER_DOMAIN}   { reverse_proxy radicale:5232 }
```

**Storage estimate:** Vaultwarden: <50 MB even at heavy use. Radicale: <10 MB
for contacts + calendars. Negligible backup impact.

**Walter Council integration:** No agent integration needed. These are operator-
facing services, not agent-facing. Vaultwarden's CLI (`rbw`) can be used by agents
to retrieve secrets if the operator configures it, but that is a v0.3.0 concern.

---

## Phase-out / Replacement Notes

### Authentik over Caddy basic_auth

Current pattern: each service either has its own login or uses Caddy basic_auth
passthrough. Adding `--profile auth` (Authentik) does not force migration, but
operators who add it should migrate service-level auth over time. No existing
service is removed; authentication is additive. Caddy forward_auth blocks
unauthenticated access at the proxy layer.

### Ntfy over Telegram-only alerting

Ntfy is recommended as ADD-CORE. It does not replace Telegram as an alert
destination — it adds an HTTP-native push channel. The `alert_emit` script gains
an `ntfy` tier alongside the existing Telegram tier. Both coexist. No migration
needed; the pattern is additive.

### Listmonk added to existing `devrel` profile

Listmonk slots into the existing `--profile devrel` (Postiz + Metabase) without
creating a new profile. Add it to the compose block for that profile. No existing
service is replaced.

### Open WebUI alongside OpenClaw

Both live in `--profile assistant`. OpenClaw is Walter-OS-specific (Council-
integrated personal assistant). Open WebUI is a general-purpose LiteLLM frontend.
They serve different mental modes (Council-mediated vs raw chat) and are not
redundant.

---

## Services Added to Core (ADD-CORE)

| Service | RAM estimate | Reason |
|---|---|---|
| **Ntfy** | 20 MB | Alert channel decoupled from Telegram; HTTP-native; fits on every VPS |

Total new core services: **1**

## Services Added by Profile

| Profile | Services | Combined RAM estimate |
|---|---|---|
| `knowledge` | Outline + Linkwarden | ~400 MB |
| `documents` | Paperless-ngx + Stirling-PDF | ~600 MB |
| `auth` | Authentik (server + worker) | ~500 MB |
| `assistant` (extension) | Open WebUI + LangFuse | ~500 MB |
| `personal` | Vaultwarden + Radicale | ~80 MB |
| `devrel` (extension) | Listmonk | ~50 MB |
| `network` | AdGuard Home + Statusnook | ~100 MB |

No single operator is expected to run all profiles simultaneously on a $7 VPS.
The typical personal operator runs core + personal + knowledge (~900 MB total new
overhead). The typical DevRel/work operator runs core + devrel + assistant + auth
(~1.1 GB new overhead).

---

## Open Questions

- Redis is implied by Outline, Authentik, and Paperless-ngx. A shared Redis
  instance should be added to core compose (not profile-gated) to avoid each
  profile adding its own. Should Redis move to ADD-CORE silently or be made
  explicit in the W-1 spec revision?
- Ntfy ADD-CORE designation means the `alert_emit` function in
  `scripts/agents/lib/alerts.sh` needs updating. Is that a W-1 follow-up task or
  a new tiny task in the current branch?
- LangFuse v2 changed its architecture to a worker + web split (similar to
  Authentik). The compose block above reflects v1; verify image tag before
  implementation.

## References

- `docs/specs/phase-w-1-docker-compose.md` — all-in-one compose spec (profiles pattern)
- `docs/specs/phase-w-overview.md` — Phase W scope
- `docs/specs/phase-w-5-depersonalization.md` — overlay strategy
- `docs/specs/walter-council-v2.md` — existing service inventory
- `docs/specs/devrel-analytics-stack.md` — existing devrel profile context
