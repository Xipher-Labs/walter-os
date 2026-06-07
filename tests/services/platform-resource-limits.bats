#!/usr/bin/env bats
# Static and render coverage for platform/observability service resource limits.

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
    ANALYTICS_PG_PASS=test \
    GF_ADMIN_PASSWORD=test \
    WALTER_TELEGRAM_BOT_TOKEN=test \
    WALTER_TELEGRAM_CHAT_ID=test \
    OBSERVABILITY_DATA_DIR="$tmpdir/data" \
    docker compose --project-directory "$tmpdir" -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "postgres analytics service has overrideable resource limits" {
  assert_service_limits "postgres" "postgres-analytics" "POSTGRES_ANALYTICS"
}

@test "observability stack has overrideable resource limits" {
  assert_service_limits "observability" "prometheus" "PROMETHEUS"
  assert_service_limits "observability" "loki" "LOKI"
  assert_service_limits "observability" "promtail" "PROMTAIL"
  assert_service_limits "observability" "node-exporter" "NODE_EXPORTER"
  assert_service_limits "observability" "cadvisor" "CADVISOR"
  assert_service_limits "observability" "grafana" "GRAFANA"
}

@test "seaweedfs has overrideable resource limits" {
  assert_service_limits "seaweedfs" "seaweedfs" "SEAWEEDFS"
}

@test "platform service compose files render with defaults" {
  assert_compose_renders "postgres"
  assert_compose_renders "observability"
  assert_compose_renders "seaweedfs"
}
