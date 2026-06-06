#!/usr/bin/env bats
# Static assertions for subscription-router deploy smoke tests.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
  PATTERN_DIR="$ROUTER_ROOT/subscription-router-pattern"
  LITELLM_CONFIG="$ROUTER_ROOT/litellm/config.yaml"
  LITELLM_COMPOSE="$ROUTER_ROOT/litellm/compose.yml"
}

assert_router_deploy_contract() {
  local router="$1"
  local port="$2"
  local key_env="$3"
  local litellm_aliases="$4"
  local deploy="$ROUTER_ROOT/$router/deploy.sh"

  [[ -x "$deploy" ]]
  grep -Fq 'subscription-router-pattern/deploy-router.sh' "$deploy"
  grep -Fq "\"$router\"" "$deploy"
  grep -Fq "\"$port\"" "$deploy"
  grep -Fq "\"$key_env\"" "$deploy"
  grep -Fq "\"$litellm_aliases\"" "$deploy"
}

@test "shared deploy smoke helper probes advertised router models" {
  local smoke="$PATTERN_DIR/deploy-smoke.sh"
  [[ -x "$smoke" ]]

  grep -Fq '/v1/models' "$smoke"
  grep -Fq 'ROUTER_API_KEY' "$smoke"
  grep -Fq 'models_code=' "$smoke"
  grep -Fq 'HTTP ${models_code}' "$smoke"
  grep -Fq ': > "$tmp_body"' "$smoke"
  ! grep -Fq '2>/dev/null' "$smoke"
  grep -Fq 'sed -n' "$smoke"
  grep -Fq 'failed to parse ${ROUTER_NAME} /v1/models response' "$smoke"
  grep -Fq 'payload.get("data"' "$smoke"
  grep -Fq '/v1/chat/completions' "$smoke"
  grep -Fq 'max_tokens' "$smoke"
  grep -Fq 'ROUTER_SMOKE_TIMEOUT_SECONDS' "$smoke"
  grep -Fq 'no advertised models' "$smoke"
}

@test "shared deploy smoke helper can verify LiteLLM alias hop" {
  local smoke="$PATTERN_DIR/deploy-smoke.sh"
  [[ -x "$smoke" ]]

  grep -Fq 'LITELLM_SMOKE_MODELS' "$smoke"
  grep -Fq 'LITELLM_BASE_URL' "$smoke"
  grep -Fq 'LITELLM_MASTER_KEY' "$smoke"
  grep -Fq 'LITELLM_API_KEY' "$smoke"
  grep -Fq 'LITELLM_ENV_FILE' "$smoke"
}

@test "router deploy helper waits for health and runs smoke" {
  local helper="$PATTERN_DIR/deploy-router.sh"
  [[ -x "$helper" ]]

  grep -Fq 'docker compose' "$helper"
  grep -Fq 'docker inspect' "$helper"
  grep -Fq 'State.Health.Status' "$helper"
  grep -Fq 'deploy-smoke.sh' "$helper"
  grep -Fq 'ROUTER_BASE_URL' "$helper"
  grep -Fq 'invalid router port' "$helper"
  grep -Fq 'invalid router API-key env var name' "$helper"
}

@test "each subscription router deploys with a real model smoke" {
  assert_router_deploy_contract "chatgpt-codex-router" "1456" "CCR_APIKEY" "codex-sub,codex-sub-think"
  assert_router_deploy_contract "claude-sub-router" "1457" "CSR_APIKEY" "claude-sub,claude-sub-opus"
  assert_router_deploy_contract "gemini-sub-router" "1458" "GSR_APIKEY" "gemini-sub,gemini-sub-flash"
}

@test "LiteLLM subscription aliases point at the current sub-routers" {
  [[ -f "$LITELLM_CONFIG" ]]

  grep -Fq "model_name: codex-sub" "$LITELLM_CONFIG"
  grep -Fq "model_name: codex-sub-think" "$LITELLM_CONFIG"
  grep -Fq "api_base: http://chatgpt-codex-router:1456/v1" "$LITELLM_CONFIG"
  grep -Fq "api_key: os.environ/CCR_APIKEY" "$LITELLM_CONFIG"

  grep -Fq "model_name: claude-sub" "$LITELLM_CONFIG"
  grep -Fq "model_name: claude-sub-opus" "$LITELLM_CONFIG"
  grep -Fq "api_base: http://claude-sub-router:1457/v1" "$LITELLM_CONFIG"
  grep -Fq "api_key: os.environ/CSR_APIKEY" "$LITELLM_CONFIG"

  grep -Fq "model_name: gemini-sub" "$LITELLM_CONFIG"
  grep -Fq "model_name: gemini-sub-flash" "$LITELLM_CONFIG"
  grep -Fq "api_base: http://gemini-sub-router:1458/v1" "$LITELLM_CONFIG"
  grep -Fq "api_key: os.environ/GSR_APIKEY" "$LITELLM_CONFIG"

  ! grep -Fq "claude-code-router:3456" "$LITELLM_CONFIG"
}

@test "LiteLLM compose passes subscription router keys" {
  [[ -f "$LITELLM_COMPOSE" ]]

  grep -Fq 'CCR_APIKEY: ${CCR_APIKEY:-}' "$LITELLM_COMPOSE"
  grep -Fq 'CSR_APIKEY: ${CSR_APIKEY:-}' "$LITELLM_COMPOSE"
  grep -Fq 'GSR_APIKEY: ${GSR_APIKEY:-}' "$LITELLM_COMPOSE"
}
