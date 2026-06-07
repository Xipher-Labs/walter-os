#!/usr/bin/env bats
# Static coverage for core/network service resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SERVICE_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_service_limits() {
  local compose="$1"
  local service="$2"
  local prefix="$3"

  [[ -f "$compose" ]]

  python3 - "$compose" "$service" "$prefix" <<'PY'
import sys
import yaml

compose_path, service_name, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
with open(compose_path, "r", encoding="utf-8") as fh:
    compose = yaml.safe_load(fh)

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
  local compose="$SERVICE_ROOT/$service_dir/compose.yml"
  local tmpdir="$BATS_TEST_TMPDIR/$service_dir"

  if ! command -v docker >/dev/null 2>&1; then
    skip "docker is not installed"
  fi
  if ! docker compose version >/dev/null 2>&1; then
    skip "docker compose is not available"
  fi

  mkdir -p "$tmpdir"
  cp "$compose" "$tmpdir/compose.yml"

  run env \
    WALTER_DOMAIN=example.com \
    WALTER_TELEGRAM_BOT_HANDLE=test \
    WALTER_OPENCLAW_BOT_HANDLE=test \
    WG_PASSWORD_HASH=test \
    docker compose --project-directory "$tmpdir" -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "homepage has resource limits" {
  local compose="$SERVICE_ROOT/homepage/compose.yml"
  assert_service_limits "$compose" "homepage" "HOMEPAGE"
}

@test "uptime-kuma has resource limits" {
  local compose="$SERVICE_ROOT/uptime-kuma/compose.yml"
  assert_service_limits "$compose" "uptime-kuma" "UPTIME_KUMA"
}

@test "headscale services have resource limits" {
  local compose="$SERVICE_ROOT/headscale/compose.yml"
  assert_service_limits "$compose" "headscale" "HEADSCALE"
  assert_service_limits "$compose" "headscale-admin" "HEADSCALE_ADMIN"
}

@test "wireguard has resource limits" {
  local compose="$SERVICE_ROOT/wireguard/compose.yml"
  assert_service_limits "$compose" "wg-easy" "WIREGUARD"
}

@test "core service compose files render with defaults" {
  assert_compose_renders "homepage"
  assert_compose_renders "uptime-kuma"
  assert_compose_renders "headscale"
  assert_compose_renders "wireguard"
}
