# Walter Council v2 — Operator Prerequisites

> Manual steps the **operator** must complete outside the implementer flow, phase
> by phase. The implementer cannot create these resources alone because they
> require UI access, elevated permissions, or naming decisions. The related phases
> cannot land safely until their prerequisites are complete.
>
> **Refs**: `docs/specs/walter-council-v2.md`, `docs/specs/walter-council-v2.plan.md`

---

## Status Board

| Phase | Prereqs done? | Notes |
|---|---|---|
| F (foundation) | [ ] | Grafana datasource + Prometheus scrape config |
| M (memory) | [ ] | Wiki normalization manual review + Postgres `lessons` DB |
| R (recovery) | [ ] | Plane state `awaiting-resume` |
| T (trust + consensus) | [ ] | Plane states `awaiting-consensus`, `awaiting-human` |
| U (Control Tower) | [ ] | Tailscale ACL + Postgres `control_tower` DB + session secret |

Mark each `[ ]` as `[x]` as it is completed.

---

## Phase F — Foundation

### F-prereq-1: Verify Prometheus + Grafana stack

```bash
docker compose ps | grep -E "prometheus|grafana"
# Both services should be Up.
```

If they are not running, start them before the implementer begins T-3:

```bash
docker compose up -d prometheus grafana
```

### F-prereq-2: Grafana datasource — Prometheus

UI: `https://grafana.walter.lan` → Configuration → Data sources → Add data source → Prometheus

- URL: `http://prometheus:9090`
- Access: Server (default)
- Name: `walter-prometheus`

The dashboard provisioned by T-4 assumes the datasource is named `walter-prometheus`. If a different name is used, record it here.

### F-prereq-3: Prometheus scrape config

Edit `prometheus/prometheus.yml`, mounted as a volume, to add:

```yaml
scrape_configs:
  - job_name: 'walter-council'
    static_configs:
      - targets: ['node-exporter:9100']
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'walter_council_.*'
        action: keep
```

Reload Prometheus:

```bash
docker compose exec prometheus kill -HUP 1
```

### F-prereq-4: LiteLLM `/spend/tags` endpoint enabled

```bash
curl -s http://litellm:4000/spend/tags -H "Authorization: Bearer $LITELLM_MASTER_KEY"
# Should return JSON, not 404.
```

If it returns 404, add this to `litellm/config.yaml`:

```yaml
general_settings:
  store_model_in_db: true
  enable_spend_tracking: true
```

Then restart LiteLLM.

---

## Phase M — Memory + Intelligence

### M-prereq-1: Wiki normalization sanity check

Before T-M-0, the operator must manually review pages the normalizer marks as `needs review`. The script lists them in:

`~/.config/walter-os/wiki-normalize-report.txt`

Wait for the normalizer to run once, review the report, and approve the normalizer commit.

### M-prereq-2: AGENTS.md amendment review

T-M-1 adds a "Wiki integrity" section to the global `AGENTS.md`. The exact text is in the spec under "Required AGENTS.md amendments".

The operator must **review the PR** that includes this amendment before merge. It changes the global agent contract and applies to every agent and project.

### M-prereq-3: Postgres database `walter_lessons`

```bash
# On walter-vm:
docker compose exec postgres psql -U postgres -c "CREATE DATABASE walter_lessons;"
docker compose exec postgres psql -U postgres -c "CREATE USER lessons_writer WITH ENCRYPTED PASSWORD 'CHANGE_ME';"
docker compose exec postgres psql -U postgres -c "GRANT ALL ON DATABASE walter_lessons TO lessons_writer;"
```

Provision `LESSONS_DB_URL` in Infisical (`walter-os` workspace, `dev` env):

```text
LESSONS_DB_URL=postgresql://lessons_writer:<password>@postgres:5432/walter_lessons
```

### M-prereq-4: Embedding model availability

LiteLLM config must expose `nomic-embed-text` or an equivalent embedding model:

```yaml
model_list:
  - model_name: walter-embed
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://ollama-standby-node:11434
```

Verify:

```bash
curl http://litellm:4000/v1/embeddings -d '{"model": "walter-embed", "input": "test"}'
```

If no embedding model is available, T-10 will fail.

### M-prereq-5: Re-run install.sh to activate wiki-validator hook

`wiki-validator.sh` is registered as a `PreToolUse` hook in Claude Code for `Write|Edit` tools. To activate it, rerun the installer:

```bash
cd /path/to/walter-os
./install.sh --upgrade
```

This merges the hook into `~/.claude/settings.json`. Without this step, agents can write wiki pages with missing frontmatter and validation will not fire.

Verify after install:

```bash
jq '.hooks.PreToolUse' ~/.claude/settings.json | grep wiki-validator
```

---

## Phase R — Resilience

### R-prereq-1: Plane custom state `awaiting-resume`

Plane currently has default states: `backlog`, `todo`, `in-progress`, `done`, `cancelled`. Phase R needs an intermediate state for tasks abandoned by one agent and resumed by another instance.

UI Plane: workspace `walter-os` → project `agents` → States → Add State:

- Name: `awaiting-resume`
- Group: `started`
- Color: `#f59e0b` (amber)

Without this state, T-19 (zombie watchdog) cannot re-enqueue tasks correctly.

### R-prereq-2: Watchdog cron permissions

T-20 installs a cron. On walter-vm, ensure the `walter` user can run cron:

```bash
ssh walter-vm "crontab -l" # should not return "you are not allowed"
```

If cron is blocked, edit `/etc/cron.allow` and add `walter`.

---

## Phase T — Trust + Controls + Consensus

### T-prereq-1: Plane custom state `awaiting-consensus`

UI Plane: workspace `walter-os` → project `agents` → States → Add State:

- Name: `awaiting-consensus`
- Group: `unstarted`
- Color: `#8b5cf6` (violet)

T-35 fails without this state.

### T-prereq-2: Plane custom state `awaiting-human`

UI Plane: same path as above:

- Name: `awaiting-human`
- Group: `unstarted`
- Color: `#ef4444` (red)

Used for tasks that consensus rejects and escalates to the operator.

### T-prereq-3: Initial trust-tiers.yml values

T-25 creates the file. The operator must **review and sign off** on the initial values before commit:

- triage: `medium`
- researcher: `medium`
- coder: `medium`
- reviewer: `high`
- janitor: `low`
- liaison: `low`

Any adjustments should happen before the commit. Afterward, changes are governed and require another PR.

### T-prereq-4: Consensus mode dry-run

Before enabling `walter-os mode consensus on` in production, run the T-36c end-to-end bats test:

```bash
cd walter-os && bats tests/agents/consensus-mode.bats
```

It must pass 100%. If it fails, do not enable consensus mode until it is fixed.

---

## Phase U — Control Tower

### U-prereq-1: Postgres database `walter_control_tower`

```bash
docker compose exec postgres psql -U postgres -c "CREATE DATABASE walter_control_tower;"
```

### U-prereq-2: Session secret in Infisical

Generate:

```bash
openssl rand -hex 32
```

Store it in Infisical workspace `walter-os`, env `dev`, as `CONTROL_TOWER_ADMIN_TOKEN`.

### U-prereq-3: Tailscale ACL

Control Tower is Tailscale-only. Verify Funnel is not exposing the port:

```bash
ssh walter-vm "sudo tailscale funnel status"
```

If `tailscale funnel status` shows public exposure, disable Funnel. Use
`tailscale serve status` only to confirm tailnet-only access.

ACL fragment in Headscale on walter-vm:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["${WALTER_ADMIN_TAILSCALE_USER}@"],
      "dst": ["tag:walter-vm:3000"]
    }
  ]
}
```

### U-prereq-4: Grafana embed permission

T-40 embeds Grafana panels in Control Tower. Grafana must allow iframe embedding:

UI Grafana → Configuration → Settings → Embed mode → enable iframe embedding from `walter-vm:3000`.

Without this, panels render blank with a CORS error.

### U-prereq-5: Operator account creation in Control Tower

The first time the operator opens Control Tower through Tailscale, the system asks them to create a profile. This is not real auth; it stores UI preferences such as layout, theme, and default views.

This is a one-time manual step per device.

---

## Phase V — DevRel Analytics Stack

### V-prereq-1: Google Ads Developer Token

Apply at: Google Ads Manager → Tools → API Center → Developer Token Request.
Approval usually takes about 3-5 business days for a test account or 2-4 weeks for production approval.

```text
Status: APPLY NOW — blocker for tap-google-ads (AC-6)
```

### V-prereq-2: Meta Business Verification + App Review

Apply at: https://developers.facebook.com → Your App → App Review → Permissions → `ads_read`

Also requires Meta Business Verification, which can take 5-15 days.

```text
Status: APPLY NOW — blocker for tap-facebook (AC-7)
```

### V-prereq-3: LinkedIn Marketing Developer Platform

Apply at: https://learn.microsoft.com/en-us/linkedin/marketing/integrations

Requires a LinkedIn Company Page and a LinkedIn developer app with Marketing API access.
Approval is slow, can take multiple weeks, and may reject without a clear reason.

```text
Status: APPLY NOW — Tier 3, blocker for tap-linkedin-ads
Note: This is the longest blocker. Apply immediately even if code is not ready.
```

### V-prereq-4: Postiz version verification

```bash
# On walter-vm:
docker inspect postiz | jq -r '.[0].Config.Image'
# Must show: ghcr.io/gitroomhq/postiz-app:v2.21.7 or newer

# If behind, upgrade:
cd setup/walter-host/services/postiz
docker compose pull && docker compose up -d postiz
```

See `setup/walter-host/services/postiz/UPGRADE.md` for details.

### V-prereq-5: n8n credentials configuration

In n8n UI, create these credentials under Settings → Credentials:

| Name | Type | For |
|---|---|---|
| `YouTube OAuth2` | YouTube OAuth2 API | yt-data-api-pull |
| `Analytics Postgres` | PostgreSQL | All workflows → analytics DB (port 5433) |
| `Plausible API Key` | HTTP Header Auth (`Authorization: Bearer <key>`) | plausible-pull |
| `GitHub PAT` | GitHub API | github-pull (`repo:traffic` scope required) |
| `Bluesky Session Token` | HTTP Header Auth | bluesky-stream (optional for public content) |
| `Walter Telegram Bot` | Telegram API | alert notifications |
| `Google Ads OAuth2` | after V-prereq-1 approval | google-ads-pull |
| `Meta App Token` | after V-prereq-2 approval | meta-ads-pull |

### V-prereq-6: Postgres analytics DB

```bash
# On walter-vm, build and start analytics Postgres:
cd setup/walter-host/services/postgres
docker compose build
ANALYTICS_PG_PASS=<generate-strong-password> docker compose up -d

# Verify migrations ran:
docker compose exec postgres-analytics psql -U analytics -d walter_devrel_analytics \
  -c "\dt" | grep -E "analytics_events|content_pieces|ad_spend_events"
```

The custom Dockerfile adds `pg_partman` and `pg_cron`.
`postgresql.conf` sets `shared_preload_libraries = 'pg_cron,pg_partman_bgw'`.

Store the password in Infisical `walter-os` workspace, env `dev`:

```text
ANALYTICS_PG_PASS=<generated>
ANALYTICS_DB_URL=postgresql://analytics:<pass>@localhost:5433/walter_devrel_analytics
```

### V-prereq-7: Grafana datasource for analytics DB

After V-prereq-6 is running:

1. Ensure `postgres-analytics` is on the same Docker network as `grafana`.
   - Either join `obs_net` from `postgres-analytics`, or use `host.docker.internal`.
   - Update `datasources.yml` URL if needed. Current expected value: `postgres-analytics:5432`.
2. Restart Grafana to pick up the provisioned datasource:
   ```bash
   docker compose restart grafana
   ```
3. Verify: Grafana → Configuration → Data Sources → "Walter DevRel Analytics" shows "OK".

### V-prereq-8: Telegram bot for alerts

Already exists from Phase F. Verify:

```bash
docker compose exec n8n wget -qO- \
  "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/getMe"
```

If missing, create a new bot through BotFather and store credentials in Infisical.

### V-prereq-9: Singer Python environment on walter-vm

```bash
# On walter-vm:
pip install singer-python tap-google-ads tap-facebook tap-linkedin-ads tap-google-analytics

# Verify:
tap-google-ads --help
tap-facebook --help

# Create state and config dirs:
mkdir -p ~/.config/walter-os/singer-state ~/.config/walter-os/singer-configs

# Run prereqs check:
cd setup/walter-host/singer
bash check-prereqs.sh
```

---

## Global Rollback Plan

If any phase introduces a severe regression:

1. `git revert <merge-commit>` on `main`.
2. Reopen the `feature/council-v2-<phase>` branches for fixes.
3. If the problem affects the current Council runtime, pause all agents:
   ```bash
   walter-os agents pause --all
   ```
4. Investigate with `walter-os agents status --verbose` and logs in `~/sync/agent-memory/audit/<date>.log`.
5. After the fix, smoke test on `staging` before promoting again.

The `branch-flow-guard.sh` and `approval-gate.sh` hooks remain active during rollback. They provide a safety net if the revert accidentally reintroduces a destructive commit.

---

## How This Document Evolves

- Each PR that lands a phase must mark the corresponding status-board row as `[x]`.
- Prereqs discovered during implementation are added here, not in the spec. The spec is the contract; this document is operational.
- If a prereq changes mid-implementation, such as a DB name change, update this document in the same PR.
