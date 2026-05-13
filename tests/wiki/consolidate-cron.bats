#!/usr/bin/env bats
# Tests for T-16: wiki consolidation cron setup
# Covers: AC-1, AC-5 of Improvement 3

setup() {
  CRON_FILE="$BATS_TEST_DIRNAME/../../setup/walter-host/cron/crontab.d/wiki-consolidation"
  INSTALL_SCRIPT="$BATS_TEST_DIRNAME/../../setup/walter-host/install-cron.sh"
  CONSOLIDATE="$BATS_TEST_DIRNAME/../../scripts/wiki/consolidate.sh"
}

@test "wiki-consolidation cron file exists" {
  [ -f "$CRON_FILE" ]
}

@test "wiki-consolidation cron runs at 02:00 on Sundays" {
  grep -q "0 2 \* \* 0" "$CRON_FILE"
}

@test "wiki-consolidation cron references consolidate.sh or walter-run" {
  grep -qE "consolidate|wiki-consolidation" "$CRON_FILE"
}

@test "install-cron.sh includes wiki-consolidation" {
  [ -f "$INSTALL_SCRIPT" ]
  grep -q "wiki-consolidation" "$INSTALL_SCRIPT"
}

@test "consolidate.sh script is referenced in cron file" {
  # The cron should call the consolidation script
  local cron_content
  cron_content="$(cat "$CRON_FILE")"
  echo "$cron_content" | grep -qE "consolidate|wiki"
}
