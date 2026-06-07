# MCP Tool Definition Drift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime MCP tool-definition drift detection for stdio MCP servers.

**Architecture:** A Node helper probes stdio MCPs from Claude settings with JSON-RPC and returns deterministic snapshots. The Walter-OS CLI writes an approved baseline, while the daily audit compares current tool definitions against that baseline and reports critical drift.

**Tech Stack:** Bash, Bats, jq, Node.js built-ins, MCP JSON-RPC stdio.

---

### Task 1: RED Test For Tool Snapshot Baselines

**Files:**
- Create: `tests/audit/mcp-tool-drift.bats`
- Modify: none

- [ ] **Step 1: Write the failing test**

Create a Bats test that builds a temporary Claude settings file with one mock
stdio MCP server, runs `walter-os baseline-mcp-tools`, and asserts both the
existing server-registry baseline and the new tool-definition baseline exist.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bats tests/audit/mcp-tool-drift.bats
```

Expected: fail because `mcp-tool-snapshots.json` is not written yet.

### Task 2: GREEN Helper For MCP `tools/list`

**Files:**
- Create: `skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs`
- Modify: `bin/walter-os`
- Test: `tests/audit/mcp-tool-drift.bats`

- [ ] **Step 1: Implement the stdio probe helper**

The helper should read `.mcpServers` from a settings path, skip non-stdio
servers, spawn each stdio command without a shell, send `initialize`,
`notifications/initialized`, and `tools/list`, then print sorted JSON.

- [ ] **Step 2: Wire `walter-os baseline-mcp-tools`**

Keep the existing `mcp-server-snapshots.json` output and add
`mcp-tool-snapshots.json` when the helper and Claude settings exist.

- [ ] **Step 3: Run test to verify it passes**

Run:

```bash
bats tests/audit/mcp-tool-drift.bats
```

Expected: baseline test passes.

### Task 3: RED/GREEN Audit Drift Finding

**Files:**
- Modify: `skills/daily-supply-chain-audit/scripts/audit.sh`
- Modify: `tests/audit/mcp-tool-drift.bats`

- [ ] **Step 1: Add failing drift test**

After baseline, mutate the mock MCP tool description and run
`check_tool_definitions`; assert a critical `mcp-tool-shadowing` finding.

- [ ] **Step 2: Implement audit comparison**

Add a second phase after the registry comparison that snapshots current stdio
tools and compares them against `mcp-tool-snapshots.json`.

- [ ] **Step 3: Run focused tests**

Run:

```bash
bats tests/audit/mcp-tool-drift.bats tests/audit/mcp-server-drift.bats
```

Expected: both suites pass.

### Task 4: Docs And Verification

**Files:**
- Modify: `skills/daily-supply-chain-audit/SKILL.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update docs**

Document that server-registry drift and stdio tool-definition drift are now
separate checks, and that HTTP/SSE tool probes remain out of scope.

- [ ] **Step 2: Run static checks**

Run:

```bash
bash -n skills/daily-supply-chain-audit/scripts/audit.sh bin/walter-os
node --check skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs
shellcheck -e SC2155,SC1091,SC1083,SC2317,SC2329 bin/walter-os skills/daily-supply-chain-audit/scripts/audit.sh
git diff --check
```

Expected: all checks pass.
