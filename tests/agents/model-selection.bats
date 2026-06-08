#!/usr/bin/env bats
# Tests for agent model selection safety around LiteLLM-only aliases.

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  LIB="$REPO_ROOT/scripts/agents/lib/model-selection.sh"
  ROUTER="$REPO_ROOT/scripts/walter/lib/model-router.sh"
  [[ -f "$LIB" ]] || skip "model-selection.sh not found"
  [[ -f "$ROUTER" ]] || skip "model-router.sh not found"

  TEST_CONFIG="$(mktemp -d -t walter-model-selection-XXXXXX)"
  export WALTER_AI_CAPABILITIES_FILE="$TEST_CONFIG/missing-ai-capabilities.yaml"
  unset LITELLM_BASE_URL LITELLM_API_KEY
  unset WALTER_MODEL_BACKEND_REVIEW WALTER_MODEL_DEFAULT WALTER_MODEL_OVERRIDE
}

teardown() {
  rm -rf "$TEST_CONFIG"
}

@test "agent model selection fails closed when router is missing" {
  run bash -c '
    source "$1"
    WALTER_MODEL_ROUTER_SH="/tmp/does-not-exist"
    walter_agent_select_model backend_review MODEL
  ' _ "$LIB"

  [ "$status" -eq 3 ]
  echo "$output" | grep -q "model router not found"
}

@test "agent model selection rejects LiteLLM-only aliases for direct Anthropic" {
  run bash -c '
    source "$1"
    export WALTER_MODEL_ROUTER_SH="$2"
    export WALTER_MODEL_BACKEND_REVIEW=codex
    walter_agent_select_model backend_review MODEL
  ' _ "$LIB" "$ROUTER"

  [ "$status" -eq 3 ]
  echo "$output" | grep -q "requires LiteLLM"
  echo "$output" | grep -q "WALTER_MODEL_BACKEND_REVIEW=sonnet"
}

@test "agent model selection accepts Anthropic-compatible aliases without LiteLLM" {
  run bash -c '
    source "$1"
    export WALTER_MODEL_ROUTER_SH="$2"
    export WALTER_MODEL_BACKEND_REVIEW=sonnet
    walter_agent_select_model backend_review MODEL
    printf "%s\n" "$MODEL"
  ' _ "$LIB" "$ROUTER"

  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "agent model selection allows LiteLLM-only aliases when LiteLLM is configured" {
  run bash -c '
    source "$1"
    export WALTER_MODEL_ROUTER_SH="$2"
    export WALTER_MODEL_BACKEND_REVIEW=codex
    export LITELLM_BASE_URL=http://litellm.test
    export LITELLM_API_KEY=sk-test
    walter_agent_select_model backend_review MODEL
    printf "%s\n" "$MODEL"
  ' _ "$LIB" "$ROUTER"

  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "agent model selection can fall back safely for lesson extraction" {
  run bash -c '
    source "$1"
    export WALTER_MODEL_ROUTER_SH="$2"
    export WALTER_MODEL_DEFAULT=claude
    walter_agent_select_model default MODEL sonnet
    printf "%s\n" "$MODEL"
  ' _ "$LIB" "$ROUTER"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sonnet"
}
