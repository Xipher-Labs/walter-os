#!/usr/bin/env bats
# Tests for P0-04: doctor.sh must not use eval with WALTER_OS_HOME.
# See: docs/operational/security-audit-2026-05-11.md P0-04

DOCTOR="$BATS_TEST_DIRNAME/../../scripts/walter/subcommands/doctor.sh"

setup() {
  TMPDIR_TEST=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "P0-04: doctor.sh exists" {
  [[ -f "$DOCTOR" ]]
}

@test "P0-04: doctor.sh check() function does not use eval" {
  # The check() helper must not use eval at all — it's structurally dangerous
  # because any future check command involving $WALTER_OS_HOME inside $() would
  # be exploitable. Replace eval with direct bash test execution.
  # See: docs/operational/security-audit-2026-05-11.md P0-04
  run grep -n '^\s*if eval\|^\s*eval "' "$DOCTOR"
  # Should find no eval usage inside check functions
  [[ "$status" -eq 1 ]]
}

@test "P0-04: WALTER_OS_HOME with injection chars does not execute injected commands" {
  # Create a marker file path to detect injection
  MARKER="$TMPDIR_TEST/injection_executed"

  # Craft WALTER_OS_HOME that tries to create the marker via shell injection.
  # If eval is used with single quotes: eval "[[ -d '$WALTER_OS_HOME' ]]"
  # then setting WALTER_OS_HOME to: /real/path'; touch /marker; echo '
  # would break out of the single quotes.
  EVIL_HOME="/nonexistent'; touch $MARKER; echo '"

  # Run doctor.sh with the evil WALTER_OS_HOME (it will fail checks, that's fine)
  # We only care that the marker file is NOT created.
  WALTER_OS_HOME="$EVIL_HOME" run bash "$DOCTOR" 2>/dev/null || true

  [[ ! -f "$MARKER" ]]
}

@test "P0-04: doctor.sh with valid WALTER_OS_HOME runs without error" {
  # Smoke test: a real path should not cause crashes
  WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.." run bash "$DOCTOR" 2>/dev/null
  # Exit 0 (all ok) or exit 1 (some checks failed) are both acceptable.
  # Exit 2+ would indicate a script error.
  [[ "$status" -le 1 ]]
}
