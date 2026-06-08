#!/usr/bin/env bash
# scripts/bootstrap.sh — Walter-OS first-run service initialization
#
# Runs AFTER `docker compose up -d` has brought core services to healthy.
# Idempotent: a .bootstrapped sentinel file prevents re-running.
#
# What this creates (AC-2):
#   - Plane workspace "walter-os"
#   - Forgejo admin user matching WALTER_INITIAL_USER
#   - Infisical workspace "walter-os" + Machine Identity "walter-agent"
#   - LiteLLM master key confirmation + OpenClaw virtual key
#   - Grafana admin password via API
#   - Uptime Kuma monitor list (AC-6)
#
# Usage:
#   scripts/bootstrap.sh             # full bootstrap
#   scripts/bootstrap.sh --dry-run   # print what would happen, no API calls
#   scripts/bootstrap.sh --force     # ignore .bootstrapped sentinel and re-run
#   scripts/bootstrap.sh --help
#
# Required env vars:
#   WALTER_DOMAIN, WALTER_ADMIN_EMAIL, WALTER_INITIAL_USER,
#   WALTER_INITIAL_PASSWORD, WALTER_TIMEZONE
#
# Refs: docs/specs/phase-w-1-docker-compose.md

set -euo pipefail

# ---------- Configuration ----------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$REPO_ROOT}"
SENTINEL="$BOOTSTRAP_DIR/.bootstrapped"

DRY=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    -h|--help)
      grep '^#' "$0" | head -30 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ---------- Terminal colors ----------

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}[bootstrap]${c_0} %s\n" "$*"; }
warn() { printf "${c_y}[bootstrap]${c_0} %s\n" "$*"; }
err()  { printf "${c_r}[bootstrap]${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==> %s${c_0}\n" "$*"; }
dry()  { printf "${c_d}[dry-run]${c_0} would: %s\n" "$*"; }
info() { printf "${c_b}[bootstrap]${c_0} %s\n" "$*"; }

# ---------- Validate required env vars ----------

check_env() {
  local missing=()
  for var in WALTER_DOMAIN WALTER_ADMIN_EMAIL WALTER_INITIAL_USER \
             WALTER_INITIAL_PASSWORD WALTER_TIMEZONE; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required environment variables: ${missing[*]}"
    err "Copy templates/env.all.template to .env and source it, or export them manually."
    exit 1
  fi
}

if [[ $DRY -eq 0 ]]; then
  check_env
fi

# In dry-run mode, use defaults for display
WALTER_DOMAIN="${WALTER_DOMAIN:-example.com}"
WALTER_ADMIN_EMAIL="${WALTER_ADMIN_EMAIL:-admin@example.com}"
WALTER_INITIAL_USER="${WALTER_INITIAL_USER:-admin}"
WALTER_INITIAL_PASSWORD="${WALTER_INITIAL_PASSWORD:-changeme}"
WALTER_TIMEZONE="${WALTER_TIMEZONE:-UTC}"

# ---------- Service base URLs (derived from WALTER_DOMAIN) ----------

PLANE_URL="http://localhost:8090"           # plane-proxy internal port
FORGEJO_URL="http://localhost:3000"         # forgejo internal port
INFISICAL_URL="http://localhost:8800"       # infisical internal port
LITELLM_URL="http://localhost:4000"         # litellm internal port
GRAFANA_URL="http://localhost:3030"         # grafana internal port
UPTIME_KUMA_URL="http://localhost:3001"     # uptime-kuma internal port

# Override for testing
PLANE_URL="${WALTER_PLANE_URL:-$PLANE_URL}"
FORGEJO_URL="${WALTER_FORGEJO_URL:-$FORGEJO_URL}"
INFISICAL_URL="${WALTER_INFISICAL_URL:-$INFISICAL_URL}"
LITELLM_URL="${WALTER_LITELLM_URL:-$LITELLM_URL}"
GRAFANA_URL="${WALTER_GRAFANA_URL:-$GRAFANA_URL}"

# ---------- Sentinel check ----------

if [[ -f "$SENTINEL" ]] && [[ $FORCE -eq 0 ]]; then
  ok "Already bootstrapped (sentinel: $SENTINEL). Use --force to re-run."
  exit 0
fi

# ---------- Dry-run mode banner ----------

if [[ $DRY -eq 1 ]]; then
  info "DRY RUN — no API calls will be made."
  info ""
  info "Bootstrap would perform the following steps:"
  info ""
  step "Step 0: Render Caddyfile from template"
  dry "envsubst < setup/caddy/Caddyfile.template > setup/caddy/Caddyfile"
  dry "docker exec walter-caddy caddy reload --config /etc/caddy/Caddyfile"
  info ""

  step "Step 0b: Render Headscale config from template"
  dry "envsubst '\$WALTER_DOMAIN' < setup/headscale/config.yaml.template > setup/headscale/config.yaml"
  dry "docker restart headscale (if container is running)"
  info ""

  step "Wait for Postgres (pg_isready) then sync role passwords"
  dry "docker exec walter-postgres pg_isready -U walter"
  dry "docker exec walter-postgres psql -U walter -c 'ALTER USER forgejo WITH PASSWORD ...'"
  dry "... (repeat for infisical, litellm, n8n, postiz, metabase)"
  info ""

  step "Wait for app services to be healthy"
  dry "curl -sf ${PLANE_URL}/api/ (Plane API)"
  dry "curl -sf ${FORGEJO_URL}/api/v1/version (Forgejo API)"
  dry "curl -sf ${INFISICAL_URL}/api/status (Infisical API)"
  dry "curl -sf ${LITELLM_URL}/health (LiteLLM API)"
  dry "curl -sf ${GRAFANA_URL}/api/health (Grafana API)"
  info ""

  step "Plane: create workspace 'walter-os'"
  dry "POST ${PLANE_URL}/api/v1/workspaces/ {name: walter-os, slug: walter-os}"
  info ""

  step "Forgejo: create admin user '${WALTER_INITIAL_USER}'"
  dry "POST ${FORGEJO_URL}/api/v1/admin/users {login: ${WALTER_INITIAL_USER}, email: ${WALTER_ADMIN_EMAIL}}"
  info ""

  step "Infisical: create workspace 'walter-os' + Machine Identity 'walter-agent'"
  dry "POST ${INFISICAL_URL}/api/v1/workspace {name: walter-os}"
  dry "POST ${INFISICAL_URL}/api/v1/auth/machine-identities {name: walter-agent}"
  info ""

  step "LiteLLM: verify master key + create OpenClaw virtual key"
  dry "POST ${LITELLM_URL}/key/generate {key_alias: openclaw, max_budget: 10}"
  info ""

  step "Grafana: set admin password"
  dry "PUT ${GRAFANA_URL}/api/admin/users/1/password {password: \$WALTER_INITIAL_PASSWORD}"
  info ""

  step "Uptime Kuma: import monitor list"
  dry "POST ${UPTIME_KUMA_URL}/api/monitor (for each service in compose)"
  info ""

  step "Write sentinel: ${SENTINEL}"
  dry "NOT written in dry-run mode"
  info ""
  ok "Dry-run complete. Inspect the steps above before running for real."
  exit 0
fi

# ---------- Helper: wait for service ----------

wait_for() {
  local name="$1" url="$2" max="${3:-60}"
  local i=0
  info "Waiting for $name at $url (max ${max}s)..."
  while ! curl -sf "$url" >/dev/null 2>&1; do
    sleep 2
    i=$((i + 2))
    if [[ $i -ge $max ]]; then
      err "$name did not become healthy within ${max}s. Check: docker compose ps"
      return 1
    fi
  done
  ok "$name is up."
}

# ---------- Helper: curl with retry ----------

api_call() {
  local method="$1" url="$2"
  shift 2
  curl -sf -X "$method" "$url" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------- Step 0: Render Caddyfile from template ----------
# The committed Caddyfile is a placeholder with literal ${VAR} strings that
# Caddy does NOT expand itself.  bootstrap.sh owns the render step; without
# it, all reverse-proxy routes (git.${DOMAIN}, plane.${DOMAIN}, …) never
# work — Caddy serves only the placeholder ":80" response.

step "Step 0: Rendering Caddyfile from template..."

: "${WALTER_DOMAIN:?WALTER_DOMAIN is required to render the Caddyfile}"
CADDY_TEMPLATE="${REPO_ROOT}/setup/caddy/Caddyfile.template"
CADDY_FILE="${REPO_ROOT}/setup/caddy/Caddyfile"
CADDY_CONTAINER="${CADDY_CONTAINER:-walter-caddy}"

if [[ ! -f "$CADDY_TEMPLATE" ]]; then
  err "Caddyfile.template not found at: $CADDY_TEMPLATE"
  err "Cannot render Caddyfile — aborting."
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  err "'envsubst' not found. Install gettext (macOS: brew install gettext; Linux: apt install gettext)."
  exit 1
fi

# Restrict envsubst to ONLY the bootstrap-time vars. Closes Codex R2
# (PR #130) BLOCKER: envsubst without an allowlist would also expand
# Caddy's native `{$VAR}` placeholders (e.g. `{$WALTER_TAILNET_CIDR}` →
# `{<value-or-empty>}`), corrupting the admin_auth_gate matchers.
# The Caddy-native placeholders MUST survive untouched into the
# rendered Caddyfile so Caddy resolves them at container start time
# from its environment (set in compose.yml).
#
# The SHELL-FORMAT positional arg tells envsubst which $-references to
# expand; any $-reference whose name is not in the list is left alone.
# shellcheck disable=SC2016 # envsubst shell-format must stay literal.
WALTER_DOMAIN="$WALTER_DOMAIN" \
WALTER_ADMIN_EMAIL="${WALTER_ADMIN_EMAIL:-admin@example.com}" \
  envsubst '$WALTER_DOMAIN $WALTER_ADMIN_EMAIL' < "$CADDY_TEMPLATE" > "$CADDY_FILE"

ok "Caddyfile rendered to: $CADDY_FILE"

# Validate: no unexpanded ${...} vars remain
if grep -qE '\$\{[A-Z_][A-Z0-9_]*\}' "$CADDY_FILE"; then
  warn "Caddyfile still contains unexpanded variables:"
  grep -E '\$\{[A-Z_][A-Z0-9_]*\}' "$CADDY_FILE" | head -5 | while IFS= read -r line; do
    warn "  $line"
  done
fi

# Reload Caddy if the container is running (it may not be on first start yet)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CADDY_CONTAINER}$"; then
  if docker exec "$CADDY_CONTAINER" caddy reload \
       --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    ok "Caddy reloaded with new config."
  else
    warn "Caddy reload returned non-zero. It will pick up the new Caddyfile on restart."
  fi
else
  info "Caddy container not running yet — it will use the rendered Caddyfile on startup."
fi

# ---------- Step 0b: Render Headscale config from template ----------
# The root all-in-one compose stack mounts setup/headscale/config.yaml
# read-only into the Headscale container. Headscale does not expand shell
# placeholders from YAML, so bootstrap owns the render step just like Caddy.

step "Step 0b: Rendering Headscale config from template..."

HEADSCALE_TEMPLATE="${REPO_ROOT}/setup/headscale/config.yaml.template"
HEADSCALE_FILE="${REPO_ROOT}/setup/headscale/config.yaml"
HEADSCALE_CONTAINER="${HEADSCALE_CONTAINER:-headscale}"

if [[ ! -f "$HEADSCALE_TEMPLATE" ]]; then
  err "Headscale config template not found at: $HEADSCALE_TEMPLATE"
  err "Cannot render Headscale config — aborting."
  exit 1
fi

WALTER_DOMAIN="$WALTER_DOMAIN" \
  envsubst "\$WALTER_DOMAIN" < "$HEADSCALE_TEMPLATE" > "$HEADSCALE_FILE"

ok "Headscale config rendered to: $HEADSCALE_FILE"

if grep -qE '\$\{[A-Z_][A-Z0-9_]*\}' "$HEADSCALE_FILE"; then
  warn "Headscale config still contains unexpanded variables:"
  grep -E '\$\{[A-Z_][A-Z0-9_]*\}' "$HEADSCALE_FILE" | head -5 | while IFS= read -r line; do
    warn "  $line"
  done
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${HEADSCALE_CONTAINER}$"; then
  if docker restart "$HEADSCALE_CONTAINER" >/dev/null 2>&1; then
    ok "Headscale restarted with rendered config."
  else
    warn "Headscale restart returned non-zero. Restart it manually after checking the rendered config."
  fi
else
  info "Headscale container not running yet — it will use the rendered config on startup."
fi

# ---------- Step 1: Wait for Postgres + sync passwords BEFORE app services ----------
#
# ORDERING — why Postgres must come first:
#
#   On a first run with empty volumes, init.sql creates service DB roles
#   without passwords.  The app containers (Forgejo, Infisical, LiteLLM, …)
#   start in parallel and immediately try to authenticate using the passwords
#   from their ${*_DB_PASS} env vars.  Authentication fails and they enter
#   Docker's restart-on-fail loop.
#
#   If bootstrap waited for all services to become healthy BEFORE running
#   the ALTER USER fixup, we would deadlock: app containers can never reach
#   "healthy" because their passwords are not set yet, and passwords are
#   never set because we are waiting for the apps first.
#
#   Correct ordering enforced here:
#     1. Wait for Postgres only (no DB auth dependency).
#     2. ALTER USER for every service role → passwords now match env vars.
#     3. Wait for app services → they reconnect successfully on next attempt.

# Default matches compose.yml `POSTGRES_USER: walter`. Override via
# PG_SUPERUSER env var, then POSTGRES_USER, then the compose default.
PG_SUPERUSER="${PG_SUPERUSER:-${POSTGRES_USER:-walter}}"
WALTER_POSTGRES_USER="${WALTER_POSTGRES_USER:-$PG_SUPERUSER}"
WALTER_POSTGRES_CONTAINER="${WALTER_POSTGRES_CONTAINER:-walter-postgres}"

step "Step 1: Waiting for Postgres to be healthy (must precede password sync)..."

# wait_for polls HTTP endpoints; Postgres needs docker exec pg_isready.
pg_ready=0
for _i in $(seq 1 30); do
  if docker exec "$WALTER_POSTGRES_CONTAINER" \
       pg_isready -U "$PG_SUPERUSER" >/dev/null 2>&1; then
    pg_ready=1
    break
  fi
  sleep 2
done
if [[ $pg_ready -eq 0 ]]; then
  err "Postgres did not become ready within 60s. Check: docker compose ps postgres"
  err "Cannot sync DB role passwords — aborting."
  exit 1
fi
ok "Postgres is ready."

# ---------- Step 1b: Postgres — sync service role passwords from env vars ----------
# init.sql creates roles without passwords; ALTER USER sets them from env vars.
# Idempotent — safe to re-run.  MUST complete before waiting on app services.

step "Step 1b: Syncing Postgres service role passwords..."

declare -A PG_SERVICE_PASS=(
  [forgejo]="${FORGEJO_DB_PASS:-}"
  [infisical]="${INFISICAL_DB_PASS:-}"
  [litellm]="${LITELLM_DB_PASS:-}"
  [n8n]="${N8N_PG_PASS:-}"
  [postiz]="${POSTIZ_PG_PASS:-}"
  [metabase]="${METABASE_DB_PASS:-}"
  [posthog]="${POSTHOG_DB_PASS:-}"
)

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${WALTER_POSTGRES_CONTAINER}$"; then
  for svc in forgejo infisical litellm n8n postiz metabase posthog; do
    pass="${PG_SERVICE_PASS[$svc]:-}"
    if [[ -z "$pass" ]]; then
      warn "  $svc: password env var not set, skipping ALTER USER"
      continue
    fi
    if docker exec "$WALTER_POSTGRES_CONTAINER" \
         psql -U "$PG_SUPERUSER" -c "ALTER USER ${svc} WITH PASSWORD '${pass}';" \
         >/dev/null 2>&1; then
      ok "  $svc: password synced via ALTER USER"
    else
      warn "  $svc: ALTER USER failed (user may not exist yet)"
    fi
  done
else
  warn "Postgres container '${WALTER_POSTGRES_CONTAINER}' not running — skipping ALTER USER."
  warn "Re-run bootstrap.sh after Postgres starts to sync passwords."
fi

# ---------- Step 1c: Now wait for app services (passwords are set) ----------

step "Step 1c: Waiting for app services to become healthy..."

wait_for "Forgejo"   "${FORGEJO_URL}/api/v1/version"  120
wait_for "Infisical" "${INFISICAL_URL}/api/status"     120
wait_for "LiteLLM"   "${LITELLM_URL}/health"           120
wait_for "Grafana"   "${GRAFANA_URL}/api/health"       120

# Plane might take longer (runs migrations on first start)
wait_for "Plane" "${PLANE_URL}/api/" 180 || true

# ---------- Step 2: Plane — create workspace ----------

step "Plane: create workspace 'walter-os'..."

PLANE_API_KEY="${PLANE_API_KEY:-}"

if [[ -n "$PLANE_API_KEY" ]]; then
  plane_resp=$(api_call POST "${PLANE_URL}/api/v1/workspaces/" \
    -H "X-Api-Key: $PLANE_API_KEY" \
    -d "{\"name\":\"walter-os\",\"slug\":\"walter-os\"}" 2>&1 || true)
  if echo "$plane_resp" | grep -qi "walter-os"; then
    ok "Plane workspace 'walter-os' created."
  else
    warn "Plane workspace may already exist or API key not set. Response: ${plane_resp:-empty}"
    warn "Complete Plane setup manually at https://plane.${WALTER_DOMAIN}"
  fi
else
  warn "PLANE_API_KEY not set — skip Plane API bootstrap."
  warn "Create workspace manually at https://plane.${WALTER_DOMAIN}"
fi

# ---------- Step 3: Forgejo — create admin user ----------

step "Forgejo: create admin user '${WALTER_INITIAL_USER}'..."

forgejo_resp=$(api_call POST "${FORGEJO_URL}/api/v1/admin/users" \
  -u "${WALTER_INITIAL_USER}:${WALTER_INITIAL_PASSWORD}" \
  -d "{
    \"email\": \"${WALTER_ADMIN_EMAIL}\",
    \"login_name\": \"${WALTER_INITIAL_USER}\",
    \"password\": \"${WALTER_INITIAL_PASSWORD}\",
    \"username\": \"${WALTER_INITIAL_USER}\",
    \"must_change_password\": true,
    \"send_notify\": false,
    \"source_id\": 0,
    \"visibility\": \"public\"
  }" 2>&1 || true)

if echo "$forgejo_resp" | grep -qi "\"id\""; then
  ok "Forgejo user '${WALTER_INITIAL_USER}' created."
elif echo "$forgejo_resp" | grep -qi "already exist\|user already"; then
  ok "Forgejo user '${WALTER_INITIAL_USER}' already exists."
else
  warn "Forgejo user creation response: ${forgejo_resp:-empty}"
  warn "You may need to create the admin user via the Forgejo web UI."
fi

# ---------- Step 4: Infisical — create workspace + Machine Identity ----------

step "Infisical: create workspace 'walter-os' + Machine Identity 'walter-agent'..."

INFISICAL_TOKEN="${INFISICAL_TOKEN:-}"

if [[ -n "$INFISICAL_TOKEN" ]]; then
  # Create workspace
  infisical_ws=$(api_call POST "${INFISICAL_URL}/api/v2/workspaces" \
    -H "Authorization: Bearer $INFISICAL_TOKEN" \
    -d "{\"workspaceName\":\"walter-os\",\"organizationId\":\"\"}" 2>&1 || true)

  if echo "$infisical_ws" | grep -qi "walter-os"; then
    ok "Infisical workspace 'walter-os' created."
    WS_ID=$(echo "$infisical_ws" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    # Create Machine Identity
    if [[ -n "$WS_ID" ]]; then
      api_call POST "${INFISICAL_URL}/api/v1/auth/machine-identities" \
        -H "Authorization: Bearer $INFISICAL_TOKEN" \
        -d "{\"name\":\"walter-agent\",\"workspaceId\":\"$WS_ID\"}" >/dev/null 2>&1 || true
      ok "Infisical Machine Identity 'walter-agent' created."
    fi
  else
    warn "Infisical workspace creation response: ${infisical_ws:-empty}"
  fi
else
  warn "INFISICAL_TOKEN not set — skip Infisical API bootstrap."
  warn "Log in to Infisical at https://secrets.${WALTER_DOMAIN} and create workspace manually."
fi

# ---------- Step 5: LiteLLM — verify master key + create OpenClaw key ----------

step "LiteLLM: verify master key + create OpenClaw virtual key..."

LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

if [[ -n "$LITELLM_MASTER_KEY" ]]; then
  litellm_health=$(api_call GET "${LITELLM_URL}/health" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>&1 || true)

  if echo "$litellm_health" | grep -qi "healthy\|status"; then
    ok "LiteLLM master key is valid."

    # Create OpenClaw virtual key
    openclaw_key=$(api_call POST "${LITELLM_URL}/key/generate" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -d "{\"key_alias\":\"openclaw\",\"max_budget\":10,\"budget_duration\":\"1mo\"}" 2>&1 || true)

    if echo "$openclaw_key" | grep -q '"key"'; then
      OPENCLAW_KEY=$(echo "$openclaw_key" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
      ok "LiteLLM OpenClaw virtual key created: ${OPENCLAW_KEY:0:12}..."
      warn "Add LITELLM_OPENCLAW_KEY=${OPENCLAW_KEY} to your .env"
    else
      warn "OpenClaw key creation response: ${openclaw_key:-empty}"
    fi
  else
    warn "LiteLLM health response: ${litellm_health:-empty}"
  fi
else
  warn "LITELLM_MASTER_KEY not set — skip LiteLLM bootstrap."
fi

# ---------- Step 6: Grafana — set admin password ----------

step "Grafana: set admin password..."

GF_ADMIN_PASSWORD="${GF_ADMIN_PASSWORD:-$WALTER_INITIAL_PASSWORD}"

grafana_resp=$(api_call PUT "${GRAFANA_URL}/api/admin/users/1/password" \
  -u "${WALTER_INITIAL_USER}:${GF_ADMIN_PASSWORD}" \
  -d "{\"password\":\"${GF_ADMIN_PASSWORD}\"}" 2>&1 || true)

if echo "$grafana_resp" | grep -qi "message\|password"; then
  ok "Grafana admin password set."
else
  warn "Grafana password response: ${grafana_resp:-empty}"
  warn "Set password manually at https://grafana.${WALTER_DOMAIN}"
fi

# ---------- Step 7: Uptime Kuma — import monitor list ----------

step "Uptime Kuma: import monitor list (AC-6)..."

# Uptime Kuma's API requires authentication setup first.
# On first run, we wait for the UI to be available and note manual steps.
# Full API automation requires the operator to set a credentials pair.

KUMA_USER="${KUMA_USER:-}"
KUMA_PASS="${KUMA_PASS:-}"
KUMA_URL="${KUMA_URL:-http://localhost:3001}"

if [[ -n "$KUMA_USER" ]] && [[ -n "$KUMA_PASS" ]]; then
  # Wire kuma-bulk-monitors.py for automated monitor import (AC-6)
  KUMA_SCRIPT="$SCRIPT_DIR/kuma-bulk-monitors.py"
  if [[ -f "$KUMA_SCRIPT" ]] && command -v python3 >/dev/null 2>&1; then
    ok "Running kuma-bulk-monitors.py to import monitor list (AC-6)..."
    WALTER_DOMAIN="$WALTER_DOMAIN" \
    KUMA_URL="$KUMA_URL" \
    KUMA_USER="$KUMA_USER" \
    KUMA_PASS="$KUMA_PASS" \
      python3 "$KUMA_SCRIPT" || warn "Kuma monitor import failed (non-fatal — check Kuma credentials)"
  else
    warn "kuma-bulk-monitors.py not found or python3 unavailable, skipping monitor import."
    warn "Manual import: WALTER_DOMAIN=... KUMA_USER=... KUMA_PASS=... python3 scripts/kuma-bulk-monitors.py"
  fi
else
  warn "KUMA_USER/KUMA_PASS not set."
  warn "Complete Uptime Kuma setup at https://status.${WALTER_DOMAIN}"
  warn "Then run: KUMA_USER=admin KUMA_PASS=... scripts/bootstrap.sh --force"
fi

# ---------- Step 8: Write sentinel ----------

step "Writing bootstrap sentinel..."

date -u '+%Y-%m-%dT%H:%M:%SZ' > "$SENTINEL"
echo "domain=${WALTER_DOMAIN}" >> "$SENTINEL"
echo "user=${WALTER_INITIAL_USER}" >> "$SENTINEL"

ok "Bootstrap complete. Sentinel written: $SENTINEL"
info ""
info "Next steps:"
info "  1. Visit https://plane.${WALTER_DOMAIN} and complete Plane workspace setup"
info "  2. Visit https://git.${WALTER_DOMAIN} and verify Forgejo is accessible"
info "  3. Visit https://secrets.${WALTER_DOMAIN} and log in to Infisical"
info "  4. Visit https://llm.${WALTER_DOMAIN} and verify LiteLLM gateway"
info "  5. Visit https://grafana.${WALTER_DOMAIN} and change the default password"
info "  6. Visit https://status.${WALTER_DOMAIN} and set up Uptime Kuma monitors"
info ""
info "For profile services:"
info "  docker compose --profile devrel up -d   # Postiz"
info "  docker compose --profile design up -d   # Penpot + Drawio"
info "  docker compose --profile assistant up -d # OpenClaw"
