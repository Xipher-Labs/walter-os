#!/usr/bin/env bats
# tests/hooks/workflow-pins.bats
# Verify that all GitHub Actions workflow files pin actions to commit SHAs
# (not floating @vN tags) — supply-chain hardening (audit #82).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"

@test "A-4: no workflow file uses actions/checkout@v<N> (floating tag)" {
  run grep -rn 'uses:[[:space:]]*actions/checkout@v[0-9]' "$WORKFLOWS_DIR"
  [ "$status" -ne 0 ]
}

@test "A-4: no workflow file uses actions/setup-node@v<N> (floating tag)" {
  run grep -rn 'uses:[[:space:]]*actions/setup-node@v[0-9]' "$WORKFLOWS_DIR"
  [ "$status" -ne 0 ]
}

@test "A-4: no workflow file uses pnpm/action-setup@v<N> (floating tag)" {
  run grep -rn 'uses:[[:space:]]*pnpm/action-setup@v[0-9]' "$WORKFLOWS_DIR"
  [ "$status" -ne 0 ]
}

@test "A-4: no workflow file uses actions/upload-artifact@v<N> (floating tag)" {
  run grep -rn 'uses:[[:space:]]*actions/upload-artifact@v[0-9]' "$WORKFLOWS_DIR"
  [ "$status" -ne 0 ]
}

@test "A-4: ci.yml uses pinned SHA for actions/checkout" {
  run grep 'actions/checkout@' "$WORKFLOWS_DIR/ci.yml"
  [ "$status" -eq 0 ]
  # SHA is 40 hex chars
  echo "$output" | grep -qE 'actions/checkout@[0-9a-f]{40}'
}

@test "A-4: control-tower.yml uses pinned SHA for actions/setup-node" {
  run grep 'actions/setup-node@' "$WORKFLOWS_DIR/control-tower.yml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'actions/setup-node@[0-9a-f]{40}'
}

@test "A-4: control-tower.yml uses pinned SHA for pnpm/action-setup" {
  run grep 'pnpm/action-setup@' "$WORKFLOWS_DIR/control-tower.yml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'pnpm/action-setup@[0-9a-f]{40}'
}

@test "A-4: control-tower.yml uses pinned SHA for actions/upload-artifact" {
  run grep 'actions/upload-artifact@' "$WORKFLOWS_DIR/control-tower.yml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'actions/upload-artifact@[0-9a-f]{40}'
}
