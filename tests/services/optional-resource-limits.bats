#!/usr/bin/env bats
# Static and render coverage for optional service resource limits.

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
    assert str(value).startswith(marker), f"{service_name} {key} is not overridable by {prefix}: {value!r}"
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
    AUTHENTIK_SECRET_KEY=test-authentik-secret-key \
    AUTHENTIK_POSTGRESQL__PASSWORD=test \
    NEXTAUTH_SECRET=test-nextauth-secret \
    SALT=test-salt \
    ENCRYPTION_KEY=test-encryption-key \
    LANGFUSE_DB_PASSWORD=test \
    CLICKHOUSE_PASSWORD=test \
    REDIS_AUTH=test \
    MINIO_ROOT_USER=test \
    MINIO_ROOT_PASSWORD=test-password \
    LISTMONK_POSTGRES_PASSWORD=test \
    LISTMONK_ADMIN_USER=test \
    LISTMONK_ADMIN_PASSWORD=test-password \
    docker compose --project-directory "$tmpdir" -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "authentik stack has overridable resource limits" {
  assert_service_limits "authentik" "authentik-postgresql" "AUTHENTIK_POSTGRESQL"
  assert_service_limits "authentik" "authentik-redis" "AUTHENTIK_REDIS"
  assert_service_limits "authentik" "authentik-server" "AUTHENTIK_SERVER"
  assert_service_limits "authentik" "authentik-worker" "AUTHENTIK_WORKER"
}

@test "langfuse stack has overridable resource limits" {
  assert_service_limits "langfuse" "langfuse-web" "LANGFUSE_WEB"
  assert_service_limits "langfuse" "langfuse-worker" "LANGFUSE_WORKER"
  assert_service_limits "langfuse" "langfuse-postgres" "LANGFUSE_POSTGRES"
  assert_service_limits "langfuse" "langfuse-clickhouse" "LANGFUSE_CLICKHOUSE"
  assert_service_limits "langfuse" "langfuse-redis" "LANGFUSE_REDIS"
  assert_service_limits "langfuse" "langfuse-minio" "LANGFUSE_MINIO"
}

@test "listmonk stack has overridable resource limits" {
  assert_service_limits "listmonk" "listmonk" "LISTMONK"
  assert_service_limits "listmonk" "listmonk-db" "LISTMONK_DB"
}

@test "optional service compose files render with defaults" {
  assert_compose_renders "authentik"
  assert_compose_renders "langfuse"
  assert_compose_renders "listmonk"
}
