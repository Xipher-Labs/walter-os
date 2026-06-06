#!/usr/bin/env bats
# Static assertions for sub-router MODEL_MAP_JSON overrides.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_router_model_map_json_contract() {
  local router="$1"
  local dir="$ROUTER_ROOT/$router"
  local server="$dir/server.js"
  local compose="$dir/docker-compose.yml"
  local env_template="$dir/.env.template"

  [[ -f "$server" ]]
  [[ -f "$compose" ]]
  [[ -f "$env_template" ]]

  grep -q "const DEFAULT_MODEL_MAP" "$server"
  grep -q "function loadModelMap" "$server"
  grep -q "process.env.MODEL_MAP_JSON" "$server"
  grep -q "const normalizedMap" "$server"
  grep -q "normalizedAlias = alias.trim()" "$server"
  grep -q "normalizedModel = typeof model === 'string' ? model.trim() : ''" "$server"
  grep -q "normalizedMap\\[normalizedAlias\\] = normalizedModel" "$server"
  grep -q "MODEL_MAP_JSON" "$compose"
  grep -q "MODEL_MAP_JSON" "$env_template"
}

@test "chatgpt-codex-router supports MODEL_MAP_JSON" {
  assert_router_model_map_json_contract "chatgpt-codex-router"
}

@test "claude-sub-router supports MODEL_MAP_JSON" {
  assert_router_model_map_json_contract "claude-sub-router"
}

@test "gemini-sub-router supports MODEL_MAP_JSON" {
  assert_router_model_map_json_contract "gemini-sub-router"
}
