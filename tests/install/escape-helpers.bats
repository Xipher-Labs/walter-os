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
# without running the full installer.
#
# Copilot R2 #138 + R1 #141: pass INSTALL_SH + the command string via
# ENV VARS (NOT bash -c positional args + NOT string interpolation
# into the script body). The previous `source '$INSTALL_SH'` form
# broke under quoted paths (a single quote in the install.sh path
# terminated the literal). Env vars work for any path — `source "$VAR"`
# inside the inner bash tolerates everything.
_invoke() {
  # `set --` clears positional args before sourcing — install.sh
  # parses $@ at source time and would otherwise see whatever
  # positional args the bats caller had as install.sh's own args.
  WALTER_INSTALL_SH="$INSTALL_SH" WALTER_INVOKE_CMD="$1" \
  bash -c '
    set -uo pipefail
    DRY_RUN=0
    CHECK_ONLY=0
    UPGRADE=1
    UNINSTALL=0
    STEP_ONLY=""
    # Clear positional args (install.sh expects none when sourced).
    set --
    # shellcheck source=/dev/null
    source "$WALTER_INSTALL_SH"
    eval "$WALTER_INVOKE_CMD"
  '
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
  # Copilot R2 #138: the round-trip uses `eval` on _shell_quote's
  # output. If _shell_quote ever regresses, that eval would execute
  # the injection payload (the `touch INJECTION` in the input). Two
  # defenses applied here:
  #   1. The probe filename lives in an isolated $TMP_HOME subdir
  #      that bats already cleans up on teardown.
  #   2. After the round-trip, ASSERT the probe file does NOT exist —
  #      so a future regression is caught with a clear failure
  #      rather than a silently-passing test that ran the payload.
  local canary_dir="$TMP_HOME/quote-roundtrip-canary"
  mkdir -p "$canary_dir"
  local canary="$canary_dir/INJECTION"
  run _invoke "_shell_quote \"/tmp/foo'; touch $canary; #\""
  [ "$status" -eq 0 ]
  # The quoted form must NOT contain a bare apostrophe followed by `;`.
  # printf '%q' produces something like /tmp/foo\'\;\ touch\ INJECTION\ \#
  [[ "$output" != *"'; touch"* ]]
  # Round-trip via eval (in the isolated $TMP_HOME context).
  local roundtrip
  roundtrip=$(eval "echo $output")
  [ "$roundtrip" = "/tmp/foo'; touch $canary; #" ]
  # And — critically — the eval did NOT actually execute the
  # `touch $canary` payload. If _shell_quote regresses, this fails.
  [ ! -e "$canary" ]
}

@test "#133: env-file rendered from a quoted-path source is safe to re-source" {
  # End-to-end byte test under a malicious clone-path: copy install.sh
  # to a dir whose name contains shell metacharacters, run write_env_file
  # from that copy, then source the rendered env file in a clean subshell
  # and assert the malicious payload did NOT execute (no canary file).
  #
  # Copilot R2 #138: the previous version of this test ran against the
  # real worktree's REPO_ROOT, which has no metacharacters — so it would
  # silently pass even if the integration broke under a quoted path.
  # This version actually exercises the #133 exploit scenario.
  # Copilot R2 #141 catch: the canary must appear IN the malicious
  # path so that a regression which falls back to literal single-
  # quote interpolation actually attempts to execute the canary-touch
  # payload. The previous version of this test had a $canary variable
  # but never embedded it in the dir name — so the assertion was a
  # tautology (no payload could ever touch the canary).
  local canary="$TMP_HOME/env-file-canary"
  local malicious_dir="$TMP_HOME/foo'; touch $canary; #"
  mkdir -p "$malicious_dir"
  cp "$INSTALL_SH" "$malicious_dir/install.sh"

  INSTALL_SH="$malicious_dir/install.sh" _invoke "write_env_file" >/dev/null 2>&1
  local env_file="$WALTER_CONFIG/env"
  [ -f "$env_file" ]

  # No literal-single-quoted form in the rendered output (would mean
  # we regressed to the pre-#133 `'${REPO_ROOT}'` template).
  ! grep -qE "^export WALTER_OS_HOME='" "$env_file"

  # Source in a clean subshell + verify the canary was NOT touched —
  # if _shell_quote regressed, sourcing would execute `touch $canary`
  # from the injected payload.
  bash -c "source '$env_file'; true" >/dev/null 2>&1 || true
  [ ! -e "$canary" ]

  # And WALTER_OS_HOME (post-source) equals the malicious path verbatim.
  local got
  got=$(bash -c "source '$env_file'; printf '%s' \"\$WALTER_OS_HOME\"")
  [ "$got" = "$malicious_dir" ]
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
