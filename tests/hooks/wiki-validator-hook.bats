#!/usr/bin/env bats
# Tests for M13: hooks/wiki-validator-hook.sh — PreToolUse JSON wrapper
# Backport of R7 from feature/council-v2-resilience to feature/council-v2-memory.

setup() {
  HOOK="$BATS_TEST_DIRNAME/../../hooks/wiki-validator-hook.sh"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  WORK_DIR="$(mktemp -d -t wiki-hook-m13-XXXXXX)"
}

teardown() {
  rm -rf "$WORK_DIR"
}

@test "M13: wiki-validator-hook.sh exists and is executable" {
  [[ -x "$HOOK" ]]
}

@test "M13: hook emits JSON with decision field for wiki path" {
  [[ -x "$HOOK" ]] || skip "hook not found"
  local page="$WORK_DIR/test.md"
  printf -- '---\ntype: note\ntitle: Test\ncreated: 2026-01-01\ntags: []\n---\nBody.\n' > "$page"
  result=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORK_DIR}/wiki/test.md\"}}" | "$HOOK")
  echo "$result" | jq -e '.decision' >/dev/null
}

@test "M13: non-wiki path passes through without validation" {
  [[ -x "$HOOK" ]] || skip "hook not found"
  result=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/some-other-file.md"}}' | "$HOOK")
  [[ "$(echo "$result" | jq -r '.decision')" == "allow" ]]
}

@test "M13: hook passes through when input is not wiki path (no validation needed)" {
  [[ -x "$HOOK" ]] || skip "hook not found"
  result=$(echo '{}' | "$HOOK")
  echo "$result" | jq -e '.decision' >/dev/null
}

@test "M16: block reason with control characters produces valid JSON" {
  [[ -x "$HOOK" ]] || skip "hook not found"
  # Create a mock validator that outputs a reason with control characters (0x01).
  # The old sed 's/["\]/\\&/g' does NOT escape control chars, producing invalid JSON.
  local mock_validator="$WORK_DIR/wiki-validator.sh"
  cat > "$mock_validator" << 'MOCK_SCRIPT'
#!/usr/bin/env bash
# Output reason containing a control character (0x01 = SOH)
printf 'bad field\x01control\n'
exit 1
MOCK_SCRIPT
  chmod +x "$mock_validator"

  # Patch the hook to use our mock validator
  local wrapper="$WORK_DIR/wiki-validator-hook-wrapper.sh"
  sed "s|VALIDATOR=.*|VALIDATOR=\"$mock_validator\"|" "$HOOK" > "$wrapper"
  chmod +x "$wrapper"

  result=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/wiki/test.md"}}' | "$wrapper")
  # Output must be valid JSON — control chars must be stripped or escaped
  if ! echo "$result" | python3 -c "import sys,json; json.loads(sys.stdin.read())" >/dev/null 2>&1; then
    echo "Invalid JSON output: $result" >&3
    false
  fi
  [[ $(echo "$result" | jq -r '.decision') == "block" ]]
}

@test "M13: wiki writes fail closed when validator is missing" {
  [[ -x "$HOOK" ]] || skip "hook not found"
  local wrapper="$WORK_DIR/wiki-validator-hook-wrapper.sh"
  sed 's|VALIDATOR=.*|VALIDATOR="/tmp/missing-wiki-validator"|' "$HOOK" > "$wrapper"
  chmod +x "$wrapper"

  result=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/wiki/test.md"}}' | "$wrapper")
  [[ "$(echo "$result" | jq -r '.decision')" == "block" ]]
  [[ "$(echo "$result" | jq -r '.reason')" =~ "validator not found" ]]
}

@test "M13: install.sh references wiki-validator-hook.sh not bare wiki-validator.sh" {
  INSTALL="$BATS_TEST_DIRNAME/../../install.sh"
  [[ -f "$INSTALL" ]]
  # The install.sh hook command should reference the wrapper, not the bare validator
  grep -q "wiki-validator-hook.sh" "$INSTALL"
}
