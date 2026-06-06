#!/usr/bin/env bats
# Static-analysis assertions for the Walter-VM AI stack watchdog.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ALERTING_DIR="$REPO_ROOT/setup/walter-host/services/alerting"
  WATCHDOG="$ALERTING_DIR/ai-stack-watchdog.sh"
  CRON_EXAMPLE="$ALERTING_DIR/cron.example"
}

@test "ai stack watchdog files exist" {
  [[ -f "$WATCHDOG" ]]
  [[ -f "$CRON_EXAMPLE" ]]
}

@test "litellm recovery remains debounced after successful auto-heal" {
  run grep -q 'state_set "litellm_down" 0' "$WATCHDOG"
  [ "$status" -ne 0 ]
  grep -q "Keep litellm_down=1 after a heal" "$WATCHDOG"
}

@test "db saturation restart waits for litellm liveliness before model probes" {
  grep -q "code_after_db_restart" "$WATCHDOG"
  grep -q "skipping model probes" "$WATCHDOG"
}

@test "model probe detects missing LiteLLM master key without router restarts" {
  grep -q "missing_key" "$WATCHDOG"
  grep -q "master key is empty" "$WATCHDOG"
  grep -q "continue" "$WATCHDOG"
}

@test "cron logrotate hint includes the AI watchdog log" {
  grep -q "/var/log/walter-ai-watchdog.log" "$CRON_EXAMPLE"
  grep -q "/var/log/walter-watchdog.log /var/log/walter-ai-watchdog.log /var/log/hetzner-spend.log" "$CRON_EXAMPLE"
}
