#!/usr/bin/env bats
# Tests for walter-os doctor PM config checks [AC-10]

WALTER_OS_BIN="${BATS_TEST_DIRNAME}/../../bin/walter-os"
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
  FAKE_HOME="$(mktemp -d)"
  export FAKE_HOME
  FAKE_WALTER_CONFIG="$(mktemp -d)"
  export FAKE_WALTER_CONFIG
  mkdir -p "$FAKE_HOME/.config/pnpm"
}

teardown() {
  rm -rf "$TMPDIR" "$FAKE_HOME" "$FAKE_WALTER_CONFIG"
}

_run_doctor() {
  WALTER_CONFIG="$FAKE_WALTER_CONFIG" WALTER_OS_HOME="$REPO_ROOT" HOME="$FAKE_HOME" \
    "$WALTER_OS_BIN" doctor 2>/dev/null
}

@test "doctor output includes bunfig.toml minimumReleaseAge check" {
  # Create a bunfig.toml with the key
  printf '[install]\nminimumReleaseAge = "1209600s"\n' > "$FAKE_HOME/.bunfig.toml"
  printf 'minimum-release-age=20160\n' > "$FAKE_HOME/.config/pnpm/rc"

  run _run_doctor || true
  echo "$output" | grep -q "minimumReleaseAge\|minimum-release-age\|bunfig\|pnpm"
}

@test "doctor output includes pnpm rc minimum-release-age check" {
  printf '[install]\nminimumReleaseAge = "1209600s"\n' > "$FAKE_HOME/.bunfig.toml"
  printf 'minimum-release-age=20160\n' > "$FAKE_HOME/.config/pnpm/rc"

  run _run_doctor || true
  echo "$output" | grep -q "pnpm\|minimum-release-age"
}
