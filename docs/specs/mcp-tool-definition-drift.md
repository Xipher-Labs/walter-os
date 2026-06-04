# MCP Tool Definition Drift

## Problem

Walter-OS currently detects drift in the static MCP server registry
(`mcp/servers.json`), but it does not query loaded MCP servers for their
runtime tool definitions. A malicious or compromised MCP can keep the same
package/version in config while changing tool names, descriptions, or schemas.
That is the tool-name shadowing gap tracked by #122 and the unresolved Phase 2
portion of #117.

## Scope

This slice implements Phase 2A for stdio MCP servers loaded by Claude Code:

- Read the runtime config from `~/.claude/settings.json` `.mcpServers`.
- Probe only stdio MCPs (`command` + optional `args` / `env`).
- Use the MCP JSON-RPC lifecycle: `initialize`,
  `notifications/initialized`, then `tools/list`.
- Store an operator-approved baseline at
  `~/.config/walter-os/mcp-tool-snapshots.json`.
- Emit a critical audit finding when a probed server's normalized tool
  definitions differ from the baseline.

## Non-Goals

- HTTP/SSE MCP probing. Remote transports stay covered by server-registry drift
  until a separate transport-specific probe lands.
- Calling MCP tools. This check only lists definitions.
- Changing `AGENTS.md`. That file is protected; this PR updates narrower docs
  and the daily audit skill text only.

## Design

Add a small Node helper,
`skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`, because stdio
MCP probing needs JSON-RPC request/response coordination and process timeouts.
The helper uses only Node built-ins, spawns each configured stdio server without
a shell, sends JSON-RPC messages over stdin, reads newline-delimited responses,
normalizes tool objects with sorted keys, and prints deterministic JSON.
To avoid turning the audit itself into an execution vector, the helper refuses
to spawn a runtime MCP unless its `command`, `args`, and `env` match the
approved `mcp-server-snapshots.json` baseline.

`walter-os baseline-mcp-tools` keeps its existing registry baseline behavior and
also writes the approved tool snapshot when Claude settings are present. The
daily audit keeps the existing registry drift check, then compares the current
tool snapshot with the approved tool baseline.

## Acceptance Criteria

- [ ] AC1: `walter-os baseline-mcp-tools` still writes
  `mcp-server-snapshots.json`.
- [ ] AC2: when `~/.claude/settings.json` contains a working stdio MCP,
  `walter-os baseline-mcp-tools` also writes `mcp-tool-snapshots.json`.
- [ ] AC3: unchanged stdio MCP tool definitions produce no audit finding after
  baseline.
- [ ] AC4: a changed tool description, schema, added tool, or removed tool
  produces a critical `mcp-tool-shadowing` finding.
- [ ] AC5: HTTP/SSE MCP entries are skipped by this Phase 2A probe rather than
  failing the audit.
- [ ] AC6: probe failures are reported without rewriting the approved baseline.
- [ ] AC7: a tampered runtime MCP command is reported but not executed.

## Verification

- `bats tests/audit/mcp-tool-drift.bats`
- `bats tests/audit/mcp-server-drift.bats`
- `bash -n skills/daily-supply-chain-audit/scripts/audit.sh bin/walter-os`
- `node --check skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`
- `shellcheck -e SC2155,SC1091,SC1083,SC2317,SC2329 bin/walter-os skills/daily-supply-chain-audit/scripts/audit.sh`
