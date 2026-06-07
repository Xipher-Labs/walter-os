#!/usr/bin/env bats
# Static and render coverage for lightweight service resource limits.

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
    "mem_limit": f"${{{prefix}_MEM_LIMIT:-",
    "mem_reservation": f"${{{prefix}_MEM_RESERVATION:-",
    "cpus": f"${{{prefix}_CPUS:-",
    "pids_limit": f"${{{prefix}_PIDS_LIMIT:-",
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
    FORGEJO_DB_PASS=test \
    FORGEJO_INSTANCE_URL=https://git.example.com \
    RENOVATE_TOKEN=test \
    CONTROL_TOWER_ADMIN_TOKEN=test \
    docker compose -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "forgejo services have overrideable resource limits" {
  assert_service_limits "forgejo" "forgejo" "FORGEJO"
  assert_service_limits "forgejo" "forgejo-db" "FORGEJO_DB"
}

@test "developer automation services have overrideable resource limits" {
  assert_service_limits "forgejo-runner" "forgejo-runner" "FORGEJO_RUNNER"
  assert_service_limits "renovate" "renovate" "RENOVATE"
}

@test "lightweight UI and sync services have overrideable resource limits" {
  assert_service_limits "control-tower" "control-tower" "CONTROL_TOWER"
  assert_service_limits "drawio" "drawio" "DRAWIO"
  assert_service_limits "ntfy" "ntfy" "NTFY"
  assert_service_limits "syncthing" "syncthing" "SYNCTHING"
}

@test "lightweight service compose files render with defaults" {
  assert_compose_renders "forgejo"
  assert_compose_renders "forgejo-runner"
  assert_compose_renders "renovate"
  assert_compose_renders "control-tower"
  assert_compose_renders "drawio"
  assert_compose_renders "ntfy"
  assert_compose_renders "syncthing"
}
