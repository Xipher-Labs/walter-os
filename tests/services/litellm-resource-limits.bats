#!/usr/bin/env bats
# Static coverage for LiteLLM per-container resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/setup/walter-host/services/litellm/compose.yml"
  RESOURCE_BUDGET="$REPO_ROOT/docs/operational/resource-budget.md"
}

@test "litellm compose declares shared Walter resource limit anchors" {
  [[ -f "$COMPOSE_FILE" ]]

  grep -q '^x-walter-limits:' "$COMPOSE_FILE"
  grep -q '&limits-litellm$' "$COMPOSE_FILE"
  grep -q '&limits-litellm-db$' "$COMPOSE_FILE"
  grep -q '&limits-litellm-pgbouncer$' "$COMPOSE_FILE"
}

@test "every litellm service has cpu memory and pids limits" {
  python3 - "$COMPOSE_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    compose = yaml.safe_load(fh)

for service_name in ("litellm", "litellm-db", "litellm-pgbouncer"):
    service = compose["services"][service_name]
    for key in ("mem_limit", "mem_reservation", "cpus", "pids_limit"):
        assert key in service, f"{service_name} missing {key}"
        assert service[key] not in ("", None), f"{service_name} has empty {key}"
PY
}

@test "litellm resource limits are overrideable by environment" {
  [[ -f "$COMPOSE_FILE" ]]

  grep -q 'LITELLM_MEM_LIMIT:-1024m' "$COMPOSE_FILE"
  grep -q 'LITELLM_DB_MEM_LIMIT:-1024m' "$COMPOSE_FILE"
  grep -q 'LITELLM_PGBOUNCER_MEM_LIMIT:-128m' "$COMPOSE_FILE"
}

@test "resource budget documents LiteLLM service caps" {
  [[ -f "$RESOURCE_BUDGET" ]]

  grep -q "LiteLLM resource caps" "$RESOURCE_BUDGET"
  grep -q "LITELLM_MEM_LIMIT" "$RESOURCE_BUDGET"
  grep -q "LITELLM_DB_MEM_LIMIT" "$RESOURCE_BUDGET"
  grep -q "LITELLM_PGBOUNCER_MEM_LIMIT" "$RESOURCE_BUDGET"
}
