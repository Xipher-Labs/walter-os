#!/usr/bin/env bats
# Static and render coverage for product/design service resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SERVICES_ROOT="$REPO_ROOT/setup/walter-host/services"
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 is not installed"
  fi
  if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    skip "PyYAML is not installed"
  fi
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
    POSTGRES_USER=plane \
    POSTGRES_PASSWORD=test \
    POSTGRES_DB=plane \
    RABBITMQ_USER=plane \
    RABBITMQ_PASSWORD=test \
    RABBITMQ_VHOST=plane \
    AWS_ACCESS_KEY_ID=test \
    AWS_SECRET_ACCESS_KEY=test \
    PENPOT_DB_PASS=test \
    PENPOT_SECRET_KEY=test-penpot-secret-key \
    docker compose --project-directory "$tmpdir" -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "plane application services have overrideable resource limits" {
  assert_service_limits "plane" "web" "PLANE_WEB"
  assert_service_limits "plane" "admin" "PLANE_ADMIN"
  assert_service_limits "plane" "space" "PLANE_SPACE"
  assert_service_limits "plane" "live" "PLANE_LIVE"
  assert_service_limits "plane" "api" "PLANE_API"
  assert_service_limits "plane" "worker" "PLANE_WORKER"
  assert_service_limits "plane" "beat-worker" "PLANE_BEAT_WORKER"
  assert_service_limits "plane" "migrator" "PLANE_MIGRATOR"
  assert_service_limits "plane" "proxy" "PLANE_PROXY"
}

@test "plane dependency services have overrideable resource limits" {
  assert_service_limits "plane" "plane-db" "PLANE_DB"
  assert_service_limits "plane" "plane-redis" "PLANE_REDIS"
  assert_service_limits "plane" "plane-mq" "PLANE_MQ"
  assert_service_limits "plane" "plane-minio" "PLANE_MINIO"
}

@test "penpot stack has overrideable resource limits" {
  assert_service_limits "penpot" "penpot-frontend" "PENPOT_FRONTEND"
  assert_service_limits "penpot" "penpot-backend" "PENPOT_BACKEND"
  assert_service_limits "penpot" "penpot-exporter" "PENPOT_EXPORTER"
  assert_service_limits "penpot" "penpot-postgres" "PENPOT_POSTGRES"
  assert_service_limits "penpot" "penpot-redis" "PENPOT_REDIS"
}

@test "product service compose files render with defaults" {
  assert_compose_renders "plane"
  assert_compose_renders "penpot"
}
