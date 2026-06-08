#!/usr/bin/env bats
# tests/skills/nanobanana-capabilities.bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GENERATE_PY="$REPO_ROOT/skills/nanobanana/scripts/generate.py"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export WALTER_CONFIG="$TEST_HOME/.config/walter-os"
  mkdir -p "$WALTER_CONFIG"
  unset GEMINI_API_KEY WALTER_AI_CAPABILITIES_FILE
}

teardown() {
  rm -rf "$TEST_HOME"
}

write_capabilities() {
  cat >"$WALTER_CONFIG/ai-capabilities.yaml"
}

@test "nanobanana blocks when Gemini provider is disabled" {
  write_capabilities <<'YAML'
profile: claude-only
provider_gemini: disabled
route_image_generation: gemini
YAML

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "provider_gemini is disabled"
  echo "$output" | grep -q "walter ai configure --profile claude-only --set image_generation=gemini"
  ! echo "$output" | grep -q "Missing deps"
}

@test "nanobanana parses capability keys with whitespace before colon" {
  write_capabilities <<'YAML'
profile: claude-only
provider_gemini : disabled
route_image_generation: gemini
YAML

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "provider_gemini is disabled"
  ! echo "$output" | grep -q "Set GEMINI_API_KEY"
}

@test "nanobanana falls back to mixed for invalid profile hints" {
  write_capabilities <<'YAML'
profile: banana-mode
provider_gemini: disabled
route_image_generation: gemini
YAML

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "walter ai configure --profile mixed --set image_generation=gemini"
  ! echo "$output" | grep -q "banana-mode --set"
}

@test "nanobanana keeps hash characters that are not YAML comments" {
  write_capabilities <<'YAML'
profile: mixed
provider_gemini: enabled
route_image_generation: gemini#preview
YAML

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "route_image_generation must include gemini"
  ! echo "$output" | grep -q "Set GEMINI_API_KEY"
}

@test "nanobanana blocks when image generation is not routed to Gemini" {
  write_capabilities <<'YAML'
profile: local-only
provider_gemini: enabled
route_image_generation: none
YAML

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "route_image_generation must include gemini"
  ! echo "$output" | grep -q "Missing deps"
}

@test "nanobanana accepts Gemini capability config before requiring API key" {
  write_capabilities <<'YAML'
profile: mixed
provider_gemini: enabled
route_image_generation: gemini
YAML

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Set GEMINI_API_KEY"
  ! echo "$output" | grep -q "Missing deps"
}

@test "nanobanana honors WALTER_AI_CAPABILITIES_FILE override" {
  custom="$TEST_HOME/custom-ai.yaml"
  cat >"$custom" <<'YAML'
profile: gemini-only
provider_gemini: enabled
route_image_generation: gemini
YAML
  export WALTER_AI_CAPABILITIES_FILE="$custom"

  run python3 "$GENERATE_PY" --prompt "test" --out "$TEST_HOME/out.png"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Set GEMINI_API_KEY"
}
