#!/usr/bin/env bash
# walter-vm-watchdog.sh — Tier 2 alerting (resource health) for Walter-VM.
# Runs every 5 minutes via cron. Pushes to Telegram on threshold crossings
# (transitions only — debounced via state file).
#
# Install:
#   sudo cp walter-vm-watchdog.sh /opt/walter-vm/services/alerting/
#   sudo chmod +x /opt/walter-vm/services/alerting/walter-vm-watchdog.sh
#   crontab -e   # add:
#     */5 * * * * /opt/walter-vm/services/alerting/walter-vm-watchdog.sh >/var/log/walter-watchdog.log 2>&1
#
# Env required (in /etc/walter-vm/alerting.env):
#   WALTER_TELEGRAM_BOT_TOKEN
#   WALTER_TELEGRAM_CHAT_ID

set -euo pipefail

ENV_FILE="${WALTER_ALERTING_ENV:-/etc/walter-vm/alerting.env}"
STATE_FILE="${WALTER_ALERTING_STATE:-/var/run/walter-watchdog.state}"

[[ -f "$ENV_FILE" ]] || { echo "missing env: $ENV_FILE"; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"

[[ -n "${WALTER_TELEGRAM_BOT_TOKEN:-}" && -n "${WALTER_TELEGRAM_CHAT_ID:-}" ]] || {
  echo "WALTER_TELEGRAM_{BOT_TOKEN,CHAT_ID} required"
  exit 2
}

# ---------- helpers ----------
notify() {
  local msg="$1"
  curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$msg" \
    -d "parse_mode=Markdown" >/dev/null
}

# state file maps "metric:level" → 0/1 (alerted)
state_get() {
  [[ -f "$STATE_FILE" ]] || return 1
  grep -E "^${1}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "0"
}
state_set() {
  mkdir -p "$(dirname "$STATE_FILE")"
  touch "$STATE_FILE"
  if grep -qE "^${1}=" "$STATE_FILE"; then
    sed -i "s/^${1}=.*/${1}=${2}/" "$STATE_FILE"
  else
    echo "${1}=${2}" >> "$STATE_FILE"
  fi
}

# transition check: alert when 0→1 (problem starts) or 1→0 (recovered)
check_transition() {
  local key="$1" current="$2" alert_msg="$3" recover_msg="$4"
  local prev
  prev=$(state_get "$key" 2>/dev/null || echo "0")
  if [[ "$current" == "1" && "$prev" == "0" ]]; then
    notify "🚨 *Walter-VM*: $alert_msg"
    state_set "$key" 1
  elif [[ "$current" == "0" && "$prev" == "1" ]]; then
    notify "✅ *Walter-VM*: $recover_msg"
    state_set "$key" 0
  fi
}

# ---------- checks ----------

# Disk root
ROOT_PCT=$(df / --output=pcent | tail -1 | tr -d ' %')
[[ "$ROOT_PCT" -gt 85 ]] && r=1 || r=0
check_transition "disk_root" "$r" \
  "disk \`/\` at ${ROOT_PCT}% used (>85%)" \
  "disk \`/\` recovered, ${ROOT_PCT}% used"

# Disk /mnt/walter-vm-data (the volume)
if [[ -d /mnt/walter-vm-data ]]; then
  DATA_PCT=$(df /mnt/walter-vm-data --output=pcent | tail -1 | tr -d ' %')
  [[ "$DATA_PCT" -gt 85 ]] && r=1 || r=0
  check_transition "disk_data" "$r" \
    "disk \`/mnt/walter-vm-data\` at ${DATA_PCT}% used (>85%)" \
    "disk \`/mnt/walter-vm-data\` recovered, ${DATA_PCT}% used"
fi

# RAM
RAM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
[[ "$RAM_PCT" -gt 90 ]] && r=1 || r=0
check_transition "ram" "$r" \
  "RAM at ${RAM_PCT}% used (>90%)" \
  "RAM recovered, ${RAM_PCT}% used"

# Load average 1m (we have 8 vCPU; alert if > 8.0)
LOAD_1M=$(awk '{print $1}' /proc/loadavg)
LOAD_HIGH=$(awk -v l="$LOAD_1M" 'BEGIN { print (l > 8.0) ? 1 : 0 }')
check_transition "load" "$LOAD_HIGH" \
  "load1m=${LOAD_1M} (>8.0, 8 vCPU pinned)" \
  "load1m back to ${LOAD_1M}"

# Swap
SWAP_TOTAL=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
SWAP_FREE=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
if [[ "$SWAP_TOTAL" -gt 0 ]]; then
  SWAP_PCT=$(awk -v t="$SWAP_TOTAL" -v f="$SWAP_FREE" 'BEGIN { printf "%.0f", (t-f)/t*100 }')
  [[ "$SWAP_PCT" -gt 50 ]] && r=1 || r=0
  check_transition "swap" "$r" \
    "swap at ${SWAP_PCT}% used (>50%) — RAM pressure" \
    "swap recovered, ${SWAP_PCT}% used"
fi

# Docker daemon health
if ! docker info >/dev/null 2>&1; then r=1; else r=0; fi
check_transition "docker" "$r" \
  "Docker daemon is unresponsive" \
  "Docker daemon is back"

# cloudflared health (the tunnel)
if ! systemctl is-active --quiet cloudflared; then r=1; else r=0; fi
check_transition "cloudflared" "$r" \
  "cloudflared is *not active* — tunnel may be down" \
  "cloudflared back to active"

exit 0
