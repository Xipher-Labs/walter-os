#!/usr/bin/env bats
# Static assertions for sub-router startup model probes.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_router_startup_model_probe_contract() {
  local router="$1"
  local dir="$ROUTER_ROOT/$router"
  local server="$dir/server.js"
  local compose="$dir/docker-compose.yml"
  local env_template="$dir/.env.template"

  [[ -f "$server" ]]
  [[ -f "$compose" ]]
  [[ -f "$env_template" ]]

  grep -q "ROUTER_STARTUP_MODEL_PROBE" "$server"
  grep -q "function startupModelProbeEnabled" "$server"
  grep -q "function startupModelProbeTimeoutMs" "$server"
  grep -q "async function postStartupModelProbe" "$server"
  grep -q "async function runStartupModelProbes" "$server"
  grep -q "ROUTER_STARTUP_MODEL_PROBE_TIMEOUT_MS" "$server"
  grep -q "AbortController" "$server"
  grep -q "probe timed out after" "$server"
  grep -q "Object.entries(MODEL_MAP)" "$server"
  grep -q 'model: `openai/${alias}`' "$server"
  grep -q "STARTUP_MODEL_PROBE_HEADER_VALUE" "$server"
  grep -q "function startupModelProbeReadinessError" "$server"
  grep -q "function isStartupModelProbeRequest" "$server"
  grep -q "/v1/chat/completions" "$server"
  grep -q "Startup model probe failed for advertised model slug" "$server"
  grep -q "mapped to" "$server"
  ! grep -q "server.close(() => process.exit(78))" "$server"
  ! grep -q "setTimeout(() => process.exit(78)" "$server"
  grep -q "startup_model_probe_failed" "$server"
  grep -q "startup_model_probe_passed" "$server"
  grep -q "server_started_with_failed_startup_model_probe" "$server"
  grep -q "startup model probe pending" "$server"

  grep -q 'ROUTER_STARTUP_MODEL_PROBE: "${ROUTER_STARTUP_MODEL_PROBE:-1}"' "$compose"
  grep -q 'ROUTER_STARTUP_MODEL_PROBE_TIMEOUT_MS: "${ROUTER_STARTUP_MODEL_PROBE_TIMEOUT_MS:-240000}"' "$compose"
  grep -q "start_period: 10m" "$compose"
  grep -q "ROUTER_STARTUP_MODEL_PROBE" "$env_template"
  grep -q "ROUTER_STARTUP_MODEL_PROBE_TIMEOUT_MS" "$env_template"
}

@test "chatgpt-codex-router probes advertised models at startup" {
  assert_router_startup_model_probe_contract "chatgpt-codex-router"
}

@test "claude-sub-router probes advertised models at startup" {
  assert_router_startup_model_probe_contract "claude-sub-router"
}

@test "gemini-sub-router probes advertised models at startup" {
  assert_router_startup_model_probe_contract "gemini-sub-router"
}
