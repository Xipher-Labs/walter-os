#!/usr/bin/env bats
# tests/install/escape-helpers.bats
#
# Closes #133 (REPO_ROOT shell-escape) + #134 (audit_script XML-escape).
# Validates _shell_quote + _xml_escape helpers AND the env-file +
# plist render paths that consume them.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL_SH="${REPO_ROOT}/install.sh"
  [[ -f "$INSTALL_SH" ]] || skip "install.sh missing"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  mkdir -p "$WALTER_CONFIG"
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# Helper: source install.sh under a stub env that loads the helpers
# without running the full installer. The same pattern as
# tests/install/no-eval-in-helpers.bats's _invoke.
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
# _shell_quote — closes #133
# -----------------------------------------------------------------------
@test "#133: _shell_quote handles a plain path" {
  run _invoke "_shell_quote /tmp/foo"
  [ "$status" -eq 0 ]
  # printf '%q' outputs unquoted form for paths without metacharacters
  [ "$output" = "/tmp/foo" ]
}

@test "#133: _shell_quote escapes a path containing a single quote" {
  run _invoke "_shell_quote \"/tmp/foo'; touch INJECTION #\""
  [ "$status" -eq 0 ]
  # The quoted form must NOT contain a bare apostrophe followed by `;`.
  # printf '%q' produces something like /tmp/foo\'\;\ touch\ INJECTION\ \#
  [[ "$output" != *"'; touch"* ]]
  # And the escaped form must round-trip back to the original:
  local roundtrip
  roundtrip=$(eval "echo $output")
  [ "$roundtrip" = "/tmp/foo'; touch INJECTION #" ]
}

@test "#133: env-file rendered from a quoted-path source is safe to re-source" {
  # End-to-end byte test: render write_env_file with the real install.sh
  # (REPO_ROOT == install.sh's parent dir, which is the worktree under
  # /tmp/walter-escape). The crucial behavior is that the rendered file
  # round-trips: source it, get WALTER_OS_HOME back identical.
  _invoke "write_env_file" >/dev/null 2>&1
  local env_file="$WALTER_CONFIG/env"
  [ -f "$env_file" ]
  # The export line must use printf '%q' output, not the old literal
  # '${REPO_ROOT}' form. Static check: no single-quoted REPO_ROOT
  # literal remains in the rendered output.
  ! grep -qE "^export WALTER_OS_HOME='" "$env_file"
  # And the file must round-trip to the original REPO_ROOT.
  local got expected
  expected="$REPO_ROOT"
  got=$(bash -c "source '$env_file'; printf '%s' \"\$WALTER_OS_HOME\"")
  [ "$got" = "$expected" ]
}

# -----------------------------------------------------------------------
# _xml_escape — closes #134
# -----------------------------------------------------------------------
@test "#134: _xml_escape leaves plain ASCII untouched" {
  run _invoke '_xml_escape "/tmp/walter-os/skills/daily-supply-chain-audit/scripts/audit.sh"'
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/walter-os/skills/daily-supply-chain-audit/scripts/audit.sh" ]
}

@test "#134: _xml_escape escapes the 5 XML-reserved characters" {
  run _invoke '_xml_escape "<a&b>'"'"'c'"'"'\"d\""'
  [ "$status" -eq 0 ]
  # & must escape FIRST so we don't double-escape entities we add later
  [ "$output" = "&lt;a&amp;b&gt;&apos;c&apos;&quot;d&quot;" ]
}

@test "#134: _xml_escape ampersand-first ordering — no double-escape" {
  # If '&' weren't escaped first, '<' → '&lt;' would itself contain '&'
  # which would then become '&amp;lt;'. Lock in the correct order.
  run _invoke '_xml_escape "<"'
  [ "$status" -eq 0 ]
  [ "$output" = "&lt;" ]
  [ "$output" != "&amp;lt;" ]
}

# -----------------------------------------------------------------------
# Source-level: both helpers exist
# -----------------------------------------------------------------------
@test "install.sh defines _shell_quote and _xml_escape" {
  grep -qE '^_shell_quote\(\)' "$INSTALL_SH"
  grep -qE '^_xml_escape\(\)' "$INSTALL_SH"
}

@test "env-file render uses _shell_quote on REPO_ROOT" {
  grep -qE '_shell_quote "\$REPO_ROOT"' "$INSTALL_SH"
}

@test "plist render uses _xml_escape on every interpolated string" {
  # Four sites: label, audit_script, stdout, stderr
  [[ $(grep -cE '_xml_escape "\$(DAILY_AUDIT_LABEL|audit_script|WALTER_CONFIG)' "$INSTALL_SH") -ge 4 ]]
}
