#!/usr/bin/env bats
# Tests for setup/walter-host/install-cron.sh — M2 (--user flag) + M3 (probe stdout)

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../setup/walter-host/install-cron.sh"
  [[ -f "$SCRIPT" ]] || skip "install-cron.sh not found"
}

# ---- M2: --user flag parsing ----

@test "install-cron.sh accepts --user flag" {
  # Should parse --user and not error out with unknown option
  run "$SCRIPT" --user testuser 2>&1
  # If crontab binary exists, error is about crontab -u, not arg parsing.
  # We only check that the script doesn't emit "unknown option/flag" errors.
  ! [[ "$output" =~ "unknown" ]]
  ! [[ "$output" =~ "unrecognized" ]]
  # The script should print the user name it is targeting
  [[ "$output" =~ "testuser" ]]
}

@test "install-cron.sh --user value appears in output" {
  run "$SCRIPT" --user mywalteruser 2>&1
  [[ "$output" =~ "mywalteruser" ]]
}

@test "install-cron.sh positional arg (legacy) also works" {
  # Backward compat: install-cron.sh legacyuser still reads username
  run "$SCRIPT" legacyuser 2>&1
  [[ "$output" =~ "legacyuser" ]]
}

# ---- M15: --user without value must exit 2 ----

@test "M15: install-cron.sh --user without value exits 2 with error message" {
  # Under set -u, bare --user without a value derefs unbound $2 and crashes.
  # After fix: must exit 2 with a useful error message.
  run bash "$SCRIPT" --user
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ [Ee]rror || "$output" =~ [Vv]alue || "$output" =~ [Rr]equires || \
     "$output" =~ "--user" ]] || \
    { echo "Expected error/value/requires/--user in output; got: '$output'"; false; }
}

# ---- M3: probe does not dump crontab to stdout ----

@test "install-cron.sh probe redirects crontab stdout to /dev/null" {
  # The fix: crontab -l probe must redirect stdout to /dev/null so the
  # existing crontab is not dumped to install-cron.sh's stdout.
  # Static check: the if crontab ... -l line must have [0-9]*>/dev/null (stdout redir)
  # NOT just 2>/dev/null (stderr-only). Grep for 1>/dev/null or a bare >/dev/null
  # that is preceded by something other than '2'.
  grep -qE 'if crontab.*-l.*[^2]>/dev/null|if crontab.*-l.* >/dev/null' "$SCRIPT"
}
