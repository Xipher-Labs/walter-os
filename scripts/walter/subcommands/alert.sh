#!/usr/bin/env bash
# walter alert test  — sends a test message to the Walter Telegram bot
# walter alert mute <duration>  — pauses Tier 2-4 alerts for duration (e.g. 1h, 30m)
set -euo pipefail
[[ -f "$HOME/.config/walter-os/secrets.env" ]] && source "$HOME/.config/walter-os/secrets.env"

sub="${1:-test}"

case "$sub" in
  test)
    : "${WALTER_TELEGRAM_BOT_TOKEN:?missing}"
    : "${WALTER_TELEGRAM_CHAT_ID:?missing}"
    msg="🧪 *walter alert test* — $(date +%FT%T) from $(hostname)"
    curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=$msg" \
      -d "parse_mode=Markdown" | jq -r '{ok, msg_id: .result.message_id}'
    ;;
  mute)
    dur="${2:-1h}"
    ssh walter-vm "sudo touch /var/run/walter-watchdog.muted; date -d 'now + $dur' +%s | sudo tee /var/run/walter-watchdog.mute-until >/dev/null"
    echo "✓ Walter watchdog muted until +$dur"
    ;;
  *)
    echo "Usage: walter alert <test|mute> [duration]"; exit 2 ;;
esac
