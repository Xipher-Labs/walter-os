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
  # Copilot R2 #128 R2.4: pass raw backticks via an exported env var
  # (single-quoted at assignment so they aren't executed at outer
  # parse time). Inside _invoke, $PAYLOAD expands to the literal
  # backtick string; bash does not re-evaluate substitutions inside
  # already-substituted values, so under run_args's argv path the
  # backticks are passed verbatim to echo. If a regression re-introduced
  # eval semantics, the substitution would fire and touch the probe.
  PROBE="$PROBE" PAYLOAD='`touch '"$PROBE"'`' \
    _invoke 'run_args echo "arg1 $PAYLOAD"'
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
  # Copilot R2 #128 R2.5: anchor to leading whitespace so we only
  # count actual call sites, not the function definition (line 231,
  # no leading whitespace) nor the docs comments (start with '#').
  # A regression that drops the real call site count to single
  # digits will now fail the assertion.
  count=$(grep -cE '^[[:space:]]+run_args ' "$INSTALL_SH")
  [ "$count" -ge 10 ]
}

# -----------------------------------------------------------------------
# R3: arg-count guards on run_args / run_sh / write_file
# -----------------------------------------------------------------------
# Copilot R3 #128 — under set -euo pipefail, an empty "$@" expansion in
# run_args silently succeeds (masking call-site bugs); missing positional
# args to run_sh / write_file surface as confusing unbound errors. All
# three helpers now exit 2 with a clear message on misuse.

@test "AC-R3: run_args with zero args returns 2 with usage message" {
  run bash -c "set -uo pipefail; DRY_RUN=0; CHECK_ONLY=0; UPGRADE=1; UNINSTALL=0; STEP_ONLY=''; source '$INSTALL_SH'; run_args"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires at least 1 argument"* ]]
}

@test "AC-R3: run_sh with zero args returns 2" {
  run bash -c "set -uo pipefail; DRY_RUN=0; CHECK_ONLY=0; UPGRADE=1; UNINSTALL=0; STEP_ONLY=''; source '$INSTALL_SH'; run_sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires exactly 1 argument"* ]]
}

@test "AC-R3: write_file with 1 arg returns 2" {
  run bash -c "set -uo pipefail; DRY_RUN=0; CHECK_ONLY=0; UPGRADE=1; UNINSTALL=0; STEP_ONLY=''; source '$INSTALL_SH'; write_file /tmp/foo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires exactly 2 arguments"* ]]
}

# -----------------------------------------------------------------------
# R3: trailing newline preservation on write_file
# -----------------------------------------------------------------------
# Copilot R3 #128 (MAJOR): `content="$(cat <<EOF ... )"` strips trailing
# newlines (bash command-substitution semantics). The previous direct-
# heredoc form (cat > file <<EOF) produced exactly one trailing newline.
# write_file now appends a single '\n' via printf '%s\n' to restore that.

@test "AC-R3: write_file preserves one trailing newline (heredoc parity)" {
  local out="$TMP_HOME/wf-test.txt"
  _invoke "write_file '$out' 'line1
line2'"
  [ -f "$out" ]
  # Byte-equivalent to `cat > $out <<EOF\nline1\nline2\nEOF`: 12 bytes.
  local size; size=$(wc -c <"$out" | tr -d ' ')
  [ "$size" -eq 12 ]
  [[ "$(tail -c 1 "$out" | od -An -c | tr -d ' ')" == "\\n" ]]
}

# -----------------------------------------------------------------------
# R3: run_sh no longer relies on inner eval
# -----------------------------------------------------------------------
# Copilot R3 #128: switched from `bash -c 'set -euo pipefail; eval "$1"' bash "$1"`
# to `printf '%s\n' 'set -euo pipefail' "$1" | bash -s` so there's no
# extra eval layer. Lock the new pattern in.

@test "AC-R3: run_sh impl uses bash -s pipe (no eval layer)" {
  grep -qE "printf '%s\\\\n' 'set -euo pipefail' \"\\\$1\" \\| bash -s" "$INSTALL_SH"
}

@test "AC-R3: run_sh does NOT pass snippet via 'bash -c .* eval' (call sites only)" {
  # Anchor to leading whitespace so the historical-pattern documentation
  # comment inside run_sh (lines starting with '#') doesn't false-fail
  # this assertion. Only flag a real call-site regression.
  ! grep -qE '^[[:space:]]+bash -c .* eval "\$1"' "$INSTALL_SH"
}
