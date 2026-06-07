#!/usr/bin/env bats
# Static assertions for Postgres healthchecks that fail before slot saturation.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

service_block() {
  local file="$1" service="$2"
  awk -v svc="$service" '
    index($0, "  " svc ":") == 1 { found = 1; print; next }
    found && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { exit }
    found { print }
  ' "$file"
}

assert_saturation_healthcheck() {
  local file="$1" service="$2"
  local block
  block="$(service_block "$REPO_ROOT/$file" "$service")"

  [[ -n "$block" ]]
  [[ "$block" == *"healthcheck:"* ]]
  [[ "$block" != *"pg_isready"* ]]
  [[ "$block" == *"psql -U"* ]]
  [[ "$block" == *"pg_stat_activity"* ]]
  [[ "$block" == *"current_setting('max_connections')"* ]]
  [[ "$block" == *"superuser_reserved_connections"* ]]
  [[ "$block" == *"grep -qx 1"* ]]
}

@test "root compose Postgres healthchecks are saturation-aware" {
  assert_saturation_healthcheck "compose.yml" "postgres"
  assert_saturation_healthcheck "compose.yml" "plane-db"
  assert_saturation_healthcheck "compose.yml" "penpot-postgres"
  assert_saturation_healthcheck "compose.yml" "synapse-db"
}

@test "authentik Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/authentik/compose.yml" "authentik-postgresql"
}

@test "forgejo Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/forgejo/compose.yml" "forgejo-db"
}

@test "infisical Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/infisical/compose.yml" "infisical-db"
}

@test "langfuse Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/langfuse/compose.yml" "langfuse-postgres"
}

@test "listmonk Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/listmonk/compose.yml" "listmonk-db"
}

@test "metabase Postgres healthchecks are saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/metabase/compose.yml" "metabase-pg"
  assert_saturation_healthcheck "setup/walter-host/services/metabase/compose.yml" "social-pg"
}

@test "n8n Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/n8n/compose.yml" "n8n-pg"
}

@test "penpot Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/penpot/compose.yml" "penpot-postgres"
}

@test "analytics Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/postgres/compose.yml" "postgres-analytics"
}

@test "postiz Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/postiz/compose.yml" "postiz-pg"
}

@test "synapse Postgres healthcheck is saturation-aware" {
  assert_saturation_healthcheck "setup/walter-host/services/synapse/compose.yml" "synapse-db"
}
