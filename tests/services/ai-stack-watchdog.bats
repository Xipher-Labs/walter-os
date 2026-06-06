#!/usr/bin/env bats
# Static-analysis assertions for the Walter-VM AI stack watchdog.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ALERTING_DIR="$REPO_ROOT/setup/walter-host/services/alerting"
  WATCHDOG="$ALERTING_DIR/ai-stack-watchdog.sh"
  CRON_EXAMPLE="$ALERTING_DIR/cron.example"
  CLOUDFLARED_DROPIN="$REPO_ROOT/setup/walter-host/services/cloudflared/restart-hardening.conf"
}

@test "ai stack watchdog files exist" {
  [[ -f "$WATCHDOG" ]]
  [[ -f "$CRON_EXAMPLE" ]]
}

@test "ai stack watchdog fails fast on unexpected shell errors" {
  grep -q "set -euo pipefail" "$WATCHDOG"
}

@test "telegram notification failures are visible in cron logs" {
  grep -q "Telegram notification failed" "$WATCHDOG"
  grep -q "return 1" "$WATCHDOG"
  run grep -q '>/dev/null || true' "$WATCHDOG"
  [ "$status" -ne 0 ]
}

@test "telegram notification calls are bounded by connect and total timeouts" {
  grep -q 'TELEGRAM_CONNECT_TIMEOUT="${WALTER_TELEGRAM_CONNECT_TIMEOUT:-5}"' "$WATCHDOG"
  grep -q 'TELEGRAM_MAX_TIME="${WALTER_TELEGRAM_MAX_TIME:-15}"' "$WATCHDOG"
  grep -q -- '--connect-timeout "$TELEGRAM_CONNECT_TIMEOUT"' "$WATCHDOG"
  grep -q -- '--max-time "$TELEGRAM_MAX_TIME"' "$WATCHDOG"
}

@test "debounce state advances only after successful notification" {
  grep -q 'notify ".*" && state_set "$key" 1' "$WATCHDOG"
  grep -q 'notify ".*" && state_set "$key" 0' "$WATCHDOG"
}

@test "install docs use root crontab for docker and root log paths" {
  grep -q "sudo crontab -e" "$WATCHDOG"
  grep -q "root crontab" "$CRON_EXAMPLE"
  grep -q "sudo crontab -e" "$CRON_EXAMPLE"
  grep -q "installed in root cron because it calls docker and journalctl" "$WATCHDOG"
  run grep -q "or as walter" "$WATCHDOG"
  [ "$status" -ne 0 ]
}

@test "litellm recovery remains debounced after successful auto-heal" {
  run grep -q 'state_set "litellm_down" 0' "$WATCHDOG"
  [ "$status" -ne 0 ]
  grep -q "Keep litellm_down=1 after a heal" "$WATCHDOG"
}

@test "cloudflared recovery remains debounced after successful auto-heal" {
  run grep -q 'state_set "cloudflared_down" 0' "$WATCHDOG"
  [ "$status" -ne 0 ]
  grep -q "Keep cloudflared_down=1 after a heal" "$WATCHDOG"
}

@test "db saturation restart waits for litellm liveliness before model probes" {
  grep -q "code_after_db_restart" "$WATCHDOG"
  grep -q "skipping model probes" "$WATCHDOG"
}

@test "model probe detects missing LiteLLM master key without router restarts" {
  grep -q "missing_key" "$WATCHDOG"
  grep -q "master key is empty" "$WATCHDOG"
  grep -q "LITELLM_MASTER_KEY.*LiteLLM service environment" "$WATCHDOG"
  grep -q "litellm_master_key_missing" "$WATCHDOG"
  run grep -q '[$][{]key[}]_auth' "$WATCHDOG"
  [ "$status" -ne 0 ]
  run grep -q 'fix `/run/secrets/litellm.env`' "$WATCHDOG"
  [ "$status" -ne 0 ]
  grep -q "continue" "$WATCHDOG"
}

@test "model router restart debouncing is independent from alert delivery" {
  grep -q 'restart_key="${key}_restart"' "$WATCHDOG"
  grep -q 'prev_restart_state=$(state_get "$restart_key")' "$WATCHDOG"
  grep -q 'if \[\[ "$prev_restart_state" == "0" \]\]; then' "$WATCHDOG"
  grep -q 'state_set "$restart_key" 1' "$WATCHDOG"
  grep -q 'state_set "$restart_key" 0' "$WATCHDOG"
  run grep -q 'prev_model_state=$(state_get "$key")' "$WATCHDOG"
  [ "$status" -ne 0 ]
}

@test "cron logrotate hint includes the AI watchdog log" {
  grep -q "/var/log/walter-ai-watchdog.log" "$CRON_EXAMPLE"
  grep -q "/var/log/walter-watchdog.log /var/log/walter-ai-watchdog.log /var/log/hetzner-spend.log" "$CRON_EXAMPLE"
}

@test "cloudflared start-limit hardening uses the systemd Unit section" {
  awk '
    /^\[Unit\]$/ { section="Unit"; next }
    /^\[Service\]$/ { section="Service"; next }
    /^StartLimitIntervalSec=0$/ && section == "Unit" { found_unit=1 }
    /^StartLimitIntervalSec=/ && section == "Service" { found_service=1 }
    END { exit !(found_unit && !found_service) }
  ' "$CLOUDFLARED_DROPIN"
}

@test "cloudflared hardening drop-in does not claim to enable metrics" {
  grep -q "This drop-in does not add --metrics" "$CLOUDFLARED_DROPIN"
  run grep -q "Also expose the metrics endpoint" "$CLOUDFLARED_DROPIN"
  [ "$status" -ne 0 ]
}
