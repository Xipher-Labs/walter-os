# HTTP/SSE MCP Tool Drift Implementation Plan

**Issue:** #331
**Parent:** #122
**Base PR:** #319 (`codex/issue-122-mcp-tool-drift`)

## Goal

Extend the MCP tool-definition snapshotter from stdio-only probing to approved
HTTP and SSE MCP transports so daily audit detects tool add/remove/schema/
description drift for remote MCPs too.

## Scope

- Reuse `skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`.
- Support generated Claude config shapes with `type: "http"` or
  `type: "sse"` plus `url` and optional `headers`.
- Gate every remote probe against `mcp-server-snapshots.json` before making any
  request.
- Materialize remote header env placeholders only after the gate succeeds.
- Keep the approved tool-baseline schema centered on `.servers.<name>.tools`.

## Non-Goals

- Do not call MCP tools; only `initialize`, `notifications/initialized`, and
  `tools/list`.
- Do not add new npm dependencies.
- Do not change generated MCP config format.

## Tasks

- [x] Add RED tests for HTTP/SSE happy path, remote drift, unreachable remote
  servers, token non-persistence, and header-tamper no-request behavior.
- [x] Add Streamable HTTP JSON-RPC probing with JSON and SSE response parsing.
- [x] Add legacy SSE probing with endpoint discovery and response correlation.
- [x] Preserve the approved server-registry gate across stdio and remote
  transports.
- [x] Update CLI/audit wording and docs so the repo no longer says
  stdio-only.
- [x] Run verification:
  `bats tests/audit/mcp-tool-drift.bats tests/audit/mcp-server-drift.bats`;
  `bash -n skills/daily-supply-chain-audit/scripts/audit.sh bin/walter-os`;
  `node --check skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`;
  `shellcheck`;
  markdown/cross-reference lint; `git diff --check`.
- [ ] Commit, push, open a stacked PR, and request Copilot review.
