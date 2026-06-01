#!/usr/bin/env bats
# Smoke test for install.sh --dry-run

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export CLAUDE_HOME="$TEST_HOME/.claude"
  export CODEX_HOME="$TEST_HOME/.codex"
  export WALTER_CONFIG="$TEST_HOME/.config/walter-os"
  export LAUNCH_AGENTS="$TEST_HOME/Library/LaunchAgents"
  cd "$REPO_ROOT"
}

teardown() {
  case "${TEST_HOME:-}" in
    /tmp/*|/var/folders/*|/var/tmp/*)
      [[ -d "$TEST_HOME" ]] && rm -r "$TEST_HOME"
      ;;
  esac
}

@test "install.sh --dry-run exits 0" {
  run bash ./install.sh --dry-run
  [ "$status" -eq 0 ]
}

@test "install.sh --dry-run mentions every key step" {
  run bash ./install.sh --dry-run
  [[ "$output" == *"Preflight"* ]]
  [[ "$output" == *"directories"* ]]
  [[ "$output" == *"root config files"* ]]
  [[ "$output" == *"skills"* ]]
  [[ "$output" == *"hooks"* ]]
}

@test "install.sh --help prints something" {
  run bash ./install.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install.sh"* ]] || [[ "$output" == *"Walter-OS"* ]]
}

@test "install.sh --help does not print internal section comments" {
  run bash ./install.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"---------- config ----------"* ]]
  [[ "$output" != *"!/usr/bin/env bash"* ]]
}

@test "install.sh --check runs requirements check without writes" {
  run bash ./install.sh --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Requirements check"* ]]
  [[ "$output" == *"Minimum requirements satisfied"* ]]
}

@test "install.sh rejects unknown flags" {
  run bash ./install.sh --not-a-real-flag
  [ "$status" -eq 2 ]
}
