#!/usr/bin/env bats
# tests/cli/doctor-codex-startup.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WO_BIN="$REPO_ROOT/bin/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_OS_SKIP_UPDATE_CHECK="1"

  FAKE_CACHE="$BATS_TEST_TMPDIR/plugin-cache"
  FAKE_REGISTRY="$BATS_TEST_TMPDIR/servers.json"
  mkdir -p "$FAKE_CACHE/plugin/skills/too-long"
}

write_plugin_warning_fixture() {
  cat > "$FAKE_CACHE/plugin/skills/too-long/SKILL.md" <<'EOF'
---
name: this-skill-name-is-intentionally-longer-than-sixty-four-characters
description: Valid but managed plugin-cache metadata that exceeds Codex limits.
---

# Fixture
EOF
}

write_mcp_warning_fixture() {
  cat > "$FAKE_REGISTRY" <<'JSON'
{
  "servers": {
    "missing_command": {
      "command": "definitely-not-walter-mcp-bin",
      "load": "default"
    },
    "needs_token": {
      "type": "http",
      "url": "https://example.invalid/mcp",
      "headers": {
        "Authorization": "Bearer ${WALTER_TEST_MISSING_TOKEN}"
      },
      "load": "default"
    },
    "manual_skip": {
      "command": "also-missing-but-manual",
      "load": "manual"
    }
  }
}
JSON
}

run_probe() {
  WALTER_CODEX_PLUGIN_CACHE="$FAKE_CACHE" \
    WALTER_MCP_REGISTRY="$FAKE_REGISTRY" \
    bash "$WO_BIN" doctor --codex-startup
}

@test "doctor --codex-startup is wired" {
  grep -q -- "--codex-startup" "$WO_BIN"
  grep -q "_doctor_codex_startup_probe" "$WO_BIN"
}

@test "doctor --codex-startup separates repo, plugin cache, and MCP causes" {
  write_plugin_warning_fixture
  write_mcp_warning_fixture

  run run_probe

  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex startup probe"* ]]
  [[ "$output" == *"repo skills frontmatter"* ]]
  [[ "$output" == *"plugin cache metadata"* ]]
  [[ "$output" == *"do not hand-edit plugin cache"* ]]
  [[ "$output" == *"missing command 'definitely-not-walter-mcp-bin'"* ]]
  [[ "$output" == *"missing env WALTER_TEST_MISSING_TOKEN"* ]]
  [[ "$output" == *"Codex startup summary"* ]]
}
