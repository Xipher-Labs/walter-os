#!/usr/bin/env bats
# Static coverage for core/network service resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SERVICE_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_service_limits() {
  local compose="$1"
  local service="$2"

  [[ -f "$compose" ]]

  python3 - "$compose" "$service" <<'PY'
import sys
import yaml

compose_path, service_name = sys.argv[1], sys.argv[2]
with open(compose_path, "r", encoding="utf-8") as fh:
    compose = yaml.safe_load(fh)

service = compose["services"][service_name]
for key in ("mem_limit", "mem_reservation", "cpus", "pids_limit"):
    assert key in service, f"{service_name} missing {key}"
    assert service[key] not in ("", None), f"{service_name} has empty {key}"
PY
}

@test "homepage has resource limits" {
  local compose="$SERVICE_ROOT/homepage/compose.yml"
  assert_service_limits "$compose" "homepage"
  grep -q 'HOMEPAGE_MEM_LIMIT:-256m' "$compose"
}

@test "uptime-kuma has resource limits" {
  local compose="$SERVICE_ROOT/uptime-kuma/compose.yml"
  assert_service_limits "$compose" "uptime-kuma"
  grep -q 'UPTIME_KUMA_MEM_LIMIT:-384m' "$compose"
}

@test "headscale services have resource limits" {
  local compose="$SERVICE_ROOT/headscale/compose.yml"
  assert_service_limits "$compose" "headscale"
  assert_service_limits "$compose" "headscale-admin"
  grep -q 'HEADSCALE_MEM_LIMIT:-256m' "$compose"
  grep -q 'HEADSCALE_ADMIN_MEM_LIMIT:-128m' "$compose"
}

@test "wireguard has resource limits" {
  local compose="$SERVICE_ROOT/wireguard/compose.yml"
  assert_service_limits "$compose" "wg-easy"
  grep -q 'WIREGUARD_MEM_LIMIT:-256m' "$compose"
}
