#!/usr/bin/env bats
# Tests for T-20: watchdog cron entry
# Covers: AC-2 of Improvement 5

@test "watchdog cron file exists" {
  local cron_file="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/watchdog"
  [[ -f "$cron_file" ]]
}

@test "watchdog cron entry runs every 5 minutes" {
  local cron_file="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/watchdog"
  [[ -f "$cron_file" ]] || skip "cron file not found"
  # Must contain */5 schedule
  grep -q '^\*/5' "$cron_file"
}

@test "watchdog cron entry references watchdog script" {
  local cron_file="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/watchdog"
  [[ -f "$cron_file" ]] || skip "cron file not found"
  grep -qiE "watchdog" "$cron_file"
}

@test "watchdog cron entry redirects output to log file" {
  local cron_file="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/watchdog"
  [[ -f "$cron_file" ]] || skip "cron file not found"
  # Must redirect output (>> or >) to a log path
  grep -qE '>>' "$cron_file"
}

@test "watchdog cron file is non-empty" {
  local cron_file="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/watchdog"
  [[ -f "$cron_file" ]] || skip "cron file not found"
  [[ -s "$cron_file" ]]
}

# ---- R1: no username column in per-user crontab fragment ----

@test "R1: watchdog cron fragment has no username column (valid for crontab -u)" {
  local cron_file="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/watchdog"
  [[ -f "$cron_file" ]] || skip "cron file not found"
  # Per-user crontab format: MIN HOUR DOM MON DOW command
  # /etc/cron.d format adds username after schedule: MIN ... DOW USER cmd
  # This fragment is installed via crontab -u; username column is invalid.
  # Check that the active cron line does NOT have a username after the schedule.
  # The pattern 'field6 = username' appears as whitespace-separated 6th field that
  # is a word (not a path starting with / or $).
  local active_line
  active_line="$(grep -E '^\*/[0-9]' "$cron_file" | head -1)"
  # 6th field must be a command/path (starts with $ or / or .)
  # NOT a bare username like 'walter'
  local field6
  field6="$(echo "$active_line" | awk '{print $6}')"
  [[ "$field6" =~ ^[/$\.] ]]
}
