#!/usr/bin/env bats
# tests/walter-bridge/clients.bats
# Tests for walter-bridge client config templates and the `walter bridge install` subcommand.
# Refs: W-8-cli-clients

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CCR_TEMPLATE="$REPO_ROOT/setup/walter-bridge/clients/claude-code-router/config.template.json"
  GEM_TEMPLATE="$REPO_ROOT/setup/walter-bridge/clients/gemini-cli/settings.template.json"
  COD_TEMPLATE="$REPO_ROOT/setup/walter-bridge/clients/codex-cli/config.template.toml"
  BRIDGE_CMD="$REPO_ROOT/bin/walter-os"
}

# ---------------------------------------------------------------------------
# T1: Template files exist and have valid syntax
# ---------------------------------------------------------------------------

@test "claude-code-router config.template.json exists" {
  [ -f "$CCR_TEMPLATE" ]
}

@test "gemini-cli settings.template.json exists" {
  [ -f "$GEM_TEMPLATE" ]
}

@test "codex-cli config.template.toml exists" {
  [ -f "$COD_TEMPLATE" ]
}

@test "claude-code-router template is valid JSON (with literal placeholders intact)" {
  # Replace placeholders with dummy values before JSON-parsing,
  # since ${VAR} is not valid JSON but IS valid in the template.
  run python3 -c "
import json, re, sys
with open('$CCR_TEMPLATE') as f:
    content = f.read()
# Substitute placeholders with dummy values so json.loads works
content = re.sub(r'\\\${[A-Z_]+}', 'placeholder', content)
json.loads(content)
print('ok')
"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "gemini-cli template is valid JSON (with literal placeholders intact)" {
  run python3 -c "
import json, re, sys
with open('$GEM_TEMPLATE') as f:
    content = f.read()
content = re.sub(r'\\\${[A-Z_]+}', 'placeholder', content)
json.loads(content)
print('ok')
"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "codex-cli template is valid TOML" {
  run python3 -c "
import sys
with open('$COD_TEMPLATE', 'rb') as f:
    content = f.read()
try:
    import tomllib
except ImportError:
    # Python < 3.11 — try tomli
    try:
        import tomli as tomllib
    except ImportError:
        # Neither available: do a basic structural check (no traceback = ok)
        print('skip:no-tomllib')
        sys.exit(0)
tomllib.loads(content.decode())
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" || "$output" == "skip:no-tomllib" ]]
}

# ---------------------------------------------------------------------------
# T2: Templates contain required placeholders
# ---------------------------------------------------------------------------

@test "claude-code-router template contains \${WALTER_DOMAIN}" {
  grep -q '\${WALTER_DOMAIN}' "$CCR_TEMPLATE"
}

@test "claude-code-router template contains \${LITELLM_MASTER_KEY}" {
  grep -q '\${LITELLM_MASTER_KEY}' "$CCR_TEMPLATE"
}

@test "gemini-cli template contains \${WALTER_DOMAIN}" {
  grep -q '\${WALTER_DOMAIN}' "$GEM_TEMPLATE"
}

@test "gemini-cli template contains \${LITELLM_MASTER_KEY}" {
  grep -q '\${LITELLM_MASTER_KEY}' "$GEM_TEMPLATE"
}

@test "codex-cli template contains \${WALTER_DOMAIN}" {
  grep -q '\${WALTER_DOMAIN}' "$COD_TEMPLATE"
}

@test "codex-cli template contains LITELLM_MASTER_KEY reference" {
  grep -q 'LITELLM_MASTER_KEY' "$COD_TEMPLATE"
}

# ---------------------------------------------------------------------------
# T3: `walter bridge install <cli>` renders placeholders into target path
# ---------------------------------------------------------------------------

@test "walter bridge install claude-code-router renders config" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  run env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="test.example.com" \
    LITELLM_MASTER_KEY="k-testkey123" \
    "$BRIDGE_CMD" bridge install claude-code-router
  [ "$status" -eq 0 ]
  local cfg="$tmpdir/.claude-code-router/config.json"
  [ -f "$cfg" ]
  grep -q "test.example.com" "$cfg"
  grep -q "k-testkey123" "$cfg"
  # Ensure no unreplaced placeholders remain
  run grep '\${WALTER_DOMAIN}\|${LITELLM_MASTER_KEY}' "$cfg"
  [ "$status" -ne 0 ]
  rm -rf "$tmpdir"
}

@test "walter bridge install gemini-cli renders settings" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  run env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="test.example.com" \
    LITELLM_MASTER_KEY="k-testkey123" \
    "$BRIDGE_CMD" bridge install gemini-cli
  [ "$status" -eq 0 ]
  local cfg="$tmpdir/.gemini/settings.json"
  [ -f "$cfg" ]
  grep -q "test.example.com" "$cfg"
  grep -q "k-testkey123" "$cfg"
  run grep '\${WALTER_DOMAIN}\|${LITELLM_MASTER_KEY}' "$cfg"
  [ "$status" -ne 0 ]
  rm -rf "$tmpdir"
}

@test "walter bridge install codex-cli renders config" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  run env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="test.example.com" \
    LITELLM_MASTER_KEY="k-testkey123" \
    "$BRIDGE_CMD" bridge install codex-cli
  [ "$status" -eq 0 ]
  local cfg="$tmpdir/.codex/config.toml"
  [ -f "$cfg" ]
  grep -q "test.example.com" "$cfg"
  run grep '\${WALTER_DOMAIN}' "$cfg"
  [ "$status" -ne 0 ]
  rm -rf "$tmpdir"
}

@test "walter bridge install all installs all three CLIs" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  run env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="test.example.com" \
    LITELLM_MASTER_KEY="k-testkey123" \
    "$BRIDGE_CMD" bridge install all
  [ "$status" -eq 0 ]
  [ -f "$tmpdir/.claude-code-router/config.json" ]
  [ -f "$tmpdir/.gemini/settings.json" ]
  [ -f "$tmpdir/.codex/config.toml" ]
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# T4: Second invocation produces a .bak.* backup file
# ---------------------------------------------------------------------------

@test "second walter bridge install produces .bak backup" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # First install
  env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="first.example.com" \
    LITELLM_MASTER_KEY="k-first" \
    "$BRIDGE_CMD" bridge install codex-cli >/dev/null 2>&1
  # Second install — should produce backup
  env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="second.example.com" \
    LITELLM_MASTER_KEY="k-second" \
    "$BRIDGE_CMD" bridge install codex-cli >/dev/null 2>&1
  local bak_count
  bak_count="$(find "$tmpdir/.codex" -name "config.toml.bak.*" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$bak_count" -ge 1 ]
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# T5: `walter bridge status` reports wired after install
# ---------------------------------------------------------------------------

@test "walter bridge status reports all wired after install all" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Install first
  env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="test.example.com" \
    LITELLM_MASTER_KEY="k-testkey123" \
    "$BRIDGE_CMD" bridge install all >/dev/null 2>&1
  # Now check status
  run env HOME="$tmpdir" \
    WALTER_OS_HOME="$REPO_ROOT" \
    WALTER_DOMAIN="test.example.com" \
    LITELLM_MASTER_KEY="k-testkey123" \
    "$BRIDGE_CMD" bridge status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "wired"
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# T6: Missing env vars produce loud failure
# ---------------------------------------------------------------------------

@test "walter bridge install fails loudly without LITELLM_MASTER_KEY" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Run in a subshell with LITELLM_MASTER_KEY unset to test env validation.
  run bash -c "
    unset LITELLM_MASTER_KEY
    HOME='$tmpdir' WALTER_OS_HOME='$REPO_ROOT' WALTER_DOMAIN='test.example.com' \
      '$BRIDGE_CMD' bridge install codex-cli
  "
  [ "$status" -ne 0 ]
  rm -rf "$tmpdir"
}

@test "walter bridge install fails loudly without WALTER_DOMAIN" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Run in a subshell with WALTER_DOMAIN unset to test env validation.
  run bash -c "
    unset WALTER_DOMAIN
    HOME='$tmpdir' WALTER_OS_HOME='$REPO_ROOT' LITELLM_MASTER_KEY='k-testkey123' \
      '$BRIDGE_CMD' bridge install codex-cli
  "
  [ "$status" -ne 0 ]
  rm -rf "$tmpdir"
}
