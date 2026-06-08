#!/usr/bin/env bats
# Static coverage for subscription-router per-container resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_router_limits() {
  local router="$1"
  local mem_limit_env="$2"
  local mem_reservation_env="$3"
  local cpus_env="$4"
  local pids_env="$5"
  local compose="$ROUTER_ROOT/$router/docker-compose.yml"
  local service_block

  [[ -f "$compose" ]]
  service_block="$(
    awk -v router="$router" '
      $0 ~ "^  " router ":" { flag=1; next }
      flag && $0 ~ "^  [a-zA-Z0-9_-]+:" { flag=0 }
      flag { print }
    ' "$compose"
  )"

  printf '%s\n' "$service_block" \
    | grep -Fxq "    mem_limit: \"\${${mem_limit_env}:-512m}\""
  printf '%s\n' "$service_block" \
    | grep -Fxq "    mem_reservation: \"\${${mem_reservation_env}:-256m}\""
  printf '%s\n' "$service_block" \
    | grep -Fxq "    cpus: \"\${${cpus_env}:-1.0}\""
  printf '%s\n' "$service_block" \
    | grep -Fxq "    pids_limit: \"\${${pids_env}:-256}\""
}

assert_router_compose_renders() {
  local router="$1"
  local api_env="$2"
  local service_path="$ROUTER_ROOT/$router"
  local compose="$ROUTER_ROOT/$router/docker-compose.yml"

  if [ "${WALTER_COMPOSE_TEST:-0}" != "1" ]; then
    skip "set WALTER_COMPOSE_TEST=1 to run docker compose render checks"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    skip "docker is not installed"
  fi
  if ! docker compose version >/dev/null 2>&1; then
    skip "docker compose is not available"
  fi

  run env "$api_env=test" docker compose --project-directory "$service_path" -f "$compose" config --quiet
  [ "$status" -eq 0 ]
}

@test "chatgpt-codex-router has resource limits" {
  assert_router_limits \
    "chatgpt-codex-router" \
    "CHATGPT_CODEX_ROUTER_MEM_LIMIT" \
    "CHATGPT_CODEX_ROUTER_MEM_RESERVATION" \
    "CHATGPT_CODEX_ROUTER_CPUS" \
    "CHATGPT_CODEX_ROUTER_PIDS_LIMIT"
}

@test "claude-sub-router has resource limits" {
  assert_router_limits \
    "claude-sub-router" \
    "CLAUDE_SUB_ROUTER_MEM_LIMIT" \
    "CLAUDE_SUB_ROUTER_MEM_RESERVATION" \
    "CLAUDE_SUB_ROUTER_CPUS" \
    "CLAUDE_SUB_ROUTER_PIDS_LIMIT"
}

@test "gemini-sub-router has resource limits" {
  assert_router_limits \
    "gemini-sub-router" \
    "GEMINI_SUB_ROUTER_MEM_LIMIT" \
    "GEMINI_SUB_ROUTER_MEM_RESERVATION" \
    "GEMINI_SUB_ROUTER_CPUS" \
    "GEMINI_SUB_ROUTER_PIDS_LIMIT"
}

@test "router compose files render with resource limit defaults" {
  assert_router_compose_renders "chatgpt-codex-router" "CCR_APIKEY"
  assert_router_compose_renders "claude-sub-router" "CSR_APIKEY"
  assert_router_compose_renders "gemini-sub-router" "GSR_APIKEY"
}
