#!/usr/bin/env bats
# Static and render coverage for agent/runtime service resource limits.

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
    OPENCLAW_GATEWAY_TOKEN=test \
    CCR_APIKEY=test \
    docker compose --project-directory "$tmpdir" -f "$tmpdir/compose.yml" config --quiet
  [ "$status" -eq 0 ]
}

@test "agent runtime services have overrideable resource limits" {
  assert_service_limits "openclaw" "openclaw" "OPENCLAW"
  assert_service_limits "hermes-agent" "hermes-agent" "HERMES_AGENT"
}

@test "legacy subscription proxy service has overrideable resource limits" {
  assert_service_limits "llm-proxies" "claude-code-router" "CLAUDE_CODE_ROUTER"
}

@test "agent service compose files render with defaults" {
  assert_compose_renders "openclaw"
  assert_compose_renders "hermes-agent"
  assert_compose_renders "llm-proxies"
}
