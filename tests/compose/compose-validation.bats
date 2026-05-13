#!/usr/bin/env bats
# Compose YAML validation tests
# Covers: AC-1, AC-4, AC-8
#
# These tests validate compose.yml structure without spinning up containers.
# They are safe to run in CI without Docker daemon access (except the
# `docker compose config` test which needs Docker).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/compose.yml"
  ENV_TEMPLATE="$REPO_ROOT/templates/env.all.template"
}

# --- File existence ---

@test "compose.yml exists at repo root" {
  # AC-1, AC-4
  [ -f "$COMPOSE_FILE" ]
}

@test "templates/env.all.template exists" {
  # AC-8
  [ -f "$ENV_TEMPLATE" ]
}

@test "setup/env.example does not exist (templates/env.all.template is canonical)" {
  # B3: setup/env.example contained hardcoded operator-specific URLs.
  # It is replaced by templates/env.all.template. File must be deleted.
  [ ! -f "$REPO_ROOT/setup/env.example" ]
}

# --- YAML structure (grep-based, no docker required) ---

@test "compose.yml declares walter_net network" {
  grep -q "walter_net" "$COMPOSE_FILE"
}

@test "compose.yml declares postgres service" {
  grep -q "^  postgres:" "$COMPOSE_FILE"
}

@test "compose.yml declares caddy service" {
  grep -q "^  caddy:" "$COMPOSE_FILE"
}

@test "compose.yml declares plane-api service" {
  grep -q "plane-api:" "$COMPOSE_FILE"
}

@test "compose.yml declares forgejo service" {
  grep -q "^  forgejo:" "$COMPOSE_FILE"
}

@test "compose.yml declares infisical service" {
  grep -q "infisical" "$COMPOSE_FILE"
}

@test "compose.yml declares litellm service" {
  grep -q "^  litellm:" "$COMPOSE_FILE"
}

@test "compose.yml declares grafana service" {
  grep -q "^  grafana:" "$COMPOSE_FILE"
}

@test "compose.yml declares prometheus service" {
  grep -q "^  prometheus:" "$COMPOSE_FILE"
}

@test "compose.yml declares n8n service" {
  grep -q "^  n8n:" "$COMPOSE_FILE"
}

@test "compose.yml declares uptime-kuma service" {
  grep -q "uptime-kuma" "$COMPOSE_FILE"
}

@test "compose.yml contains no hardcoded xipherlabs domain" {
  # AC-8 — no operator-specific domain anywhere
  ! grep -q "xipherlabs\.xyz" "$COMPOSE_FILE"
}

@test "compose.yml uses WALTER_DOMAIN variable for domains" {
  grep -q "WALTER_DOMAIN" "$COMPOSE_FILE"
}

@test "compose.yml: postiz is in default profile (no devrel profile required) [v0.2.0+]" {
  # As of v0.2.0, postiz was promoted from --profile devrel to always-on core.
  grep -q "^  postiz:" "$COMPOSE_FILE"
  # Must NOT have profiles: [devrel] — it's core now
  ! grep -A5 "^  postiz:" "$COMPOSE_FILE" | grep -q "devrel"
}

@test "compose.yml: metabase is in default profile (no devrel profile required) [v0.2.0+]" {
  # As of v0.2.0, metabase was promoted from --profile devrel to always-on core.
  grep -q "^  metabase:" "$COMPOSE_FILE"
  # Must NOT have profiles: [devrel] — it's core now
  ! grep -A5 "^  metabase:" "$COMPOSE_FILE" | grep -q "devrel"
}

@test "compose.yml metabase depends on postgres" {
  # AC-5: metabase must wait for postgres to be healthy
  local metabase_line
  metabase_line=$(grep -n "^  metabase:" "$COMPOSE_FILE" | head -1 | cut -d: -f1)
  tail -n "+$metabase_line" "$COMPOSE_FILE" | head -30 | grep -q "postgres"
}

@test "scripts/kuma-bulk-monitors.py exists" {
  [ -f "$REPO_ROOT/scripts/kuma-bulk-monitors.py" ]
}

@test "bootstrap.sh wires kuma-bulk-monitors.py for auto-import (AC-6)" {
  # AC-6: bootstrap must reference and call kuma-bulk-monitors.py
  grep -q "kuma-bulk-monitors.py" "$REPO_ROOT/scripts/bootstrap.sh"
}

@test "compose.yml declares design profile for penpot" {
  grep -A5 "^  penpot-frontend:" "$COMPOSE_FILE" | grep -q "design"
}

@test "compose.yml declares design profile for drawio" {
  grep -A5 "^  drawio:" "$COMPOSE_FILE" | grep -q "design"
}

@test "compose.yml declares assistant profile for openclaw" {
  grep -A5 "^  openclaw:" "$COMPOSE_FILE" | grep -q "assistant"
}

@test "compose.yml forgejo service seeds admin via env vars (W1)" {
  # W1: INSTALL_LOCK must be paired with admin user env vars to avoid
  # chicken-and-egg (install wizard locked but no admin user created)
  local forgejo_line
  forgejo_line=$(grep -n "^  forgejo:" "$COMPOSE_FILE" | head -1 | cut -d: -f1)
  local block
  block=$(tail -n "+$forgejo_line" "$COMPOSE_FILE" | head -40)
  echo "$block" | grep -q "FORGEJO__security__INSTALL_LOCK"
  echo "$block" | grep -q "WALTER_INITIAL_PASSWORD"
  echo "$block" | grep -q "WALTER_ADMIN_EMAIL"
}

@test "compose.yml has healthcheck for postgres" {
  # AC-4 — count occurrences of healthcheck after postgres definition
  # Strategy: verify healthcheck appears in the file AND postgres is a service
  grep -q "^  postgres:" "$COMPOSE_FILE"
  # Find line number of postgres service, then check healthcheck appears within 30 lines
  postgres_line=$(grep -n "^  postgres:" "$COMPOSE_FILE" | head -1 | cut -d: -f1)
  tail -n "+$postgres_line" "$COMPOSE_FILE" | head -30 | grep -q "healthcheck"
}

@test "compose.yml has healthcheck for grafana" {
  # AC-4
  grep -q "^  grafana:" "$COMPOSE_FILE"
  grafana_line=$(grep -n "^  grafana:" "$COMPOSE_FILE" | head -1 | cut -d: -f1)
  tail -n "+$grafana_line" "$COMPOSE_FILE" | head -50 | grep -q "healthcheck"
}

@test "compose.yml has healthcheck for n8n" {
  # AC-4
  grep -q "^  n8n:" "$COMPOSE_FILE"
  n8n_line=$(grep -n "^  n8n:" "$COMPOSE_FILE" | head -1 | cut -d: -f1)
  tail -n "+$n8n_line" "$COMPOSE_FILE" | head -40 | grep -q "healthcheck"
}

@test "compose.yml: openclaw npm install is pinned to specific version (W5)" {
  # openclaw@latest is non-deterministic; must be pinned to a semver release
  ! grep -q 'openclaw@latest' "$COMPOSE_FILE"
}

@test "compose.yml: no service image is pinned to :latest (W4)" {
  # Security: :latest images are non-deterministic and can change unexpectedly.
  # Each image must be pinned to a specific version tag.
  # We check image: lines specifically (not command strings like migration:latest).
  # Exception: walter-control-tower:latest is a locally-built image with no
  # upstream registry; the :latest tag is controlled by the operator's docker build.
  local flagged
  flagged=$(grep '^[[:space:]]*image:.*:latest' "$COMPOSE_FILE" | grep -v 'walter-control-tower:latest' || true)
  [ -z "$flagged" ]
}

@test "env template contains WALTER_DOMAIN" {
  grep -q "WALTER_DOMAIN" "$ENV_TEMPLATE"
}

@test "env template contains WALTER_ADMIN_EMAIL" {
  grep -q "WALTER_ADMIN_EMAIL" "$ENV_TEMPLATE"
}

@test "env template contains WALTER_INITIAL_USER" {
  grep -q "WALTER_INITIAL_USER" "$ENV_TEMPLATE"
}

@test "env template contains WALTER_INITIAL_PASSWORD" {
  grep -q "WALTER_INITIAL_PASSWORD" "$ENV_TEMPLATE"
}

@test "env template contains WALTER_TIMEZONE" {
  grep -q "WALTER_TIMEZONE" "$ENV_TEMPLATE"
}

# --- docker compose config (requires Docker) ---
# Tagged @slow — only run when WALTER_COMPOSE_TEST=1

@test "docker compose config validates without errors [requires Docker]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"
  # Create minimal .env for validation
  TMPENV="$(mktemp)"
  cat > "$TMPENV" <<ENV
WALTER_DOMAIN=example.com
WALTER_ADMIN_EMAIL=admin@example.com
WALTER_INITIAL_USER=admin
WALTER_INITIAL_PASSWORD=changeme
WALTER_TIMEZONE=UTC
POSTGRES_PASSWORD=pgpass
PLANE_POSTGRES_PASSWORD=planepass
PLANE_RABBITMQ_USER=plane
PLANE_RABBITMQ_PASSWORD=mqpass
PLANE_RABBITMQ_VHOST=plane
PLANE_SECRET_KEY=supersecretkey
PLANE_AWS_ACCESS_KEY_ID=minioadmin
PLANE_AWS_SECRET_ACCESS_KEY=minioadmin
FORGEJO_DB_PASS=forgejopass
INFISICAL_ENCRYPTION_KEY=0000000000000000
INFISICAL_AUTH_SECRET=aaaaaaaaaaaaaaaa
INFISICAL_DB_PASS=infisicalpass
INFISICAL_REDIS_PASS=redispass
LITELLM_MASTER_KEY=sk-master
LITELLM_SALT_KEY=saltkey
LITELLM_DB_PASS=litellmpass
LITELLM_UI_PASS=uipass
GF_ADMIN_PASSWORD=grafanapass
N8N_PG_PASS=n8npass
N8N_ENCRYPTION_KEY=00000000000000000000000000000000
WG_PASSWORD_HASH=dummyhash
ENV
  run docker compose --env-file "$TMPENV" config --quiet
  rm -f "$TMPENV"
  [ "$status" -eq 0 ]
}
