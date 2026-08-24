#!/usr/bin/env bats
# Regression tests for setup/codex-config.toml.example.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  TEMPLATE="${REPO_ROOT}/setup/codex-config.toml.example"
}

@test "codex config template avoids deprecated approval policies" {
  grep -q 'approval_policy = "on-request"' "$TEMPLATE"
  ! grep -Eq 'approval_policy = "(untrusted|auto-approve|on-failure)"' "$TEMPLATE"
  ! grep -Eq '"(untrusted|auto-approve|on-failure)"' "$TEMPLATE"
}

@test "codex config template parses as TOML" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required (not on PATH)"
  if ! python3 -c "import tomllib" 2>/dev/null; then
    skip "tomllib required (Python 3.11+)"
  fi

  run python3 -c "import sys, tomllib; tomllib.loads(open(sys.argv[1]).read())" "$TEMPLATE"
  [ "$status" -eq 0 ]
}
