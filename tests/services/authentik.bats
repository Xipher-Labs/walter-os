#!/usr/bin/env bats
# Static-analysis assertions for the optional Authentik SSO profile.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUTHENTIK_DIR="$REPO_ROOT/setup/walter-host/services/authentik"
  AUTHENTIK_COMPOSE="$AUTHENTIK_DIR/compose.yml"
  AUTHENTIK_ENV_TEMPLATE="$AUTHENTIK_DIR/.env.template"
  AUTHENTIK_README="$AUTHENTIK_DIR/README.md"
  AUTHENTIK_RUNBOOK="$REPO_ROOT/docs/operational/authentik-sso.md"
}

@test "authentik service files exist" {
  [[ -f "$AUTHENTIK_COMPOSE" ]]
  [[ -f "$AUTHENTIK_ENV_TEMPLATE" ]]
  [[ -f "$AUTHENTIK_README" ]]
}

@test "authentik compose gates every service behind authentik profile" {
  grep -A8 "^  authentik-server:" "$AUTHENTIK_COMPOSE" | grep -q 'profiles:.*authentik'
  grep -A8 "^  authentik-worker:" "$AUTHENTIK_COMPOSE" | grep -q 'profiles:.*authentik'
  grep -A8 "^  authentik-postgresql:" "$AUTHENTIK_COMPOSE" | grep -q 'profiles:.*authentik'
  grep -A8 "^  authentik-redis:" "$AUTHENTIK_COMPOSE" | grep -q 'profiles:.*authentik'
}

@test "authentik compose pins official app and database images" {
  grep -q "ghcr.io/goauthentik/server:2026.5.2" "$AUTHENTIK_COMPOSE"
  grep -q "postgres:16-alpine" "$AUTHENTIK_COMPOSE"
  grep -q "redis:7-alpine" "$AUTHENTIK_COMPOSE"
}

@test "authentik compose does not use latest or floating app tags" {
  run grep -E '(:latest|goauthentik/server:(2026|2026\.5)([^0-9.]|$))' "$AUTHENTIK_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "authentik compose fails closed for required secrets" {
  grep -qE '\$\{AUTHENTIK_SECRET_KEY:\?' "$AUTHENTIK_COMPOSE"
  grep -qE '\$\{AUTHENTIK_POSTGRESQL__PASSWORD:\?' "$AUTHENTIK_COMPOSE"
  grep -qE 'POSTGRES_PASSWORD:.*\$\{AUTHENTIK_POSTGRESQL__PASSWORD:\?' "$AUTHENTIK_COMPOSE"
}

@test "authentik env template contains placeholders but no real secrets" {
  grep -q "^AUTHENTIK_SECRET_KEY=$" "$AUTHENTIK_ENV_TEMPLATE"
  grep -q "^AUTHENTIK_POSTGRESQL__PASSWORD=$" "$AUTHENTIK_ENV_TEMPLATE"
  run grep -E '(changeme|password123|secret123|AKIA|BEGIN [A-Z ]*PRIVATE KEY)' "$AUTHENTIK_ENV_TEMPLATE"
  [ "$status" -ne 0 ]
}

@test "authentik compose exposes no direct public host ports" {
  run grep -qE '^\s*ports:' "$AUTHENTIK_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "authentik compose uses dedicated named volumes" {
  grep -q "authentik-postgresql-data:" "$AUTHENTIK_COMPOSE"
  grep -q "authentik-data:" "$AUTHENTIK_COMPOSE"
  grep -q "authentik-certs:" "$AUTHENTIK_COMPOSE"
  grep -q "authentik-templates:" "$AUTHENTIK_COMPOSE"
}

@test "authentik docs mention OIDC, backups, and optional solo installs" {
  grep -qi "OIDC" "$AUTHENTIK_README"
  grep -qi "backup" "$AUTHENTIK_README"
  grep -qi "solo\\|personal" "$AUTHENTIK_README"
}

@test "authentik operational runbook mentions Caddy and Cloudflare Access routing" {
  [[ -f "$AUTHENTIK_RUNBOOK" ]]
  grep -qi "Caddy" "$AUTHENTIK_RUNBOOK"
  grep -qi "Cloudflare Access" "$AUTHENTIK_RUNBOOK"
  grep -qi "authentik" "$AUTHENTIK_RUNBOOK"
}
