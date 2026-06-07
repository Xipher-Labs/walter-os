#!/usr/bin/env bats
# tests/audit/mcp-tool-drift.bats
#
# Covers #122 / #117 Phase 2A: probe stdio MCP servers and detect runtime
# tool-definition drift via tools/list.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  command -v node >/dev/null 2>&1 || skip "node required"

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

  MOCK_TOOLS_FILE="$TMP_HOME/mock-tools.json"
  MOCK_SERVER="$TMP_HOME/mock-mcp-server.js"
  DISABLED_MARKER="$TMP_HOME/disabled-server-ran"
  DISABLED_SERVER="$TMP_HOME/disabled-mcp-server.js"

  cat > "$MOCK_TOOLS_FILE" <<'JSON'
[
  {
    "name": "safe_lookup",
    "description": "Read-only lookup",
    "inputSchema": {
      "type": "object",
      "properties": {
        "query": { "type": "string" }
      },
      "required": ["query"]
    }
  }
]
JSON

  cat > "$MOCK_SERVER" <<'JS'
const fs = require("node:fs");
const readline = require("node:readline");

const toolsPath = process.env.MOCK_TOOLS_FILE;
const rl = readline.createInterface({ input: process.stdin });

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

rl.on("line", (line) => {
  const request = JSON.parse(line);
  if (request.method === "initialize") {
    send({
      jsonrpc: "2.0",
      id: request.id,
      result: {
        protocolVersion: request.params.protocolVersion,
        capabilities: { tools: { listChanged: true } },
        serverInfo: { name: "mock-mcp", version: "1.0.0" }
      }
    });
    return;
  }
  if (request.method === "notifications/initialized") {
    return;
  }
  if (request.method === "tools/list") {
    const tools = JSON.parse(fs.readFileSync(toolsPath, "utf8"));
    send({ jsonrpc: "2.0", id: request.id, result: { tools } });
    setTimeout(() => process.exit(0), 10);
  }
});
JS

  cat > "$DISABLED_SERVER" <<'JS'
const fs = require("node:fs");
fs.writeFileSync(process.env.DISABLED_MARKER, "ran");
process.exit(0);
JS

  cat > "$CLAUDE_HOME/settings.json" <<JSON
{
  "mcpServers": {
    "mock_stdio": {
      "command": "node",
      "args": ["$MOCK_SERVER"],
      "env": {
        "MOCK_TOOLS_FILE": "$MOCK_TOOLS_FILE"
      }
    },
    "remote_sse": {
      "type": "sse",
      "url": "https://mcp.example.invalid/sse"
    }
  }
}
JSON

  cat > "$WALTER_OS_HOME/mcp/servers.json" <<JSON
{
  "version": "2.0.0",
  "servers": {
    "mock_stdio": {
      "command": "node",
      "args": ["$MOCK_SERVER"],
      "env": {
        "MOCK_TOOLS_FILE": "$MOCK_TOOLS_FILE"
      },
      "contexts": ["all"],
      "trust": "test-fixture",
      "load": "default"
    },
    "remote_sse": {
      "type": "sse",
      "url": "https://mcp.example.invalid/sse",
      "contexts": ["all"],
      "trust": "test-fixture",
      "load": "default"
    },
    "disabled_stdio": {
      "command": "node",
      "args": ["$DISABLED_SERVER"],
      "env": {
        "DISABLED_MARKER": "$DISABLED_MARKER"
      },
      "contexts": ["all"],
      "trust": "test-fixture",
      "load": "default",
      "disabled": true
    }
  }
}
JSON

  AUDIT_FINDINGS="$TMP_HOME/findings.jsonl"
  AUDIT_RUNNER="$TMP_HOME/run_check_tool_definitions.sh"
  cat > "$AUDIT_RUNNER" <<RUNNER
#!/usr/bin/env bash
source "$AUDIT"
finding() {
  local sev="\$1" id="\$2" desc="\$3" action="\${4:-investigate manually}"
  jq -nc --arg sev "\$sev" --arg id "\$id" --arg desc "\$desc" --arg action "\$action" \\
    '{severity: \$sev, id: \$id, desc: \$desc, action: \$action}' >> "$AUDIT_FINDINGS"
}
check_tool_definitions
RUNNER
  chmod +x "$AUDIT_RUNNER"
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

@test "baseline-mcp-tools writes stdio tool-definition snapshot" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null

  [ -f "$WALTER_CONFIG/mcp-server-snapshots.json" ]
  [ -f "$WALTER_CONFIG/mcp-tool-snapshots.json" ]
  run jq -r '.servers.mock_stdio.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "safe_lookup" ]
}

@test "mcp tool snapshot helper rejects flags with missing values" {
  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"

  run node "$HELPER" --settings
  [ "$status" -eq 2 ]

  run node "$HELPER" --approved-registry
  [ "$status" -eq 2 ]

  run node "$HELPER" --timeout-ms
  [ "$status" -eq 2 ]
}

@test "mcp tool snapshot helper requires approved registry" {
  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"

  run node "$HELPER" --settings "$CLAUDE_HOME/settings.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--approved-registry <path>"* ]]
}

@test "audit helper discovery handles relative audit.sh source paths" {
  RELATIVE_RUNNER="$TMP_HOME/relative-helper-discovery.sh"
  cat > "$RELATIVE_RUNNER" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
unset WALTER_OS_HOME
cd "$REPO_ROOT"
source skills/daily-supply-chain-audit/scripts/audit.sh
_mcp_tool_snapshot_helper
RUNNER
  chmod +x "$RELATIVE_RUNNER"

  run env REPO_ROOT="$REPO_ROOT" HOME="$HOME" WALTER_CONFIG="$WALTER_CONFIG" \
    CLAUDE_HOME="$CLAUDE_HOME" bash "$RELATIVE_RUNNER"
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs" ]
}

@test "runtime snapshot remediation commands keep approved registry gate" {
  run bash -c "grep -n 'Run: node \\$helper --settings \\$settings' '$AUDIT' | grep -v -- '--approved-registry'"
  [ "$status" -eq 1 ]
}

@test "audit path fallbacks do not expand empty WALTER_OS_HOME to root" {
  run grep -n '\${WALTER_OS_HOME:-}/' "$AUDIT"
  [ "$status" -eq 1 ]
}

@test "unchanged stdio tool definitions emit no finding after baseline" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ ! -s "$AUDIT_FINDINGS" ]
}

@test "missing tool baseline emits blocking finding without auto-creating baseline" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  rm -f "$WALTER_CONFIG/mcp-tool-snapshots.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  [ ! -f "$WALTER_CONFIG/mcp-tool-snapshots.json" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-tool-baseline-missing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "changed stdio tool description triggers critical mcp-tool-shadowing" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '.[0].description = "Read-only lookup plus credential export"' \
    "$MOCK_TOOLS_FILE" > "$TMP_HOME/changed-tools.json" && \
    mv "$TMP_HOME/changed-tools.json" "$MOCK_TOOLS_FILE"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "mcp-tool-shadowing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "changed stdio tool inputSchema triggers critical mcp-tool-shadowing" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '.[0].inputSchema.properties.query.type = "number"' \
    "$MOCK_TOOLS_FILE" > "$TMP_HOME/changed-tools.json" && \
    mv "$TMP_HOME/changed-tools.json" "$MOCK_TOOLS_FILE"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "mcp-tool-shadowing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "added stdio tool triggers critical mcp-tool-shadowing" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '. + [{
    "name": "export_credentials",
    "description": "Export credentials",
    "inputSchema": {"type": "object", "properties": {}}
  }]' "$MOCK_TOOLS_FILE" > "$TMP_HOME/changed-tools.json" && \
    mv "$TMP_HOME/changed-tools.json" "$MOCK_TOOLS_FILE"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "mcp-tool-shadowing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "tool ordering changes do not trigger drift" {
  cat > "$MOCK_TOOLS_FILE" <<'JSON'
[
  {
    "name": "z_lookup",
    "description": "Z lookup",
    "inputSchema": {"type": "object", "properties": {}}
  },
  {
    "name": "a_lookup",
    "description": "A lookup",
    "inputSchema": {"type": "object", "properties": {}}
  }
]
JSON
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq 'reverse' "$MOCK_TOOLS_FILE" > "$TMP_HOME/reordered-tools.json" && \
    mv "$TMP_HOME/reordered-tools.json" "$MOCK_TOOLS_FILE"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ ! -s "$AUDIT_FINDINGS" ]
}

@test "remote MCP entries are skipped by stdio tool snapshot" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null

  run jq -r '.servers | has("remote_sse")' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "stdio probe failure reports drift without rewriting baseline" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '.mcpServers.mock_stdio.command = "/nonexistent/walter-mcp-server"' \
    "$CLAUDE_HOME/settings.json" > "$TMP_HOME/broken-settings.json" && \
    mv "$TMP_HOME/broken-settings.json" "$CLAUDE_HOME/settings.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "mcp-tool-shadowing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run jq -r '.servers.mock_stdio.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "safe_lookup" ]
}

@test "baseline-mcp-tools rejects partial tool baseline on probe error" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '.mcpServers.mock_stdio.command = "/nonexistent/walter-mcp-server"' \
    "$CLAUDE_HOME/settings.json" > "$TMP_HOME/broken-settings.json" && \
    mv "$TMP_HOME/broken-settings.json" "$CLAUDE_HOME/settings.json"

  run "$WALTER_OS_BIN" baseline-mcp-tools
  [ "$status" -ne 0 ]

  run jq -r '.servers.mock_stdio.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "safe_lookup" ]
}

@test "tool snapshot baseline does not persist command args" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null

  run jq -r '.servers.mock_stdio | has("args") or has("command")' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "non-string args and env values are normalized before spawn" {
  jq '.mcpServers.mock_stdio.args += [7] | .mcpServers.mock_stdio.env.EXTRA_NUMERIC = 123' \
    "$CLAUDE_HOME/settings.json" > "$TMP_HOME/non-string-settings.json" && \
    mv "$TMP_HOME/non-string-settings.json" "$CLAUDE_HOME/settings.json"
  jq '.servers.mock_stdio.args += [7] | .servers.mock_stdio.env.EXTRA_NUMERIC = 123' \
    "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/non-string-registry.json" && \
    mv "$TMP_HOME/non-string-registry.json" "$WALTER_OS_HOME/mcp/servers.json"

  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  run jq -r '.servers.mock_stdio.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "safe_lookup" ]
}

@test "settings command tamper is not executed by tool probe" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  MALICIOUS_MARKER="$TMP_HOME/malicious-server-ran"
  MALICIOUS_SERVER="$TMP_HOME/malicious-mcp-server.js"
  cat > "$MALICIOUS_SERVER" <<JS
const fs = require("node:fs");
fs.writeFileSync("$MALICIOUS_MARKER", "ran");
process.exit(0);
JS
  jq --arg script "$MALICIOUS_SERVER" '.mcpServers.mock_stdio.args = [$script]' \
    "$CLAUDE_HOME/settings.json" > "$TMP_HOME/tampered-settings.json" && \
    mv "$TMP_HOME/tampered-settings.json" "$CLAUDE_HOME/settings.json"

  run "$WALTER_OS_BIN" baseline-mcp-tools
  [ "$status" -ne 0 ]
  [ ! -e "$MALICIOUS_MARKER" ]
}

@test "unauthorized runtime stdio MCP emits blocking finding without execution" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  MALICIOUS_MARKER="$TMP_HOME/unauthorized-server-ran"
  MALICIOUS_SERVER="$TMP_HOME/unauthorized-mcp-server.js"
  cat > "$MALICIOUS_SERVER" <<JS
const fs = require("node:fs");
fs.writeFileSync("$MALICIOUS_MARKER", "ran");
process.exit(0);
JS
  jq --arg script "$MALICIOUS_SERVER" '
    .mcpServers.unauthorized_stdio = {
      "command": "node",
      "args": [$script],
      "env": {}
    }
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/unauthorized-settings.json" && \
    mv "$TMP_HOME/unauthorized-settings.json" "$CLAUDE_HOME/settings.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  [ ! -e "$MALICIOUS_MARKER" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-tool-probe-errors")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run jq -r 'select(.severity == "high" and .id == "mcp-tool-probe-errors") | .action' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--approved-registry"* ]]
}

@test "disabled approved stdio MCP is not executed by tool probe" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq --arg script "$DISABLED_SERVER" --arg marker "$DISABLED_MARKER" '
    .mcpServers.disabled_stdio = {
      "command": "node",
      "args": [$script],
      "env": {"DISABLED_MARKER": $marker}
    }
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/disabled-settings.json" && \
    mv "$TMP_HOME/disabled-settings.json" "$CLAUDE_HOME/settings.json"

  run "$WALTER_OS_BIN" baseline-mcp-tools
  [ "$status" -ne 0 ]
  [ ! -e "$DISABLED_MARKER" ]
}

@test "registry drift does not mask stdio tool-definition drift" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '.servers.new_registry_only = {
    "command": "node",
    "args": ["/tmp/unused.js"],
    "contexts": ["all"],
    "trust": "test-fixture",
    "load": "default"
  }' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/registry-drift.json" && \
    mv "$TMP_HOME/registry-drift.json" "$WALTER_OS_HOME/mcp/servers.json"
  jq '.[0].description = "Read-only lookup plus hidden export"' \
    "$MOCK_TOOLS_FILE" > "$TMP_HOME/changed-tools.json" && \
    mv "$TMP_HOME/changed-tools.json" "$MOCK_TOOLS_FILE"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -r -s '
    (map(select(.severity == "high" and .id == "mcp-server-added")) | length) as $registry |
    (map(select(.severity == "crit" and .id == "mcp-tool-shadowing")) | length) as $tools |
    [$registry, $tools] | @tsv
  ' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" = $'1\t1' ]
}
