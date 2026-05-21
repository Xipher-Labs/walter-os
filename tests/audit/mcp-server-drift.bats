#!/usr/bin/env bats
# tests/audit/mcp-server-drift.bats
#
# Covers #117 Phase 1: detect drift in mcp/servers.json (server added,
# removed, command/args changed, trust level changed). Phase 2 (per-tool
# schema query via JSON-RPC) is a follow-up.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/audit.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  [[ -f "$AUDIT" ]] || skip "audit.sh missing"
  [[ -x "$WALTER_OS_BIN" ]] || skip "bin/walter-os missing"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$TMP_HOME/walter-os"
  export CLAUDE_HOME="$TMP_HOME/.claude"
  mkdir -p "$WALTER_CONFIG" "$CLAUDE_HOME" "$WALTER_OS_HOME/mcp"

  # Seed a minimal mcp/servers.json
  cat > "$WALTER_OS_HOME/mcp/servers.json" <<'JSON'
{
  "version": "2.0.0",
  "servers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem@2026.1.14", "/data"],
      "trust": "official-vendor"
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory@2026.2.1"],
      "trust": "official-vendor"
    }
  }
}
JSON

  AUDIT_FINDINGS="$TMP_HOME/findings.jsonl"
  AUDIT_RUNNER="$TMP_HOME/run_check_tool_definitions.sh"
  cat > "$AUDIT_RUNNER" <<RUNNER
#!/usr/bin/env bash
finding() {
  local sev="\$1" id="\$2" desc="\$3" action="\${4:-investigate manually}"
  jq -nc --arg sev "\$sev" --arg id "\$id" --arg desc "\$desc" --arg action "\$action" \\
    '{severity: \$sev, id: \$id, desc: \$desc, action: \$action}' >> "$AUDIT_FINDINGS"
}
source "$AUDIT"
finding() {
  local sev="\$1" id="\$2" desc="\$3" action="\${4:-investigate manually}"
  jq -nc --arg sev "\$sev" --arg id "\$id" --arg desc "\$desc" --arg action "\$action" \\
    '{severity: \$sev, id: \$id, desc: \$desc, action: \$action}' >> "$AUDIT_FINDINGS"
}
check_tool_definitions
RUNNER
  chmod +x "$AUDIT_RUNNER"

  # Establish baseline
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null 2>&1
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# -----------------------------------------------------------------------
# AC1: baseline-mcp-tools writes the snapshot
# -----------------------------------------------------------------------
@test "AC1: baseline-mcp-tools writes mcp-server-snapshots.json" {
  [ -f "$WALTER_CONFIG/mcp-server-snapshots.json" ]
  count=$(jq 'length' "$WALTER_CONFIG/mcp-server-snapshots.json")
  [ "$count" -eq 2 ]
}

# -----------------------------------------------------------------------
# AC2: new server added → HIGH "mcp-server-added"
# -----------------------------------------------------------------------
@test "AC2: server added triggers HIGH" {
  # Modify registry to add a new server
  jq '.servers["malicious-new-mcp"] = {command: "node", args: ["/tmp/attacker.js"], trust: "unknown"}' \
    "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/new.json" && \
    mv "$TMP_HOME/new.json" "$WALTER_OS_HOME/mcp/servers.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-server-added")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC3: server removed → INFO "mcp-server-removed"
# -----------------------------------------------------------------------
@test "AC3: server removed triggers INFO" {
  jq 'del(.servers.memory)' \
    "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/new.json" && \
    mv "$TMP_HOME/new.json" "$WALTER_OS_HOME/mcp/servers.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "info" and .id == "mcp-server-removed")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC4: server command/args changed → HIGH "mcp-server-cmd-changed"
# -----------------------------------------------------------------------
@test "AC4: server command change triggers HIGH" {
  # Bump filesystem version
  jq '.servers.filesystem.args[1] = "@modelcontextprotocol/server-filesystem@9.9.9-evil"' \
    "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/new.json" && \
    mv "$TMP_HOME/new.json" "$WALTER_OS_HOME/mcp/servers.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-server-cmd-changed")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC5: trust level changed → MEDIUM "mcp-server-trust-changed"
# -----------------------------------------------------------------------
@test "AC5: trust level change triggers MEDIUM" {
  jq '.servers.filesystem.trust = "community-fork"' \
    "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/new.json" && \
    mv "$TMP_HOME/new.json" "$WALTER_OS_HOME/mcp/servers.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "medium" and .id == "mcp-server-trust-changed")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC6: no changes → no findings (clean run)
# -----------------------------------------------------------------------
@test "AC6: unchanged registry emits no findings" {
  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  # Either no findings file OR empty
  [ ! -s "$AUDIT_FINDINGS" ]
}
