#!/usr/bin/env bats
# Regression tests for scripts/generate-mcp-configs.sh.
#
# Pre-fix bug: env values were emitted as `KEY = "value"` without escaping
# internal double-quotes. JSON-blob env values (e.g. OPENAPI_MCP_HEADERS)
# produced unparseable TOML and broke codex CLI startup until manually
# patched. The fix routes each env value through jq's `tojson` so internal
# `"` becomes `\"` (valid TOML basic-string escape).

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  SCRIPT="${REPO_ROOT}/scripts/generate-mcp-configs.sh"
  TMP="$(mktemp -d)"
  # Use the live mcp/servers.json — it carries the JSON-blob env value that
  # triggered the bug.
}

teardown() {
  rm -rf "$TMP"
}

@test "generate-mcp-configs.sh codex output parses as valid TOML" {
  # Two-step prerequisite check (matches the repo's convention for
  # environmental skips — see tests/agents/devrel-analyst.bats:44):
  #   1. python3 must be on PATH at all
  #   2. tomllib must be importable (stdlib from Python 3.11+)
  # Distinguishing these gives clearer skip messages — a missing python3
  # is an install gap; a present-but-old python3 is a version gap.
  # Without step 1, the previous `python3 -c "import tomllib"` check
  # would skip with the wrong reason when python3 itself was missing
  # (exit 127 from "command not found" — Copilot R1 of #101).
  command -v python3 >/dev/null 2>&1 || skip "python3 required (not on PATH)"
  if ! python3 -c "import tomllib" 2>/dev/null; then
    skip "tomllib required (Python 3.11+); test scope is TOML validity on Python 3.11+"
  fi

  run bash "$SCRIPT" codex
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$TMP/out.toml"
  run python3 -c "import sys, tomllib; tomllib.loads(open(sys.argv[1]).read())" "$TMP/out.toml"
  [ "$status" -eq 0 ]
}

@test "generate-mcp-configs.sh escapes internal double-quotes in env values (regression for codex-toml bug)" {
  run bash "$SCRIPT" codex
  [ "$status" -eq 0 ]
  # The notion server has OPENAPI_MCP_HEADERS = '{"Authorization":"Bearer ..."}'
  # which must be emitted with `\"` escapes. Pre-fix it would have raw `"`.
  echo "$output" | grep -q 'OPENAPI_MCP_HEADERS = "{\\"Authorization\\":\\"Bearer'
}

@test "generate-mcp-configs.sh emits every mcpServer from mcp/servers.json" {
  run bash "$SCRIPT" codex
  [ "$status" -eq 0 ]
  # Sanity: at least the canonical default-tier servers must appear.
  # If any of these disappear, something upstream regressed.
  for s in filesystem slack plane supabase gmail notion elevenlabs playwright memory; do
    echo "$output" | grep -q "\[mcp_servers.$s\]" || {
      echo "missing: $s" >&2
      return 1
    }
  done
}

@test "generate-mcp-configs.sh claude output is valid JSON" {
  run bash "$SCRIPT" claude
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)"
}

@test "generate-mcp-configs.sh expands HOME templates in filesystem args" {
  run bash "$SCRIPT" claude
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg home "$HOME" '
    .filesystem.args
    | index($home + "/work")
    and index($home + "/Projects-Personal")
    and index($home + "/personal")
    and (index("${HOME}/work") | not)
  '
}

@test "generate-mcp-configs.sh keeps elevenlabs uvx exact pin in claude output" {
  run bash "$SCRIPT" claude
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    .elevenlabs.command == "uvx"
    and .elevenlabs.args[0] == "elevenlabs-mcp==0.9.1"
  '
}
