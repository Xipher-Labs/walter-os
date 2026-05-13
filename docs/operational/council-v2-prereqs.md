# Walter Council v2 — Operator Prerequisites

> Pasos manuales que **el operator** debe ejecutar fuera del implementer, fase por
> fase. El implementer no puede crear estos recursos por sí solo (requieren UI,
> permisos elevados, o decisiones de naming). Sin esto, las fases respectivas no
> pueden landearse.
>
> **Refs**: `docs/specs/walter-council-v2.md`, `docs/specs/walter-council-v2.plan.md`

---

## Status board

| Phase | Prereqs done? | Notas |
|---|---|---|
| F (foundation) | [ ] | Grafana datasource + Prometheus scrape config |
| M (memory) | [ ] | Wiki normalization manual review + Postgres `lessons` DB |
| R (recovery) | [ ] | Plane state `awaiting-resume` |
| T (trust + consensus) | [ ] | Plane states `awaiting-consensus`, `awaiting-human` |
| U (Control Tower) | [ ] | Tailscale ACL + Postgres `control_tower` DB + session secret |

Marcá los `[ ]` como `[x]` a medida que se ejecuten.

---

## Phase F — Foundation

### F-prereq-1: Verificar stack Prometheus + Grafana

```bash
docker compose ps | grep -E "prometheus|grafana"
# Ambos deben estar Up
```

Si no están, levantalos antes de que el implementer empiece T-3:
```bash
docker compose up -d prometheus grafana
```

### F-prereq-2: Grafana datasource — Prometheus

UI: `https://grafana.walter.lan` → Configuration → Data sources → Add data source → Prometheus

- URL: `http://prometheus:9090`
- Access: Server (default)
- Name: `walter-prometheus`

El dashboard que va a provisionar T-4 asume que el datasource se llama `walter-prometheus`. Si lo nombrás distinto, anotalo.

### F-prereq-3: Prometheus scrape config

Editar `prometheus/prometheus.yml` (mounted como volume) para agregar:

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

Reload: `docker compose exec prometheus kill -HUP 1`

### F-prereq-4: LiteLLM `/spend/tags` endpoint enabled

```bash
curl -s http://litellm:4000/spend/tags -H "Authorization: Bearer $LITELLM_MASTER_KEY"
# Debe devolver JSON (no 404)
```

Si devuelve 404, agregar a `litellm/config.yaml`:
```yaml
general_settings:
  store_model_in_db: true
  enable_spend_tracking: true
```

Y restart LiteLLM.

---

## Phase M — Memory + Intelligence

### M-prereq-1: Wiki normalization sanity check

Antes de T-M-0 (script automático), el operator debe pasar manualmente sobre páginas que el normalizer va a marcar como "needs review". El script las lista en
`~/.config/walter-os/wiki-normalize-report.txt`.

Esperar que el normalizer corra una vez, revisar el report, y aprobar el commit del normalizer.

### M-prereq-2: AGENTS.md amendment review

T-M-1 va a agregar una sección "Wiki integrity" al `AGENTS.md` global. El texto exacto está en el spec sección "Required AGENTS.md amendments".

El operator debe **revisar el PR** que incluye esta amendment antes de mergear — es un cambio al contrato global y aplica a todos los agentes, todos los proyectos.

### M-prereq-3: Postgres database `walter_lessons`

```bash
# En walter-vm:
docker compose exec postgres psql -U postgres -c "CREATE DATABASE walter_lessons;"
docker compose exec postgres psql -U postgres -c "CREATE USER lessons_writer WITH ENCRYPTED PASSWORD 'CHANGE_ME';"
docker compose exec postgres psql -U postgres -c "GRANT ALL ON DATABASE walter_lessons TO lessons_writer;"
```

Provisionar `LESSONS_DB_URL` en Infisical (`walter-os` workspace, env `dev`):
```
LESSONS_DB_URL=postgresql://lessons_writer:<password>@postgres:5432/walter_lessons
```

### M-prereq-5: Re-run install.sh to activate wiki-validator hook

The `wiki-validator.sh` is now registered as a `PreToolUse` hook in Claude Code
for `Write|Edit` tools. To activate it, re-run the installer:

```bash
cd /path/to/Walter-OS
./install.sh --upgrade
```

This merges the hook into `~/.claude/settings.json`. Without this step, agents
can write wiki pages with missing frontmatter and the validation will not fire.

Verify after install:
```bash
jq '.hooks.PreToolUse' ~/.claude/settings.json | grep wiki-validator
```

---

### M-prereq-4: Embedding model availability

LiteLLM config debe tener `nomic-embed-text` o equivalente expuesto:
```yaml
model_list:
  - model_name: walter-embed
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://ollama-standby-node:11434
```

Verificar: `curl http://litellm:4000/v1/embeddings -d '{"model": "walter-embed", "input": "test"}'`

Si no hay embed model disponible, T-10 va a fallar.

---

## Phase R — Resilience

### R-prereq-1: Plane custom state `awaiting-resume`

Hoy Plane tiene states default: `backlog`, `todo`, `in-progress`, `done`, `cancelled`. La fase R necesita un state intermedio para tasks que un agente abandonó y otra instancia puede retomar.

UI Plane: workspace `walter-os` → project `agents` → States → Add State:
- Name: `awaiting-resume`
- Group: `started`
- Color: `#f59e0b` (amber)

Sin este state, T-19 (zombie watchdog) no puede re-encolar tasks correctamente.

### R-prereq-2: Watchdog cron permissions

T-20 va a instalar un cron. En walter-vm, asegurar que el user `walter` puede correr cron:
```bash
ssh walter-vm "crontab -l" # debe no devolver "you are not allowed"
```

Si está bloqueado, editar `/etc/cron.allow` y agregar `walter`.

---

## Phase T — Trust + Controls + Consensus

### T-prereq-1: Plane custom state `awaiting-consensus`

UI Plane: workspace `walter-os` → project `agents` → States → Add State:
- Name: `awaiting-consensus`
- Group: `unstarted`
- Color: `#8b5cf6` (violet)

T-35 falla sin este state.

### T-prereq-2: Plane custom state `awaiting-human`

UI Plane: idem arriba:
- Name: `awaiting-human`
- Group: `unstarted`
- Color: `#ef4444` (red)

Para tasks que el consensus rechaza y escalan al operator.

### T-prereq-3: Initial trust-tiers.yml values

T-25 crea el archivo. El operator debe **revisar y firmar** los valores iniciales antes del commit:
- triage: `medium`
- researcher: `medium`
- coder: `medium`
- reviewer: `high`
- janitor: `low`
- liaison: `low`

Si querés ajustes, hacelos antes del commit. Después es cambio gobernado (requiere otro PR).

### T-prereq-4: Consensus mode dry-run

Antes de activar `walter-os mode consensus on` en producción, correr el e2e bats test T-36c:
```bash
cd walter-os && bats tests/agents/consensus-mode.bats
```

Debe pasar 100%. Si falla, no activar consensus mode hasta arreglarlo.

---

## Phase U — Control Tower

### U-prereq-1: Postgres database `walter_control_tower`

```bash
docker compose exec postgres psql -U postgres -c "CREATE DATABASE walter_control_tower;"
```

### U-prereq-2: Session secret en Infisical

Generar:
```bash
openssl rand -hex 32
```

Guardar en Infisical workspace `walter-os` env `dev` como `CONTROL_TOWER_ADMIN_TOKEN`.

### U-prereq-3: Tailscale ACL

El Control Tower es Tailscale-only. Verificar que el ACL no expone el puerto:

```bash
ssh walter-vm "sudo tailscale serve status"
```

Si hay un `serve` expuesto en puerto 443 a internet, hay que removerlo y usar `funnel` interno solo.

ACL fragment en Headscale (en walter-vm):
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

T-40 embebe paneles Grafana en el Control Tower. Grafana debe permitir embed:

UI Grafana → Configuration → Settings → Embed mode → enable iframe embedding from `walter-vm:3000`.

Sin esto, los paneles aparecen vacíos con error CORS.

### U-prereq-5: Operator account creation en Control Tower

La primera vez que el operator entra al Control Tower (vía Tailscale), el sistema le pide crear un perfil (no es auth real — es preferencias UI: layout, tema, default views).

Esto es manual una sola vez por dispositivo.

---

## Phase V — DevRel Analytics Stack

### V-prereq-1: Google Ads Developer Token

Apply at: Google Ads Manager → Tools → API Center → Developer Token Request.
Approval: ~3-5 business days (test account) or 2-4 weeks (production approval).

```
Status: APPLY NOW — blocker for tap-google-ads (AC-6)
```

### V-prereq-2: Meta Business Verification + App Review

Apply at: https://developers.facebook.com → Your App → App Review → Permissions → `ads_read`
Also requires: Meta Business Verification (documents, can take 5-15 days).

```
Status: APPLY NOW — blocker for tap-facebook (AC-7)
```

### V-prereq-3: LinkedIn Marketing Developer Platform

Apply at: https://learn.microsoft.com/en-us/linkedin/marketing/integrations
Requires: LinkedIn Company Page + LinkedIn developer app with Marketing API access.
Approval: notoriously slow, multi-week, may reject without clear reason.

```
Status: APPLY NOW — Tier 3, blocker for tap-linkedin-ads
Note: This is the longest blocker. Apply immediately even if code isn't done.
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

In n8n UI, create these credentials (Settings → Credentials):

| Name | Type | For |
|---|---|---|
| `YouTube OAuth2` | YouTube OAuth2 API | yt-data-api-pull |
| `Analytics Postgres` | PostgreSQL | All workflows → analytics DB (port 5433) |
| `Plausible API Key` | HTTP Header Auth (`Authorization: Bearer <key>`) | plausible-pull |
| `GitHub PAT` | GitHub API | github-pull (needs `repo:traffic` scope) |
| `Bluesky Session Token` | HTTP Header Auth | bluesky-stream (optional for public) |
| `Walter Telegram Bot` | Telegram API | alert notifications |
| `Google Ads OAuth2` | (once V-prereq-1 approved) | google-ads-pull |
| `Meta App Token` | (once V-prereq-2 approved) | meta-ads-pull |

### V-prereq-6: Postgres analytics DB

```bash
# On walter-vm, build + start the analytics postgres:
cd setup/walter-host/services/postgres
docker compose build
ANALYTICS_PG_PASS=<generate-strong-password> docker compose up -d

# Verify migrations ran:
docker compose exec postgres-analytics psql -U analytics -d walter_devrel_analytics \
  -c "\dt" | grep -E "analytics_events|content_pieces|ad_spend_events"
```

The custom Dockerfile adds `pg_partman` + `pg_cron` extensions.
`postgresql.conf` sets `shared_preload_libraries = 'pg_cron,pg_partman_bgw'`.

Store password in Infisical `walter-os` workspace, env `dev`:
```
ANALYTICS_PG_PASS=<generated>
ANALYTICS_DB_URL=postgresql://analytics:<pass>@localhost:5433/walter_devrel_analytics
```

### V-prereq-7: Grafana datasource for analytics DB

After V-prereq-6 is running:

1. Ensure `postgres-analytics` container is on the same Docker network as `grafana`.
   - Either join `obs_net` from `postgres-analytics`, or use `host.docker.internal`.
   - Update `datasources.yml` URL if needed (currently: `postgres-analytics:5432`).
2. Restart Grafana to pick up provisioned datasource:
   ```bash
   docker compose restart grafana
   ```
3. Verify: Grafana → Configuration → Data Sources → "Walter DevRel Analytics" shows "OK".

### V-prereq-8: Telegram bot (alerts)

Already exists from Phase F. Verify:
```bash
docker compose exec n8n wget -qO- \
  "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/getMe"
```

If missing, create a new bot via @BotFather and store credentials in Infisical.

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

## Rollback plan global

Si cualquier fase introduce regression severo:

1. `git revert <merge-commit>` en `main`.
2. Reabrir las branches `feature/council-v2-<phase>` para fix.
3. Si el problema afecta runtime de Council actual (agentes parados), pausar todos:
   ```bash
   walter-os agents pause --all
   ```
4. Investigar con `walter-os agents status --verbose` y logs en `~/sync/agent-memory/audit/<date>.log`.
5. Una vez fixeado, smoke test en `staging` antes de re-promover.

Los hooks `branch-flow-guard.sh` y `approval-gate.sh` siguen activos durante el rollback — ofrecen una red de seguridad si el revert accidentalmente reintroduce un commit destructivo.

---

## Cómo este doc evoluciona

- Cada PR que landea una phase debe marcar su correspondiente row del status board como `[x]`.
- Prereqs descubiertos durante implementation se agregan acá (no en el spec — el spec es contrato, este doc es operacional).
- Si un prereq cambia mid-implementation (ej. nombre de DB), update este doc en el mismo PR.
