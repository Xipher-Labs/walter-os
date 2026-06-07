#!/usr/bin/env bats
# Static and render coverage for business/automation service resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SERVICES_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_service_limits() {
  local service_dir="$1"
  local service_name="$2"
  local prefix="$3"
  local compose="$SERVICES_ROOT/$service_dir/compose.yml"

  [[ -f "$compose" ]]

  python3 - "$compose" "$service_name" "$prefix" <<'PY'
import sys
import yaml

compose_path, service_name, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
with open(compose_path, "r", encoding="utf-8") as handle:
    compose = yaml.safe_load(handle)

service = compose["services"][service_name]
expected = {
    "mem_limit": "${" + prefix + "_MEM_LIMIT:-",
    "mem_reservation": "${" + prefix + "_MEM_RESERVATION:-",
    "cpus": "${" + prefix + "_CPUS:-",
    "pids_limit": "${" + prefix + "_PIDS_LIMIT:-",
}
for key, marker in expected.items():
    value = service.get(key)
    assert value, f"{service_name} missing {key}"
    assert str(value).startswith(marker), f"{service_name} {key} is not overrideable by {prefix}: {value!r}"
PY
}

assert_compose_renders() {
  local service_dir="$1"
  local compose="$SERVICES_ROOT/$service_dir/compose.yml"
  local tmpdir="$BATS_TEST_TMPDIR/$service_dir"

  if [ "${WALTER_COMPOSE_TEST:-0}" != "1" ]; then
    skip "set WALTER_COMPOSE_TEST=1 to run docker compose render checks"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    skip "docker is not installed"
  fi
  if ! docker compose version >/dev/null 2>&1; then
    skip "docker compose is not available"
  fi

  mkdir -p "$tmpdir"
  cp "$compose" "$tmpdir/compose.yml"
  touch "$tmpdir/.env"

  run env \
    WALTER_DOMAIN=example.com \
    WALTER_TIMEZONE=UTC \
    INFISICAL_ENCRYPTION_KEY=test-infisical-encryption-key \
    INFISICAL_AUTH_SECRET=test-infisical-auth-secret \
    INFISICAL_DB_PASS=test \
    INFISICAL_REDIS_PASS=test \
    N8N_PG_PASS=test \
    N8N_ENCRYPTION_KEY=test-n8n-encryption-key \
    N8N_BASIC_AUTH_USER=test \
    N8N_BASIC_AUTH_PASSWORD=test-password \
    METABASE_DB_PASS=test \
    METABASE_ENCRYPTION_KEY=test-metabase-encryption-key \
    SOCIAL_PG_PASS=test \
    POSTIZ_PG_PASS=test \
    POSTIZ_JWT_SECRET=test-postiz-jwt-secret \
    RESEND_API_KEY=test \
    SYNAPSE_DB_PASS=test \
    docker compose --project-directory "$tmpdir" -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "infisical stack has overrideable resource limits" {
  assert_service_limits "infisical" "infisical-backend" "INFISICAL_BACKEND"
  assert_service_limits "infisical" "infisical-db" "INFISICAL_DB"
  assert_service_limits "infisical" "infisical-redis" "INFISICAL_REDIS"
}

@test "automation and BI stacks have overrideable resource limits" {
  assert_service_limits "n8n" "n8n" "N8N"
  assert_service_limits "n8n" "n8n-pg" "N8N_PG"
  assert_service_limits "metabase" "metabase" "METABASE"
  assert_service_limits "metabase" "metabase-pg" "METABASE_PG"
  assert_service_limits "metabase" "social-pg" "SOCIAL_PG"
}

@test "marketing and communications stacks have overrideable resource limits" {
  assert_service_limits "postiz" "postiz" "POSTIZ"
  assert_service_limits "postiz" "postiz-pg" "POSTIZ_PG"
  assert_service_limits "postiz" "postiz-redis" "POSTIZ_REDIS"
  assert_service_limits "rocketchat" "rocketchat" "ROCKETCHAT"
  assert_service_limits "rocketchat" "rocketchat-mongo" "ROCKETCHAT_MONGO"
}

@test "matrix stack has overrideable resource limits" {
  assert_service_limits "synapse" "synapse" "SYNAPSE"
  assert_service_limits "synapse" "synapse-db" "SYNAPSE_DB"
  assert_service_limits "synapse" "element-web" "ELEMENT_WEB"
}

@test "business service compose files render with defaults" {
  assert_compose_renders "infisical"
  assert_compose_renders "n8n"
  assert_compose_renders "metabase"
  assert_compose_renders "postiz"
  assert_compose_renders "rocketchat"
  assert_compose_renders "synapse"
}
