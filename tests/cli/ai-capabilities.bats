#!/usr/bin/env bats
# tests/cli/ai-capabilities.bats
#
# Covers issue #401: operator-declared AI capability profiles.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_BIN="${REPO_ROOT}/bin/walter"

setup() {
  TEST_HOME="$(mktemp -d)"
  TEST_BIN="${TEST_HOME}/bin"
  export HOME="$TEST_HOME"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_CONFIG="${TEST_HOME}/.config/walter-os"
  mkdir -p "$WALTER_CONFIG" "$TEST_BIN"
  cat >"${TEST_BIN}/gh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "${TEST_BIN}/gh"
  export PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"

  unset ANTHROPIC_API_KEY ANTHROPIC_ENTERPRISE_KEY OPENAI_API_KEY GEMINI_API_KEY OLLAMA_BASE_URL
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "walter help lists ai capability commands" {
  run bash "$WALTER_BIN" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ai status"
  echo "$output" | grep -q "ai configure"
}

@test "walter ai status works before configuration and points to configure" {
  run bash "$WALTER_BIN" ai status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AI capability status"
  echo "$output" | grep -q "walter ai configure"
  echo "$output" | grep -q "claude"
  echo "$output" | grep -q "codex"
  echo "$output" | grep -q "gemini"
  echo "$output" | grep -q "ollama"
}

@test "walter ai configure --profile codex-only writes private capability config" {
  run bash "$WALTER_BIN" ai configure --profile codex-only
  [ "$status" -eq 0 ]

  config="${WALTER_CONFIG}/ai-capabilities.yaml"
  [ -f "$config" ]
  grep -q "^provider_codex: enabled" "$config"
  grep -q "^provider_claude: disabled" "$config"
  grep -q "^route_infra_security_backend: codex" "$config"
  grep -q "^route_planning: codex" "$config"
  ! grep -q "API_KEY" "$config"
}

@test "walter ai configure --profile mixed routes image and local-only work" {
  run bash "$WALTER_BIN" ai configure --profile mixed
  [ "$status" -eq 0 ]

  config="${WALTER_CONFIG}/ai-capabilities.yaml"
  grep -q "^provider_gemini: enabled" "$config"
  grep -q "^provider_ollama: enabled" "$config"
  grep -q "^route_image_generation: gemini" "$config"
  grep -q "^route_compliance_local_only: ollama" "$config"
}

@test "walter ai configure --set overrides capability routing" {
  run bash "$WALTER_BIN" ai configure --profile claude-only --set image_generation=gemini --set research=gemini
  [ "$status" -eq 0 ]

  config="${WALTER_CONFIG}/ai-capabilities.yaml"
  grep -q "^provider_claude: enabled" "$config"
  grep -q "^provider_gemini: enabled" "$config"
  grep -q "^route_image_generation: gemini" "$config"
  grep -q "^route_research: gemini" "$config"
}

@test "walter ai configure rejects unknown profiles" {
  run bash "$WALTER_BIN" ai configure --profile unknown-profile
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown profile"
}

@test "walter ai configure rejects missing --profile value" {
  run bash "$WALTER_BIN" ai configure --profile
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--profile requires a value"
}

@test "walter ai configure rejects option-looking --profile value" {
  run bash "$WALTER_BIN" ai configure --profile --set research=gemini
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--profile requires a value"
}

@test "walter ai configure rejects missing --set value" {
  run bash "$WALTER_BIN" ai configure --profile mixed --set
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--set requires capability=provider"
}

@test "walter ai configure rejects option-looking --set value" {
  run bash "$WALTER_BIN" ai configure --profile mixed --set --help
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--set requires capability=provider"
}

@test "walter ai status shows configured routes" {
  bash "$WALTER_BIN" ai configure --profile local-only >/dev/null

  run bash "$WALTER_BIN" ai status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "config:"
  echo "$output" | grep -q "infra_security_backend.*ollama"
  echo "$output" | grep -q "compliance_local_only.*ollama"
}
