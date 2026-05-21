#!/usr/bin/env bats
# tests/install/no-eval-in-helpers.bats
#
# Covers issue #119 AC4: run_args is safe against shell-injection
# payloads in arguments. Source the install.sh helpers in a subshell,
# pass adversarial args, assert no payload executes.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL_SH="${REPO_ROOT}/install.sh"
  [[ -f "$INSTALL_SH" ]] || skip "install.sh missing"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  PROBE="$TMP_HOME/probe.flag"
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# Helper: source install.sh helpers in a subshell that has the
# required globals stubbed (DRY_RUN etc.) and call the target helper.
_invoke() {
  bash -c "
    set -uo pipefail
    DRY_RUN=0
    CHECK_ONLY=0
    UPGRADE=1
    UNINSTALL=0
    STEP_ONLY=''
    source '$INSTALL_SH'
    $1
  "
}

# -----------------------------------------------------------------------
# AC4: run_args does NOT evaluate shell metacharacters in arguments
# -----------------------------------------------------------------------
# Copilot R1 #128 R1.1: the previous AC4 tests wrapped payloads in
# SINGLE quotes, which means bash never saw the metacharacters as
# special in the first place — even the dangerous deprecated run()
# would have passed those tests. To actually prove run_args is safer
# than run, use DOUBLE-quoted payloads (symmetric with the
# "regression: run() still evaluates" test below). Then run_args
# treating the arg as literal genuinely differentiates it from run.
@test "AC4: run_args treats ; as literal" {
  _invoke "run_args echo \"arg1 ; touch $PROBE\""
  [ ! -e "$PROBE" ]
}

@test "AC4: run_args treats | as literal" {
  _invoke "run_args echo \"arg1 | touch $PROBE\""
  [ ! -e "$PROBE" ]
}

@test "AC4: run_args treats && as literal" {
  _invoke "run_args echo \"arg1 && touch $PROBE\""
  [ ! -e "$PROBE" ]
}

@test "AC4: run_args treats command substitution as literal" {
  _invoke "run_args echo \"arg1 \\\$(touch $PROBE)\""
  [ ! -e "$PROBE" ]
}

@test "AC4: run_args treats backticks as literal" {
  # Use a non-interpolating single-quoted bash payload via env passing.
  _invoke "PAYLOAD='\`touch $PROBE\`'; run_args echo \"arg1 \$PAYLOAD\""
  [ ! -e "$PROBE" ]
}

# -----------------------------------------------------------------------
# Regression: run() (the deprecated eval helper) STILL evaluates
# metacharacters — proves we kept the contract for backward compat
# AND proves the new run_args is strictly safer than run.
# -----------------------------------------------------------------------
@test "regression: deprecated run() still evaluates ; (proves run_args is needed)" {
  _invoke "run \"echo arg1 ; touch $PROBE\""
  # The deprecated run() WILL touch the probe — confirms we still have
  # eval semantics for legacy callers, and explains why migrating away
  # from it is the right call.
  [ -e "$PROBE" ]
}

# -----------------------------------------------------------------------
# Source-level: every call site in install.sh uses run_args (not run)
# for the patterns we migrated. Catches future regressions.
# -----------------------------------------------------------------------
@test "AC2: zero call sites use the deprecated run() helper" {
  # grep -c returns 1 when no lines match (count=0). Tolerate that
  # exit code via || true so the assignment doesn't fail under bats'
  # implicit `set -e`.
  count=$(grep -cE '^[[:space:]]*run "' "$INSTALL_SH" || true)
  [ "$count" -eq 0 ]
}

@test "AC2: run_args call sites count is at least 10" {
  count=$(grep -cE 'run_args ' "$INSTALL_SH")
  [ "$count" -ge 10 ]
}
