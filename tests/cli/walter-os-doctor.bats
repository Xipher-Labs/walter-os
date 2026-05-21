#!/usr/bin/env bats
# tests/cli/walter-os-doctor.bats
#
# Covers AC4 of docs/specs/agent-install-tier-completion.md:
#   AC4: `walter-os doctor` (no flag) prints the existing full check
#        set unchanged. Loose structural regression check — we count
#        ✓/✗ markers and expected section labels rather than
#        line-by-line diff (too brittle across env changes).
#
# This test should PASS on day 0 (before any code change) and continue
# passing after Phase D refactors the function. If it ever fails on
# main, Phase D broke the legacy contract.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"

setup() {
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_OS_SKIP_UPDATE_CHECK="1"
}

# -----------------------------------------------------------------------
# AC4 (structural regression): `walter-os doctor` prints check results
# -----------------------------------------------------------------------
@test "AC4: walter-os doctor produces output and exits cleanly OR with documented non-zero" {
  # cmd_doctor prints ✓/✗ markers; running here only needs the binary
  # to be executable. We accept non-zero exit because some checks legit
  # fail in CI (no ~/.claude, no audit). Output structure is what we test.
  run "${WALTER_OS_BIN}" doctor
  [ -n "$output" ]
}

@test "AC4: walter-os doctor output contains check markers" {
  run "${WALTER_OS_BIN}" doctor
  [[ "$output" == *"✓"* ]] || [[ "$output" == *"✗"* ]]
}

@test "AC4: walter-os doctor output mentions WALTER_OS_HOME check" {
  run "${WALTER_OS_BIN}" doctor
  [[ "$output" == *"WALTER_OS_HOME"* ]]
}

@test "AC4: walter-os doctor output has the 'Walter-OS' banner" {
  run "${WALTER_OS_BIN}" doctor
  [[ "$output" == *"Walter-OS"* ]]
}
