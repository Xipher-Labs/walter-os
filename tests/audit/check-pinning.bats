#!/usr/bin/env bats
# Regression tests for skills/daily-supply-chain-audit/scripts/check-pinning.py.
#
# The previous jq-based detector falsely flagged every `npx -y …` server
# because its regex matched the `-y` flag. These tests lock in the correct
# behaviour: flag iff the package-spec arg has no version pin.

setup() {
  CHECK="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/scripts/check-pinning.py"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

write_settings() {
  printf '%s' "$1" > "$TMP/settings.json"
}

run_check() {
  run python3 "$CHECK" "$TMP/settings.json"
}

# ---------- false-positive regression (the bug we're fixing) ----------

@test "npx -y @scope/pkg@x.y.z is recognised as pinned (regression: -y flag matched the old regex)" {
  write_settings '{"mcpServers":{"filesystem":{"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem@2026.1.14"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "npx -y plain-pkg@x.y.z is recognised as pinned" {
  write_settings '{"mcpServers":{"maestro":{"command":"npx","args":["-y","paisanos-maestro-mcp@0.2.1"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "npx -y @scope/pkg@version followed by positional paths is pinned" {
  # filesystem MCP passes extra positional paths after the pkg spec — those
  # are not package specs and must not be checked.
  write_settings '{"mcpServers":{"filesystem":{"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem@2026.1.14","/Users/x/work","/Users/x/personal"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- true positives (real unpinned packages) ----------

@test "npx -y @scope/pkg WITHOUT @version is flagged" {
  write_settings '{"mcpServers":{"slack":{"command":"npx","args":["-y","@modelcontextprotocol/server-slack"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "slack" ]
}

@test "npx -y plain-pkg WITHOUT @version is flagged" {
  write_settings '{"mcpServers":{"sentry":{"command":"npx","args":["-y","some-mcp"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "sentry" ]
}

@test "uvx pkg WITHOUT ==version is flagged" {
  write_settings '{"mcpServers":{"elevenlabs":{"command":"uvx","args":["elevenlabs-mcp"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "elevenlabs" ]
}

# ---------- uvx pin syntaxes ----------

@test "uvx pkg==version is recognised as pinned" {
  write_settings '{"mcpServers":{"elevenlabs":{"command":"uvx","args":["elevenlabs-mcp==0.9.1"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uvx --from pkg==version entry-point is recognised as pinned" {
  write_settings '{"mcpServers":{"elevenlabs":{"command":"uvx","args":["--from","elevenlabs-mcp==0.9.1","elevenlabs-mcp"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uvx --from pkg WITHOUT version is flagged" {
  write_settings '{"mcpServers":{"elevenlabs":{"command":"uvx","args":["--from","elevenlabs-mcp","elevenlabs-mcp"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "elevenlabs" ]
}

# ---------- git commit-hash form ----------

@test "git pkg#<sha> with 7+ hex chars is recognised as pinned" {
  write_settings '{"mcpServers":{"custom":{"command":"npx","args":["-y","github:org/repo#a1b2c3d4"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git pkg#<short> with <7 chars is flagged (not a real sha)" {
  write_settings '{"mcpServers":{"custom":{"command":"npx","args":["-y","github:org/repo#abc"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "custom" ]
}

# ---------- npm dist-tags must be rejected (HIGH-1) ----------

@test "npx -y pkg@latest is flagged (dist-tag, not pinned)" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@latest"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "npx -y @scope/pkg@latest is flagged (scoped dist-tag)" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","@scope/pkg@latest"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "npx -y pkg@next is flagged" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@next"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "npx -y pkg@beta is flagged" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@beta"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

# ---------- npm semver ranges must be rejected (HIGH-1) ----------

@test "npx -y pkg@^1.2.3 is flagged (caret range)" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@^1.2.3"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "npx -y pkg@~1.2.3 is flagged (tilde range)" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@~1.2.3"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "npx -y pkg@>=1.0.0 is flagged (gte range)" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@>=1.0.0"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

# ---------- uvx PEP-440 ranges must be rejected (HIGH-2) ----------

@test "uvx pkg>=1.0 is flagged (PEP-440 gte range)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg>=1.0"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "uvx pkg<=2.0 is flagged (PEP-440 lte range)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg<=2.0"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "uvx pkg~=1.5 is flagged (PEP-440 compatible release)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg~=1.5"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "uvx pkg>1.0 is flagged (PEP-440 gt range)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg>1.0"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "uvx pkg<2.0 is flagged (PEP-440 lt range)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg<2.0"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "uvx pkg!=1.0 is flagged (PEP-440 not-equal)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg!=1.0"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

@test "uvx --from pkg>=1.0 entry-point is flagged (range in --from)" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["--from","pkg>=1.0","entry-point"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ "$output" = "foo" ]
}

# ---------- exact-semver regression (must still be pinned) ----------

@test "npx -y @scope/pkg@2026.1.14 is pinned (exact semver-like)" {
  write_settings '{"mcpServers":{"fs":{"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem@2026.1.14"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "npx -y pkg@1.2.3-rc.1+meta is pinned (semver with prerelease and build metadata)" {
  write_settings '{"mcpServers":{"foo":{"command":"npx","args":["-y","pkg@1.2.3-rc.1+meta"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uvx pkg==0.9.1 is pinned" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["pkg==0.9.1"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uvx --from pkg==0.9.1 entry-point is pinned" {
  write_settings '{"mcpServers":{"foo":{"command":"uvx","args":["--from","pkg==0.9.1","entry-point"]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- non-npx/uvx servers (remote MCPs) ----------

@test "http MCP server is not checked (no command field of interest)" {
  write_settings '{"mcpServers":{"github":{"type":"http","url":"https://api.githubcopilot.com/mcp"}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "sse MCP server is not checked" {
  write_settings '{"mcpServers":{"linear":{"type":"sse","url":"https://mcp.linear.app/sse"}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-npx/uvx command (e.g. local binary) is not flagged" {
  write_settings '{"mcpServers":{"grafana":{"command":"mcp-grafana","args":[]}}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- multiple servers ----------

@test "multiple unpinned servers are listed, one per line" {
  write_settings '{"mcpServers":{"a":{"command":"npx","args":["-y","pkg-a"]},"b":{"command":"npx","args":["-y","pkg-b@1.0.0"]},"c":{"command":"uvx","args":["pkg-c"]}}}'
  run_check
  [ "$status" -eq 0 ]
  # a and c are unpinned, b is pinned. Order follows dict iteration.
  echo "$output" | sort | tr '\n' ',' | grep -q '^a,c,$'
}

# ---------- file / input errors ----------

@test "missing settings file exits 2 with stderr message" {
  run python3 "$CHECK" /nonexistent/path.json
  [ "$status" -eq 2 ]
}

@test "invalid JSON exits 2" {
  printf 'not-json' > "$TMP/settings.json"
  run_check
  [ "$status" -eq 2 ]
}

@test "missing mcpServers key returns no findings" {
  write_settings '{"other":"stuff"}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty mcpServers returns no findings" {
  write_settings '{"mcpServers":{}}'
  run_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
