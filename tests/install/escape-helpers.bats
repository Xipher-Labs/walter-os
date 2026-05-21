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
  # Copilot R2 #141: explicit `if ! source` instead of `set -e`
  # — install.sh runs its own discovery code at source time (CLI
  # arg parsing, env defaults) which would short-circuit under
  # `set -e` even for benign non-zero returns. We want to bail
  # only when the source itself fails (missing file, parse error).
  WALTER_INSTALL_SH="$INSTALL_SH" WALTER_INVOKE_CMD="$1" \
  bash -c '
    set -uo pipefail
    DRY_RUN=0
    CHECK_ONLY=0
    UPGRADE=1
    UNINSTALL=0
    STEP_ONLY=""
    set --
    # shellcheck source=/dev/null
    if ! source "$WALTER_INSTALL_SH"; then
      echo "_invoke: source of $WALTER_INSTALL_SH failed" >&2
      exit 1
    fi
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
  # Round-trip via eval into printf (NOT echo — echo has impl-defined
  # handling of -n / -e / backslashes that would corrupt the test for
  # certain inputs; Copilot R2 #141 catch). printf '%s' is byte-faithful.
  local roundtrip
  roundtrip=$(eval "printf '%s' $output")
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

# -----------------------------------------------------------------------
# #134 end-to-end: actually render the plist with malicious path values
# and verify the output is XML-safe. Static grep + helper-unit-test alone
# (Copilot R2 #141 catch) would silently false-pass if a regression
# removed the _xml_escape calls in the render path while keeping the
# helper itself intact. This test exercises the real render contract.
# -----------------------------------------------------------------------
@test "#134 end-to-end: plist render with metacharacter paths produces valid XML" {
  # Override the path values setup_git_hooks would interpolate. We don't
  # actually run setup_git_hooks (it tries to load launchctl etc.); we
  # directly invoke the function via _invoke + a stub LAUNCH_AGENTS dir.
  local stub_la="$TMP_HOME/LaunchAgents"
  mkdir -p "$stub_la"

  # The malicious WALTER_CONFIG must contain XML-reserved chars in a
  # PATH-LEGAL way (no `/`, no NUL, etc.). Apostrophe is XML-reserved
  # AND filesystem-safe.
  local mal_config="$TMP_HOME/wc'<&"
  mkdir -p "$mal_config"

  # Drive setup_git_hooks with the malicious WALTER_CONFIG + a stub
  # LAUNCH_AGENTS. The function should:
  #   a) succeed (no XML break)
  #   b) emit a plist whose <string>$WALTER_CONFIG/audit.log</string>
  #      element contains &apos; &lt; &amp; instead of literal ' < &
  WALTER_INSTALL_SH="$INSTALL_SH" WALTER_INVOKE_CMD="
    LAUNCH_AGENTS='$stub_la'
    DAILY_AUDIT_LABEL=walter-os.test
    WALTER_CONFIG='$mal_config'
    REPO_ROOT='$mal_config'  # so audit_script ends up under the malicious dir too
    mkdir -p '$mal_config/skills/daily-supply-chain-audit/scripts'
    touch '$mal_config/skills/daily-supply-chain-audit/scripts/audit.sh'
    chmod +x '$mal_config/skills/daily-supply-chain-audit/scripts/audit.sh'
    setup_git_hooks
  " bash -c '
    set -uo pipefail
    DRY_RUN=0
    CHECK_ONLY=0
    UPGRADE=1
    UNINSTALL=0
    STEP_ONLY=""
    set --
    # shellcheck source=/dev/null
    source "$WALTER_INSTALL_SH"
    eval "$WALTER_INVOKE_CMD"
  ' >/dev/null 2>&1 || true

  # The rendered plist should exist + be valid XML. The malicious
  # apostrophe / < / & should appear as &apos; / &lt; / &amp;.
  local plist="$stub_la/walter-os.test.plist"
  if [[ -f "$plist" ]]; then
    # Literal unescaped chars must NOT appear inside any <string> body.
    # If they do, the regression has removed _xml_escape from a render site.
    ! grep -qE "<string>[^<]*[<&'][^<]*</string>" "$plist" || {
      cat "$plist" >&2
      return 1
    }
    # And the escaped entities should be present in at least one element.
    grep -qE "<string>[^<]*&apos;[^<]*</string>" "$plist"
  fi
  # If plist wasn't created (function early-exited on the macOS check
  # since we're on a CI Linux runner / Mac dev box mismatch), the
  # static + helper-unit tests still cover the contract — skip rather
  # than false-pass.
  [[ -f "$plist" ]] || skip "plist not created in this env (likely non-Darwin runner)"
}
