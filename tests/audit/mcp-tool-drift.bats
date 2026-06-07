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
  REMOTE_TOOLS_FILE="$TMP_HOME/remote-tools.json"
  REMOTE_SERVER="$TMP_HOME/mock-remote-mcp-server.js"
  REMOTE_PORT_FILE="$TMP_HOME/remote-port"
  REMOTE_REQUESTS_FILE="$TMP_HOME/remote-requests.jsonl"
  export TEST_REMOTE_TOKEN="remote-secret-token"

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

  cat > "$REMOTE_TOOLS_FILE" <<'JSON'
[
  {
    "name": "remote_lookup",
    "description": "Remote read-only lookup",
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

  cat > "$REMOTE_SERVER" <<'JS'
const fs = require("node:fs");
const http = require("node:http");

const toolsPath = process.argv[2];
const portPath = process.argv[3];
const requestsPath = process.argv[4];
const sseClients = new Map();

function readTools() {
  return JSON.parse(fs.readFileSync(toolsPath, "utf8"));
}

function rpcResult(request) {
  if (request.method === "initialize") {
    return {
      protocolVersion: request.params?.protocolVersion,
      capabilities: { tools: { listChanged: true } },
      serverInfo: { name: "mock-remote-mcp", version: "1.0.0" }
    };
  }
  if (request.method === "tools/list") {
    return { tools: readTools() };
  }
  return {};
}

function readBody(req, callback) {
  let body = "";
  req.setEncoding("utf8");
  req.on("data", (chunk) => {
    body += chunk;
  });
  req.on("end", () => callback(body));
}

function sendSse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

const server = http.createServer((req, res) => {
  fs.appendFileSync(requestsPath, JSON.stringify({
    method: req.method,
    url: req.url,
    authorization: req.headers.authorization || ""
  }) + "\n");

  if (req.method === "POST" && req.url === "/mcp-http") {
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (!Object.prototype.hasOwnProperty.call(request, "id")) {
        res.writeHead(202).end();
        return;
      }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: rpcResult(request) }));
    });
    return;
  }

  if (req.method === "POST" && req.url === "/mcp-http-redirect") {
    readBody(req, () => {
      res.writeHead(302, { location: "/mcp-http" });
      res.end();
    });
    return;
  }

  if (req.method === "POST" && req.url === "/mcp-http-mismatched-id") {
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (!Object.prototype.hasOwnProperty.call(request, "id")) {
        res.writeHead(202).end();
        return;
      }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", id: request.id + 1000, result: rpcResult(request) }));
    });
    return;
  }

  if (req.method === "POST" && req.url === "/mcp-http-slow-body") {
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (!Object.prototype.hasOwnProperty.call(request, "id")) {
        res.writeHead(202).end();
        return;
      }
      res.writeHead(200, { "content-type": "application/json" });
      res.write(`{"jsonrpc":"2.0","id":${JSON.stringify(request.id)},`);
      setTimeout(() => {
        res.end(`"result":${JSON.stringify(rpcResult(request))}}`);
      }, 400);
    });
    return;
  }

  if (req.method === "POST" && req.url === "/mcp-http-sse-final") {
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (!Object.prototype.hasOwnProperty.call(request, "id")) {
        res.writeHead(202).end();
        return;
      }
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.end(`event: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: request.id, result: rpcResult(request) })}`);
    });
    return;
  }

  if (req.method === "POST" && req.url === "/mcp-http-sse-open") {
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (!Object.prototype.hasOwnProperty.call(request, "id")) {
        res.writeHead(202).end();
        return;
      }
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive"
      });
      sendSse(res, "message", { jsonrpc: "2.0", id: request.id, result: rpcResult(request) });
    });
    return;
  }

  if (req.method === "POST" && req.url === "/mcp-http-bad-notification") {
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (!Object.prototype.hasOwnProperty.call(request, "id")) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "notification failed" }));
        return;
      }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: rpcResult(request) }));
    });
    return;
  }

  if (req.method === "GET" && req.url === "/sse") {
    const sessionId = String(Math.random()).slice(2);
    res.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive"
    });
    sseClients.set(sessionId, res);
    res.write(`event: endpoint\n`);
    res.write(`data: /sse-message?session=${sessionId}\n\n`);
    req.on("close", () => {
      sseClients.delete(sessionId);
    });
    return;
  }

  if (req.method === "GET" && req.url === "/sse-cross-origin") {
    res.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive"
    });
    res.write(`event: endpoint\n`);
    res.write(`data: http://127.0.0.2:65535/sse-message\n\n`);
    return;
  }

  if (req.method === "POST" && req.url?.startsWith("/sse-message?session=")) {
    const sessionId = new URL(req.url, "http://127.0.0.1").searchParams.get("session");
    const client = sseClients.get(sessionId);
    readBody(req, (body) => {
      const request = JSON.parse(body);
      if (Object.prototype.hasOwnProperty.call(request, "id") && client) {
        sendSse(client, "message", { jsonrpc: "2.0", id: request.id, result: rpcResult(request) });
      }
      res.writeHead(202).end();
    });
    return;
  }

  res.writeHead(404).end();
});

server.listen(0, "127.0.0.1", () => {
  fs.writeFileSync(portPath, String(server.address().port));
});
JS

  node "$REMOTE_SERVER" "$REMOTE_TOOLS_FILE" "$REMOTE_PORT_FILE" "$REMOTE_REQUESTS_FILE" &
  REMOTE_PID="$!"
  for _ in {1..100}; do
    [[ -s "$REMOTE_PORT_FILE" ]] && break
    sleep 0.05
  done
  [[ -s "$REMOTE_PORT_FILE" ]] || {
    echo "mock remote MCP server did not start" >&2
    return 1
  }
  REMOTE_BASE_URL="http://127.0.0.1:$(cat "$REMOTE_PORT_FILE")"

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
    "remote_http": {
      "type": "http",
      "url": "$REMOTE_BASE_URL/mcp-http",
      "headers": {
        "Authorization": "Bearer \${TEST_REMOTE_TOKEN}"
      }
    },
    "remote_sse": {
      "type": "sse",
      "url": "$REMOTE_BASE_URL/sse"
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
    "remote_http": {
      "type": "http",
      "url": "$REMOTE_BASE_URL/mcp-http",
      "headers": {
        "Authorization": "Bearer \${TEST_REMOTE_TOKEN}"
      },
      "contexts": ["all"],
      "trust": "test-fixture",
      "load": "default"
    },
    "remote_sse": {
      "type": "sse",
      "url": "$REMOTE_BASE_URL/sse",
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
  if [[ -n "${REMOTE_PID:-}" ]]; then
    kill "$REMOTE_PID" >/dev/null 2>&1 || true
    wait "$REMOTE_PID" >/dev/null 2>&1 || true
  fi
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

@test "HTTP/SSE MCP probe requires Node.js 18+ before runtime probing" {
  local old_node_bin="$TMP_HOME/old-node-bin"
  mkdir -p "$old_node_bin"
  cat > "$old_node_bin/node" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-p" ]]; then
  printf '16\n'
  exit 0
fi
echo "old node cannot run MCP probes" >&2
exit 1
SH
  chmod +x "$old_node_bin/node"

  rm -f "$AUDIT_FINDINGS"
  PATH="$old_node_bin:$PATH" bash "$AUDIT_RUNNER"

  run jq -r 'select(.severity == "high" and .id == "node-too-old-mcp-tool-drift") | .desc + " | " + .action' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Node.js 18+ required"* ]]
  [[ "$output" == *"Node.js 18+ host"* ]]
}

@test "HTTP/SSE MCP probe parses event-stream responses through streaming path only" {
  local helper="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"

  run grep -n 'function parseSseText' "$helper"
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

@test "remote MCP entries are probed by tool snapshot" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null

  run jq -r '.servers.remote_http.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "remote_lookup" ]

  run jq -r '.servers.remote_sse.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "remote_lookup" ]
}

@test "remote MCP header tokens are sent but not persisted" {
  run "$WALTER_OS_BIN" baseline-mcp-tools
  [ "$status" -eq 0 ]
  [[ "$output" != *"$TEST_REMOTE_TOKEN"* ]]

  run grep -q "$TEST_REMOTE_TOKEN" "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -ne 0 ]

  run jq -r 'select(.url == "/mcp-http") | .authorization' "$REMOTE_REQUESTS_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bearer $TEST_REMOTE_TOKEN"* ]]
}

@test "remote MCP header tamper is not requested" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  : > "$REMOTE_REQUESTS_FILE"
  jq '.mcpServers.remote_http.headers.Authorization = "Bearer tampered-token"' \
    "$CLAUDE_HOME/settings.json" > "$TMP_HOME/tampered-remote-settings.json" && \
    mv "$TMP_HOME/tampered-remote-settings.json" "$CLAUDE_HOME/settings.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-tool-probe-errors")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run jq -s 'map(select(.url == "/mcp-http")) | length' "$REMOTE_REQUESTS_FILE"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
  run grep -q "tampered-token" "$AUDIT_FINDINGS"
  [ "$status" -ne 0 ]
}

@test "HTTP MCP probe refuses redirects without following with auth" {
  jq --arg url "$REMOTE_BASE_URL/mcp-http-redirect" '
    .mcpServers.remote_http.url = $url
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/http-redirect-settings.json" && \
    mv "$TMP_HOME/http-redirect-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/mcp-http-redirect" '
    .servers.remote_http.url = $url
  ' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/http-redirect-registry.json" && \
    mv "$TMP_HOME/http-redirect-registry.json" "$WALTER_OS_HOME/mcp/servers.json"
  jq --sort-keys '.servers // {}' "$WALTER_OS_HOME/mcp/servers.json" \
    > "$WALTER_CONFIG/mcp-server-snapshots.json"
  : > "$REMOTE_REQUESTS_FILE"

  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
  run node "$HELPER" --settings "$CLAUDE_HOME/settings.json" \
    --approved-registry "$WALTER_CONFIG/mcp-server-snapshots.json"

  [ "$status" -eq 0 ]
  run jq -r '.errors.remote_http.message // ""' <<< "$output"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run jq -s 'map(select(.url == "/mcp-http")) | length' "$REMOTE_REQUESTS_FILE"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "HTTP MCP probe rejects mismatched JSON-RPC response ids" {
  jq --arg url "$REMOTE_BASE_URL/mcp-http-mismatched-id" '
    .mcpServers.remote_http.url = $url
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/http-mismatch-settings.json" && \
    mv "$TMP_HOME/http-mismatch-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/mcp-http-mismatched-id" '
    .servers.remote_http.url = $url
  ' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/http-mismatch-registry.json" && \
    mv "$TMP_HOME/http-mismatch-registry.json" "$WALTER_OS_HOME/mcp/servers.json"
  jq --sort-keys '.servers // {}' "$WALTER_OS_HOME/mcp/servers.json" \
    > "$WALTER_CONFIG/mcp-server-snapshots.json"

  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
  run node "$HELPER" --settings "$CLAUDE_HOME/settings.json" \
    --approved-registry "$WALTER_CONFIG/mcp-server-snapshots.json"

  [ "$status" -eq 0 ]
  run jq -r '.errors.remote_http.message // ""' <<< "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"response id mismatch"* ]]
}

@test "HTTP MCP probe times out while reading slow response bodies" {
  jq --arg url "$REMOTE_BASE_URL/mcp-http-slow-body" '
    .mcpServers.remote_http.url = $url
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/http-slow-body-settings.json" && \
    mv "$TMP_HOME/http-slow-body-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/mcp-http-slow-body" '
    .servers.remote_http.url = $url
  ' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/http-slow-body-registry.json" && \
    mv "$TMP_HOME/http-slow-body-registry.json" "$WALTER_OS_HOME/mcp/servers.json"
  jq --sort-keys '.servers // {}' "$WALTER_OS_HOME/mcp/servers.json" \
    > "$WALTER_CONFIG/mcp-server-snapshots.json"

  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
  run node "$HELPER" --settings "$CLAUDE_HOME/settings.json" \
    --approved-registry "$WALTER_CONFIG/mcp-server-snapshots.json" \
    --timeout-ms 100

  [ "$status" -eq 0 ]
  run jq -r '.errors.remote_http.message // ""' <<< "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"response body: timeout after 100ms"* ]]
}

@test "SSE MCP probe rejects cross-origin message endpoints" {
  jq --arg url "$REMOTE_BASE_URL/sse-cross-origin" '
    del(.mcpServers.remote_http) |
    .mcpServers.remote_sse.url = $url |
    .mcpServers.remote_sse.headers.Authorization = "Bearer ${TEST_REMOTE_TOKEN}"
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/sse-cross-origin-settings.json" && \
    mv "$TMP_HOME/sse-cross-origin-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/sse-cross-origin" '
    del(.servers.remote_http) |
    .servers.remote_sse.url = $url |
    .servers.remote_sse.headers.Authorization = "Bearer ${TEST_REMOTE_TOKEN}"
  ' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/sse-cross-origin-registry.json" && \
    mv "$TMP_HOME/sse-cross-origin-registry.json" "$WALTER_OS_HOME/mcp/servers.json"
  jq --sort-keys '.servers // {}' "$WALTER_OS_HOME/mcp/servers.json" \
    > "$WALTER_CONFIG/mcp-server-snapshots.json"
  : > "$REMOTE_REQUESTS_FILE"

  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
  run node "$HELPER" --settings "$CLAUDE_HOME/settings.json" \
    --approved-registry "$WALTER_CONFIG/mcp-server-snapshots.json"

  [ "$status" -eq 0 ]
  run jq -r '.errors.remote_sse.message // ""' <<< "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SSE endpoint origin mismatch"* ]]
  run jq -s 'map(select(.method == "POST")) | length' "$REMOTE_REQUESTS_FILE"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "HTTP MCP accepts final SSE event without trailing blank line" {
  jq --arg url "$REMOTE_BASE_URL/mcp-http-sse-final" '
    .mcpServers.remote_http_sse_final = {
      "type": "http",
      "url": $url
    }
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/http-sse-final-settings.json" && \
    mv "$TMP_HOME/http-sse-final-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/mcp-http-sse-final" '
    .servers.remote_http_sse_final = {
      "type": "http",
      "url": $url,
      "contexts": ["all"],
      "trust": "test-fixture",
      "load": "default"
    }
  ' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/http-sse-final-registry.json" && \
    mv "$TMP_HOME/http-sse-final-registry.json" "$WALTER_OS_HOME/mcp/servers.json"

  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  run jq -r '.servers.remote_http_sse_final.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "remote_lookup" ]
}

@test "HTTP MCP reads first SSE message without waiting for stream close" {
  jq --arg url "$REMOTE_BASE_URL/mcp-http-sse-open" '
    .mcpServers.remote_http.url = $url
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/http-sse-open-settings.json" && \
    mv "$TMP_HOME/http-sse-open-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/mcp-http-sse-open" '
    .servers.remote_http.url = $url
  ' "$WALTER_OS_HOME/mcp/servers.json" > "$TMP_HOME/http-sse-open-registry.json" && \
    mv "$TMP_HOME/http-sse-open-registry.json" "$WALTER_OS_HOME/mcp/servers.json"
  jq --sort-keys '.servers // {}' "$WALTER_OS_HOME/mcp/servers.json" \
    > "$WALTER_CONFIG/mcp-server-snapshots.json"

  HELPER="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
  run node "$HELPER" --settings "$CLAUDE_HOME/settings.json" \
    --approved-registry "$WALTER_CONFIG/mcp-server-snapshots.json" \
    --timeout-ms 100

  [ "$status" -eq 0 ]
  run jq -r '.servers.remote_http.tools[0].name' <<< "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "remote_lookup" ]
  run jq -e '.errors.remote_http' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "HTTP MCP notification failures produce probe errors" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq --arg url "$REMOTE_BASE_URL/mcp-http-bad-notification" '
    .mcpServers.remote_http.url = $url
  ' "$CLAUDE_HOME/settings.json" > "$TMP_HOME/http-bad-notification-settings.json" && \
    mv "$TMP_HOME/http-bad-notification-settings.json" "$CLAUDE_HOME/settings.json"
  jq --arg url "$REMOTE_BASE_URL/mcp-http-bad-notification" '
    .remote_http.url = $url
  ' "$WALTER_CONFIG/mcp-server-snapshots.json" > "$TMP_HOME/http-bad-notification-baseline.json" && \
    mv "$TMP_HOME/http-bad-notification-baseline.json" "$WALTER_CONFIG/mcp-server-snapshots.json"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-tool-probe-errors")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "changed remote MCP tool description triggers critical mcp-tool-shadowing" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  jq '.[0].description = "Remote lookup plus hidden export"' \
    "$REMOTE_TOOLS_FILE" > "$TMP_HOME/changed-remote-tools.json" && \
    mv "$TMP_HOME/changed-remote-tools.json" "$REMOTE_TOOLS_FILE"

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "mcp-tool-shadowing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "unreachable baselined remote MCP emits probe error without rewriting baseline" {
  "$WALTER_OS_BIN" baseline-mcp-tools >/dev/null
  kill "$REMOTE_PID" >/dev/null 2>&1 || true
  wait "$REMOTE_PID" >/dev/null 2>&1 || true
  REMOTE_PID=""

  rm -f "$AUDIT_FINDINGS"
  bash "$AUDIT_RUNNER"
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "mcp-tool-probe-errors")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run jq -r '.servers.remote_http.tools[0].name' "$WALTER_CONFIG/mcp-tool-snapshots.json"
  [ "$status" -eq 0 ]
  [ "$output" = "remote_lookup" ]
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
