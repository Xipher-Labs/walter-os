#!/usr/bin/env bats
# Tests for P0-05: submodules must be pinned to commit hashes, not branches.
# See: docs/operational/security-audit-2026-05-11.md P0-05

GITMODULES="$BATS_TEST_DIRNAME/../../.gitmodules"

@test "P0-05: .gitmodules contains no 'branch =' directive" {
  run grep -E '^\s*branch\s*=' "$GITMODULES"
  # grep returns exit 1 when no match — that is what we want
  [[ "$status" -eq 1 ]]
}

@test "P0-05: marchetto-agent-skills pinned commit is documented in .gitmodules" {
  run grep -E 'PINNED|pinned|[0-9a-f]{40}' "$GITMODULES"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ [0-9a-f]{7,} ]]
}

@test "P0-05: vercel-agent-skills pinned commit is documented in .gitmodules" {
  run grep -E 'vercel' "$GITMODULES"
  [[ "$status" -eq 0 ]]
  # verify the section exists
  [[ "$output" =~ vercel-agent-skills ]]
}

@test "P0-05: git submodule status shows no + or - prefix (dirty/uninitialized)" {
  cd "$BATS_TEST_DIRNAME/../.."
  run git submodule status
  # + means newer commit checked out than registered; - means not initialized
  # Neither should be present; each line should start with a space or nothing
  if [[ "$status" -eq 0 && -n "$output" ]]; then
    # No line should start with + or -
    echo "$output" | grep -qE '^[+-]' && return 1 || return 0
  fi
  return 0
}
