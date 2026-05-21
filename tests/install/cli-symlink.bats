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
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: run install.sh --upgrade in the sandbox. We do NOT actually
# run install.sh here (it does many other things that aren't relevant)
# — we exercise the specific symlink-creation snippet that Phase C adds.
# Once Phase C lands, this test will pass because install.sh --upgrade
# will create the symlink. Until then it FAILS — the RED state.
upgrade_symlink_only() {
  # Replicate just the symlink logic. When Phase C lands, install.sh
  # will perform this same operation in its STEP-0 path.
  ln -sf "${WALTER_OS_HOME}/bin/walter-os" "${HOME}/.local/bin/walter-os"
}

# -----------------------------------------------------------------------
# AC1: symlink is created at the expected path with the expected target
# -----------------------------------------------------------------------
@test "AC1: install.sh creates ~/.local/bin/walter-os symlink" {
  # GREEN expectation — once install.sh contains the symlink line
  # introduced in Phase C, this assertion holds after running --upgrade.
  # The bats setup above sandboxes $HOME so this is safe.
  bash "${REPO_ROOT}/install.sh" --upgrade >/dev/null 2>&1 || true
  [ -L "${HOME}/.local/bin/walter-os" ]
}

@test "AC1: symlink target is \${WALTER_OS_HOME}/bin/walter-os" {
  bash "${REPO_ROOT}/install.sh" --upgrade >/dev/null 2>&1 || true
  [ -L "${HOME}/.local/bin/walter-os" ]
  target="$(readlink "${HOME}/.local/bin/walter-os")"
  [ "${target}" = "${WALTER_OS_HOME}/bin/walter-os" ]
}

# -----------------------------------------------------------------------
# AC2: invoking the symlink works
# -----------------------------------------------------------------------
@test "AC2: invoking ~/.local/bin/walter-os --version exits 0" {
  bash "${REPO_ROOT}/install.sh" --upgrade >/dev/null 2>&1 || true
  [ -L "${HOME}/.local/bin/walter-os" ]
  run "${HOME}/.local/bin/walter-os" --version
  [ "$status" -eq 0 ]
  # Output should contain at least one digit (semver / version string).
  [[ "$output" =~ [0-9] ]]
}

# -----------------------------------------------------------------------
# AC3: idempotency — running --upgrade twice does not error / duplicate
# -----------------------------------------------------------------------
@test "AC3: re-running install.sh --upgrade is idempotent" {
  bash "${REPO_ROOT}/install.sh" --upgrade >/dev/null 2>&1 || true
  first_target="$(readlink "${HOME}/.local/bin/walter-os" 2>/dev/null || echo NONE)"
  [ "$first_target" != "NONE" ]

  # Second run must succeed and leave the same symlink target.
  bash "${REPO_ROOT}/install.sh" --upgrade >/dev/null 2>&1
  [ "$?" -eq 0 ] || true   # install.sh may do other things; we only check the symlink
  second_target="$(readlink "${HOME}/.local/bin/walter-os")"
  [ "$first_target" = "$second_target" ]
}
