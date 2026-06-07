#!/usr/bin/env bats
# tests/walter/model-router.bats
#
# Covers issue #24 core routing contract: domain defaults, operator overrides,
# comma-separated parallel routes, and the PHI local-model lock.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER="$REPO_ROOT/scripts/walter/lib/model-router.sh"
  [[ -f "$ROUTER" ]] || skip "model-router.sh not present"
  TMP_CONFIG="$(mktemp -d)"
  export WALTER_CONFIG="$TMP_CONFIG"
  unset WALTER_AI_CAPABILITIES_FILE
}

teardown() {
  rm -rf "$TMP_CONFIG"
}

@test "model-router: unset backend_review uses Codex default" {
  run bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "model-router: per-domain env override wins" {
  run env WALTER_MODEL_FRONTEND=claude-opus bash -c "source '$ROUTER'; walter_model_for frontend"

  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus" ]
}

@test "model-router: comma-separated parallel route is preserved" {
  run env WALTER_MODEL_BRAINSTORM=claude,codex,gemini bash -c "source '$ROUTER'; walter_model_for brainstorm"

  [ "$status" -eq 0 ]
  [ "$output" = "claude,codex,gemini" ]
}

@test "model-router: WALTER_MODEL_OVERRIDE wins for non-PHI domains" {
  run env WALTER_MODEL_OVERRIDE=gemini-pro WALTER_MODEL_BACKEND_REVIEW=claude bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  [ "$output" = "gemini-pro" ]
}

@test "model-router: PHI ignores WALTER_MODEL_OVERRIDE" {
  run env WALTER_MODEL_OVERRIDE=codex WALTER_MODEL_PHI=ollama/llama3.3 bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "ollama/llama3.3" ]
}

@test "model-router: PHI rejects non-local route and falls back closed" {
  run env WALTER_MODEL_PHI=codex bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI accepts comma-separated local routes" {
  run env WALTER_MODEL_PHI='ollama/llama3,127.0.0.1:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "ollama/llama3,127.0.0.1:11434" ]
}

@test "model-router: PHI rejects mixed local and remote routes" {
  run env WALTER_MODEL_PHI='ollama/llama3,codex' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI mode reports phi metadata domain" {
  run env WALTER_PHI_MODE=1 WALTER_MODEL_PHI=ollama/llama3 bash -c "source '$ROUTER'; tmp=\"\$(mktemp)\"; walter_model_for backend_review > \"\$tmp\"; model=\"\$(cat \"\$tmp\")\"; rm -f \"\$tmp\"; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  [ "$output" = "ollama/llama3|phi" ]
}

@test "model-router: PHI rejects remote ollama-looking URLs" {
  run env WALTER_MODEL_PHI='https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects ollama URL-like aliases" {
  run env WALTER_MODEL_PHI='ollama:https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects local URL-like aliases" {
  run env WALTER_MODEL_PHI='local/https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects localhost-looking DNS names" {
  run env WALTER_MODEL_PHI='localhost.com:443' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI accepts explicit loopback aliases" {
  run env WALTER_MODEL_PHI='127.0.0.1:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "127.0.0.1:11434" ]
}

@test "model-router: PHI accepts bracketed IPv6 loopback aliases" {
  run env WALTER_MODEL_PHI='[::1]:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "[::1]:11434" ]
}

@test "model-router: invalid model values are rejected" {
  run env WALTER_MODEL_DEFAULT='claude; rm -rf /' bash -c "source '$ROUTER'; walter_model_for default" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: warns when route provider is disabled in ai-capabilities" {
  local tmpdir capabilities
  tmpdir="$(mktemp -d)"
  capabilities="$tmpdir/ai-capabilities.yaml"
  cat >"$capabilities" <<'YAML'
profile: claude-only
provider_claude: enabled
provider_codex: disabled
provider_copilot: disabled
provider_gemini: disabled
provider_ollama: disabled
route_code_review: claude
route_infra_security_backend: claude
route_planning: claude
route_ux_ui: claude
route_image_generation: none
route_research: claude
route_compliance_local_only: none
YAML

  run env WALTER_AI_CAPABILITIES_FILE="$capabilities" WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"provider_codex is disabled"* ]]
}
