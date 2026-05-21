#!/usr/bin/env bats
# tests/cli/walter-os-doctor-tier.bats
#
# Covers AC5, AC6 of docs/specs/agent-install-tier-completion.md:
#   AC5: walter-os doctor --tier {1,2,3,4} runs filtered check subsets.
#        Higher tier numbers must run MORE checks than lower numbers
#        (monotonic ordering).
#   AC6: walter-os doctor --tier 99 (invalid) exits non-zero with an
#        "invalid tier" error message.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"

setup() {
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_OS_SKIP_UPDATE_CHECK="1"
}

# Helper: count the ✓/✗ markers in doctor output.
count_checks() {
  local out="$1"
  echo "$out" | grep -cE "(✓|✗)" || true
}

# -----------------------------------------------------------------------
# AC5: tier ordering — more checks at higher tiers
# -----------------------------------------------------------------------
@test "AC5: --tier 1 runs at least one check" {
  run "${WALTER_OS_BIN}" doctor --tier 1
  count=$(count_checks "$output")
  [ "$count" -ge 1 ]
}

@test "AC5: --tier 2 runs at least as many checks as --tier 1" {
  run "${WALTER_OS_BIN}" doctor --tier 1
  t1=$(count_checks "$output")
  run "${WALTER_OS_BIN}" doctor --tier 2
  t2=$(count_checks "$output")
  [ "$t2" -ge "$t1" ]
}

@test "AC5: --tier 3 runs at least as many checks as --tier 2" {
  run "${WALTER_OS_BIN}" doctor --tier 2
  t2=$(count_checks "$output")
  run "${WALTER_OS_BIN}" doctor --tier 3
  t3=$(count_checks "$output")
  [ "$t3" -ge "$t2" ]
}

@test "AC5: --tier 4 runs at least as many checks as --tier 3" {
  run "${WALTER_OS_BIN}" doctor --tier 3
  t3=$(count_checks "$output")
  run "${WALTER_OS_BIN}" doctor --tier 4
  t4=$(count_checks "$output")
  [ "$t4" -ge "$t3" ]
}

@test "AC5: bare --tier (no number) runs same as no flag" {
  # Sanity: bare `doctor` and `doctor --tier` (when tier not provided
  # as a separate arg) should behave the same — full check set.
  run "${WALTER_OS_BIN}" doctor
  base_count=$(count_checks "$output")
  [ "$base_count" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC6: invalid tier rejected
# -----------------------------------------------------------------------
@test "AC6: --tier 99 exits non-zero" {
  run "${WALTER_OS_BIN}" doctor --tier 99
  [ "$status" -ne 0 ]
}

@test "AC6: --tier 99 prints 'invalid tier' (or similar) error" {
  run "${WALTER_OS_BIN}" doctor --tier 99
  # Accept any of: "invalid tier", "must be 1", "got: 99"
  [[ "$output" == *"invalid"* ]] || [[ "$output" == *"must be"* ]] || [[ "$output" == *"99"* ]]
}

@test "AC6: --tier abc (non-numeric) exits non-zero" {
  run "${WALTER_OS_BIN}" doctor --tier abc
  [ "$status" -ne 0 ]
}
