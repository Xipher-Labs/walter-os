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
  # NOTE: python3 prerequisite is checked per-test (only the TOML and
  # JSON parse-validity tests need it). Skipping the whole file would
  # over-skip the grep-based regression tests (escape behavior,
  # mcpServer enumeration, HOME expansion, uvx pin) that don't depend
  # on Python at all.
}

teardown() {
  rm -rf "$TMP"
}

@test "generate-mcp-configs.sh codex output parses as valid TOML" {
  # Two-step prereq (matches the repo's environmental-skip convention,
  # see tests/agents/devrel-analyst.bats:44):
  #   1. python3 must be on PATH at all
  #   2. tomllib must be importable (stdlib from Python 3.11+)
  # Distinguishing these gives clear skip messages — a missing python3
  # is an install gap; a present-but-old python3 is a version gap. The
  # other tests in this file run unconditionally except for test 4
  # (claude JSON validity), which has its own python3 check.
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
  # python3 prereq is only required for the JSON parse step below; if
  # python3 isn't on PATH, skip with a clear message rather than fail
  # with "command not found" inside the pipe.
  command -v python3 >/dev/null 2>&1 || skip "python3 required (not on PATH)"
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
