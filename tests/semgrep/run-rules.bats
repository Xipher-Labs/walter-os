#!/usr/bin/env bats
# Validates Walter-OS custom semgrep rules against fixture files.
# Skips gracefully when `semgrep` is not installed locally.
#
# Refs: docs/specs/oss-hardening-stretch.md (TBD)

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
RULES_DIR="$REPO_ROOT/.semgrep/rules"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

setup() {
  if ! command -v semgrep >/dev/null 2>&1; then
    skip "semgrep not installed locally (CI runs the workflow instead)"
  fi
}

# --- Positive fixtures: each rule MUST fire on its fixture. -------------------

@test "python eval-injection rule fires on triple-quote interpolation" {
  run semgrep --config "$RULES_DIR/walter-os-python-eval-injection.yml" \
    "$FIXTURES_DIR/positive/python-eval-injection.sh" \
    --error
  # semgrep exits non-zero with --error when findings exist.
  [ "$status" -ne 0 ]
  [[ "$output" == *"walter-os-python-triple-quote-interpolation"* ]]
}

@test "python eval-injection rule fires on double-quote interpolation" {
  run semgrep --config "$RULES_DIR/walter-os-python-eval-injection.yml" \
    "$FIXTURES_DIR/positive/python-eval-injection.sh" \
    --error
  [ "$status" -ne 0 ]
  [[ "$output" == *"walter-os-python-eval-injection"* ]]
}

@test "shell-injection rule fires on eval with variable" {
  run semgrep --config "$RULES_DIR/walter-os-shell-injection.yml" \
    "$FIXTURES_DIR/positive/shell-injection.sh" \
    --error
  [ "$status" -ne 0 ]
  [[ "$output" == *"walter-os-eval-with-variable"* ]]
}

@test "shell-injection rule fires on bash -c with variable" {
  run semgrep --config "$RULES_DIR/walter-os-shell-injection.yml" \
    "$FIXTURES_DIR/positive/shell-injection.sh" \
    --error
  [ "$status" -ne 0 ]
  [[ "$output" == *"walter-os-bash-c-with-variable"* ]]
}

@test "curl-pipe-shell rule fires on curl ... | bash" {
  run semgrep --config "$RULES_DIR/walter-os-curl-pipe-shell.yml" \
    "$FIXTURES_DIR/positive/curl-pipe-shell.sh" \
    --error
  [ "$status" -ne 0 ]
  [[ "$output" == *"walter-os-curl-pipe-shell"* ]]
}

# --- Negative fixtures: rules MUST NOT fire on safe patterns. -----------------

@test "python eval-injection rule does NOT fire on safe stdin/env patterns" {
  run semgrep --config "$RULES_DIR/walter-os-python-eval-injection.yml" \
    "$FIXTURES_DIR/negative/python-stdin-safe.sh" \
    --error
  [ "$status" -eq 0 ]
}

@test "shell-injection rule does NOT fire on safe positional/file patterns" {
  run semgrep --config "$RULES_DIR/walter-os-shell-injection.yml" \
    "$FIXTURES_DIR/negative/shell-safe.sh" \
    --error
  [ "$status" -eq 0 ]
}

@test "curl-pipe-shell rule does NOT fire on download-verify-exec pattern" {
  run semgrep --config "$RULES_DIR/walter-os-curl-pipe-shell.yml" \
    "$FIXTURES_DIR/negative/shell-safe.sh" \
    --error
  [ "$status" -eq 0 ]
}

# --- Sanity: all rules combined ----------------------------------------------

@test "all rules combined: positive fixtures produce >=4 findings" {
  # Scan files explicitly to bypass any .semgrepignore defaults.
  run semgrep --config "$RULES_DIR/" \
    "$FIXTURES_DIR/positive/python-eval-injection.sh" \
    "$FIXTURES_DIR/positive/shell-injection.sh" \
    "$FIXTURES_DIR/positive/curl-pipe-shell.sh" \
    --json
  [ "$status" -eq 0 ]
  # JSON is single-line, so count occurrences (not lines).
  finding_count=$(echo "$output" | grep -o '"check_id"' | wc -l | tr -d ' ')
  [ "$finding_count" -ge 4 ]
}

@test "all rules combined: negative fixtures produce 0 findings" {
  run semgrep --config "$RULES_DIR/" \
    "$FIXTURES_DIR/negative/python-stdin-safe.sh" \
    "$FIXTURES_DIR/negative/shell-safe.sh" \
    --error
  [ "$status" -eq 0 ]
}
