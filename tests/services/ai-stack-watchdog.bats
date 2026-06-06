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

@test "ai stack watchdog uses a non-blocking singleton lock" {
  grep -q 'LOCK_FILE="${WALTER_AI_WATCHDOG_LOCK:-/var/run/walter-ai-watchdog.lock}"' "$WATCHDOG"
  grep -q 'exec 9>"$LOCK_FILE"' "$WATCHDOG"
  grep -q "flock -n 9" "$WATCHDOG"
  grep -q "already running; exiting" "$WATCHDOG"
}

@test "telegram notification failures are visible in cron logs" {
  grep -q "Telegram notification failed" "$WATCHDOG"
  grep -q "return 1" "$WATCHDOG"
  run awk '
    /^notify\(\) \{/ { in_notify=1 }
    in_notify && /[>][/]dev[/]null [|][|] true/ { found=1 }
    in_notify && /^\}/ { in_notify=0 }
    END { exit !found }
  ' "$WATCHDOG"
  [ "$status" -ne 0 ]
}

@test "telegram notification calls are bounded by connect and total timeouts" {
  grep -q 'TELEGRAM_CONNECT_TIMEOUT="${WALTER_TELEGRAM_CONNECT_TIMEOUT:-5}"' "$WATCHDOG"
  grep -q 'TELEGRAM_MAX_TIME="${WALTER_TELEGRAM_MAX_TIME:-15}"' "$WATCHDOG"
  grep -q -- '--connect-timeout "$TELEGRAM_CONNECT_TIMEOUT"' "$WATCHDOG"
  grep -q -- '--max-time "$TELEGRAM_MAX_TIME"' "$WATCHDOG"
}

@test "debounce state advances only after successful notification" {
  grep -q 'next_state=1' "$WATCHDOG"
  grep -q 'next_state=0' "$WATCHDOG"
  grep -q 'notify "$message" && state_set "$key" "$next_state"' "$WATCHDOG"
}

@test "notification failure does not abort the watchdog cycle" {
  run awk '
    /^transition\(\) \{/ { in_transition=1 }
    in_transition && /notify "\$message" && state_set "\$key" "\$next_state"/ { saw_transition=1 }
    in_transition && /return 0/ { saw_return=1 }
    in_transition && /^\}/ { in_transition=0 }
    END { exit !(saw_transition && saw_return) }
  ' "$WATCHDOG"
  [ "$status" -eq 0 ]
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

@test "db saturation threshold is validated before integer comparison" {
  grep -q "configure_db_sat_pct" "$WATCHDOG"
  grep -q "invalid LITELLM_DB_SAT_PCT" "$WATCHDOG"
  grep -q "DB_SAT_PCT=85" "$WATCHDOG"
}

@test "db saturation psql probes are bounded" {
  grep -q 'timeout 10s docker exec litellm-db psql .*pg_stat_activity' "$WATCHDOG"
  grep -q 'timeout 10s docker exec litellm-db psql .*max_connections' "$WATCHDOG"
}

@test "cloudflared log fallback evaluates the last relevant event" {
  grep -q "last_event=" "$WATCHDOG"
  grep -q "tail -n 1" "$WATCHDOG"
  run grep -q "local bad good" "$WATCHDOG"
  [ "$status" -ne 0 ]
}

@test "cloudflared metrics readiness is authoritative when reachable" {
  grep -q "ready_payload=" "$WATCHDOG"
  grep -q 'printf .*ready_payload.*readyConnections' "$WATCHDOG"
  grep -q "return 1" "$WATCHDOG"
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

@test "model probe docker exec is bounded" {
  grep -q 'MODEL_EXEC_TIMEOUT="${LITELLM_MODEL_EXEC_TIMEOUT:-70s}"' "$WATCHDOG"
  grep -q 'timeout "$MODEL_EXEC_TIMEOUT" docker exec -e M="$model"' "$WATCHDOG"
}

@test "model probe timeout is parsed defensively" {
  grep -q 'timeout=int(os.environ.get("T","50"))' "$WATCHDOG"
  grep -q "timeout=50" "$WATCHDOG"
  run grep -q 'timeout=int(os.environ\["T"\])' "$WATCHDOG"
  [ "$status" -ne 0 ]
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
