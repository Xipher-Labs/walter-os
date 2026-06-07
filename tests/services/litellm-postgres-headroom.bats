#!/usr/bin/env bats
# Static contract for LiteLLM Postgres saturation detection and headroom.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/setup/walter-host/services/litellm/compose.yml"
}

@test "litellm-db has explicit connection and buffer headroom" {
  grep -q 'max_connections=200' "$COMPOSE_FILE"
  grep -q 'shared_buffers=256MB' "$COMPOSE_FILE"
  grep -q 'superuser_reserved_connections=5' "$COMPOSE_FILE"
}

@test "litellm-db healthcheck fails before connection saturation" {
  ! grep -q 'pg_isready -U litellm' "$COMPOSE_FILE"
  grep -q 'psql -U litellm -d litellm' "$COMPOSE_FILE"
  grep -q 'pg_stat_activity' "$COMPOSE_FILE"
  grep -q "current_setting('max_connections')" "$COMPOSE_FILE"
  grep -q "current_setting('superuser_reserved_connections')" "$COMPOSE_FILE"
  grep -q 'grep -qx 1' "$COMPOSE_FILE"
}
