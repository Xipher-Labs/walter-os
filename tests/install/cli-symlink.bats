#!/usr/bin/env bats
# tests/install/cli-symlink.bats
#
# Covers AC1, AC2, AC3 of docs/specs/agent-install-tier-completion.md:
#   AC1: install.sh --upgrade creates ~/.local/bin/walter-os symlink
#        pointing at ${WALTER_OS_HOME}/bin/walter-os.
#   AC2: invoking ~/.local/bin/walter-os --version exits 0 and prints
#        a semver-like string.
#   AC3: re-running install.sh --upgrade is idempotent (no error, no
#        duplicate symlink, target unchanged).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  # Sandbox $HOME so we never touch the operator's machine.
  export TEST_HOME="$(mktemp -d "${BATS_TMPDIR}/walter-cli-symlink-XXXXXX")"
  export HOME="$TEST_HOME"
  export WALTER_OS_HOME="$REPO_ROOT"
  export REPO_ROOT  # link_walter_cli reads this
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Invoke link_walter_cli (the new install.sh function introduced in
# Phase C) in a subshell. We can't source install.sh into the bats
# scope because install.sh defines its own `run` function which
# would shadow bats' run helper. Subshell isolates the scope.
invoke_link_walter_cli() {
  HOME="$HOME" WALTER_OS_HOME="$WALTER_OS_HOME" REPO_ROOT="$REPO_ROOT" \
    bash -c '
      set +u
      DRY_RUN=0
      CHECK_ONLY=0
      UPGRADE=1
      UNINSTALL=0
      STEP_ONLY=""
      source "${REPO_ROOT}/install.sh"
      link_walter_cli
    '
}

# -----------------------------------------------------------------------
# AC1: symlink is created at the expected path with the expected target
# -----------------------------------------------------------------------
@test "AC1: link_walter_cli creates ~/.local/bin/walter-os symlink" {
  invoke_link_walter_cli >/dev/null 2>&1 || true
  [ -L "${HOME}/.local/bin/walter-os" ]
}

@test "AC1: symlink target is \${WALTER_OS_HOME}/bin/walter-os" {
  invoke_link_walter_cli >/dev/null 2>&1 || true
  [ -L "${HOME}/.local/bin/walter-os" ]
  target="$(readlink "${HOME}/.local/bin/walter-os")"
  [ "${target}" = "${WALTER_OS_HOME}/bin/walter-os" ]
}

# -----------------------------------------------------------------------
# AC2: invoking the symlink works
# -----------------------------------------------------------------------
@test "AC2: invoking ~/.local/bin/walter-os --version exits 0" {
  invoke_link_walter_cli >/dev/null 2>&1 || true
  [ -L "${HOME}/.local/bin/walter-os" ]
  run "${HOME}/.local/bin/walter-os" --version
  [ "$status" -eq 0 ]
  # Output should contain at least one digit (semver / version string).
  [[ "$output" =~ [0-9] ]]
}

# -----------------------------------------------------------------------
# AC3: idempotency — running link_walter_cli twice does not error / duplicate
# -----------------------------------------------------------------------
@test "AC3: re-running link_walter_cli is idempotent" {
  invoke_link_walter_cli >/dev/null 2>&1 || true
  first_target="$(readlink "${HOME}/.local/bin/walter-os" 2>/dev/null || echo NONE)"
  [ "$first_target" != "NONE" ]

  # Second invocation: must not error and must leave the same target.
  invoke_link_walter_cli >/dev/null 2>&1
  second_target="$(readlink "${HOME}/.local/bin/walter-os")"
  [ "$first_target" = "$second_target" ]
}

# -----------------------------------------------------------------------
# Source-level guard: link_walter_cli is wired into run_step_0 so it
# actually runs as part of --upgrade. Without this, the function could
# exist as dead code.
# -----------------------------------------------------------------------
@test "link_walter_cli is called from run_step_0" {
  grep -qE "^[[:space:]]*link_walter_cli[[:space:]]*$" "${REPO_ROOT}/install.sh"
}
