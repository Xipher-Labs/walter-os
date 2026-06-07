# MCP Tool Definition Drift

## Problem

Walter-OS currently detects drift in the static MCP server registry
(`mcp/servers.json`), but it does not query loaded MCP servers for their
runtime tool definitions. A malicious or compromised MCP can keep the same
package/version in config while changing tool names, descriptions, or schemas.
That is the tool-name shadowing gap tracked by #122 and the unresolved Phase 2
portion of #117.

## Scope

This slice implements Phase 2A for MCP servers loaded by Claude Code:

- Read the runtime config from `~/.claude/settings.json` `.mcpServers`.
- Probe stdio MCPs (`command` + optional `args` / `env`).
- Probe approved HTTP/SSE MCPs (`type`, `url`, optional `headers`) without
  invoking any state-changing tools.
- Use the MCP JSON-RPC lifecycle: `initialize`,
  `notifications/initialized`, then `tools/list`.
- Store an operator-approved baseline at
  `~/.config/walter-os/mcp-tool-snapshots.json`.
- Emit a critical audit finding when a probed server's normalized tool
  definitions differ from the baseline.

## Non-Goals

- Calling MCP tools. This check only lists definitions.
- Changing `AGENTS.md`. That file is protected; this PR updates narrower docs
  and the daily audit skill text only.

## Design

Add a small Node helper,
`skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`, because MCP
probing needs JSON-RPC request/response coordination and timeouts. The helper
uses only Node built-ins. For stdio MCPs, it spawns each configured server
without a shell, sends JSON-RPC messages over stdin, and reads
newline-delimited responses. For Streamable HTTP MCPs, it POSTs JSON-RPC to
the configured URL and accepts either JSON or SSE responses. For legacy SSE
MCPs, it opens the SSE stream, reads the `endpoint` event, POSTs JSON-RPC
messages there, and reads response `message` events. All transports normalize
tool objects with sorted keys and print deterministic JSON.

To avoid turning the audit itself into an execution vector, the helper refuses
to probe a runtime MCP unless the approved `mcp-server-snapshots.json` baseline
marks it enabled in the default profile and its stdio `command`, `args`, and
`env` or remote `type`, `url`, and `headers` match the runtime settings.
Remote header placeholders are materialized only after that registry match and
are not persisted to `mcp-tool-snapshots.json`.

`walter-os baseline-mcp-tools` keeps its existing registry baseline behavior and
also writes the approved tool snapshot when Claude settings are present. The
daily audit keeps the existing registry drift check, then compares the current
tool snapshot with the approved tool baseline.

## Acceptance Criteria

- [ ] AC1: `walter-os baseline-mcp-tools` still writes
  `mcp-server-snapshots.json`.
- [ ] AC2: when `~/.claude/settings.json` contains a working stdio, HTTP, or
  SSE MCP,
  `walter-os baseline-mcp-tools` also writes `mcp-tool-snapshots.json`.
- [ ] AC3: unchanged MCP tool definitions produce no audit finding after
  baseline.
- [ ] AC4: a changed tool description, schema, added tool, or removed tool
  produces a critical `mcp-tool-shadowing` finding.
- [ ] AC5: HTTP/SSE MCP entries are probed only when they match the approved
  default-profile server-registry baseline.
- [ ] AC6: probe failures are reported without rewriting the approved baseline.
- [ ] AC7: a tampered runtime MCP command is reported but not executed.
- [ ] AC8: a tampered runtime remote URL/header is reported but not requested.
- [ ] AC9: a disabled or manual/high-risk MCP is reported but not executed.

## Verification

- `bats tests/audit/mcp-tool-drift.bats`
- `bats tests/audit/mcp-server-drift.bats`
- `bash -n skills/daily-supply-chain-audit/scripts/audit.sh bin/walter-os`
- `node --check skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`
- `shellcheck -e SC2155,SC1091,SC1083,SC2317,SC2329 bin/walter-os skills/daily-supply-chain-audit/scripts/audit.sh`
