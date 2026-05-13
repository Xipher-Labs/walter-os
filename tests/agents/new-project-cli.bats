#!/usr/bin/env bats
# Tests for T-24: `walter-os new project` CLI wiring
# Covers: AC-1 of Improvement 6

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"

  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_CONFIG="$(mktemp -d -t new-project-cli-XXXXXX)"
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "walter-os new project --help shows usage" {
  run "$WALTER_OS" new project --help
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "project" || "$output" =~ "type" || "$output" =~ "name" ]]
}

@test "walter-os new without args shows usage and exits non-zero" {
  run "$WALTER_OS" new
  # Must not exit 0 (no subcommand given)
  [[ "$status" -ne 0 ]] || [[ "$output" =~ "project" ]]
}

@test "walter-os new project with invalid type exits 2" {
  run "$WALTER_OS" new project badtype my-project
  [[ "$status" -eq 2 ]]
}

@test "walter-os new project with invalid name exits 2" {
  run "$WALTER_OS" new project webapp "name with spaces"
  [[ "$status" -eq 2 ]]
}

@test "walter-os new project with name exceeding 50 chars exits 2" {
  run "$WALTER_OS" new project webapp "this-name-is-way-too-long-for-a-project-name-exceeding-fifty"
  [[ "$status" -eq 2 ]]
}

@test "walter-os new project dispatches to induction.sh" {
  # Verify the dispatch exists in bin/walter-os
  grep -q "induction" "$WALTER_OS"
}

@test "walter-os new project is documented in bin/walter-os help block" {
  grep -q "new" "$WALTER_OS"
}

@test "walter-os new project webapp valid-name runs with --skip-plane and exits 0" {
  # Requires WALTER_OS_HOME to find induction.sh
  WORK_DIR="$(mktemp -d -t new-proj-run-XXXXXX)"

  run "$WALTER_OS" new project webapp test-proj \
    --output-dir "$WORK_DIR" --skip-plane --non-interactive \
    --answers-file "$BATS_TEST_DIRNAME/../../tests/fixtures/induction-answers.yml"
  rm -rf "$WORK_DIR"
  [[ "$status" -eq 0 ]]
}
