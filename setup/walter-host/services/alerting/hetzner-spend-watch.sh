#!/usr/bin/env bash
# hetzner-spend-watch.sh — Tier 4 alerting (cloud spend trend).
# Runs daily at 09:00 via cron on Walter-VM.
# Uses hcloud CLI to enumerate running resources, sums monthly cost,
# pings Telegram on threshold cross OR daily summary.
#
# Install:
#   sudo cp hetzner-spend-watch.sh /opt/walter-vm/services/alerting/
#   crontab -e   # add:
#     0 9 * * * /opt/walter-vm/services/alerting/hetzner-spend-watch.sh
#
# Env required (in /etc/walter-vm/alerting.env):
#   WALTER_TELEGRAM_BOT_TOKEN, WALTER_TELEGRAM_CHAT_ID
#   HCLOUD_TOKEN  (read-only token preferred)

set -euo pipefail

ENV_FILE="${WALTER_ALERTING_ENV:-/etc/walter-vm/alerting.env}"
STATE_DIR="${WALTER_ALERTING_STATE_DIR:-/var/lib/walter-alerting}"
THRESHOLD_DELTA_PCT=10        # alert when delta-vs-yesterday > 10%
THRESHOLD_ABS_EUR=100         # alert when projected monthly > €100

[[ -f "$ENV_FILE" ]] || { echo "missing env: $ENV_FILE"; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"

mkdir -p "$STATE_DIR"
LAST_FILE="$STATE_DIR/last-spend.txt"

# ---------- compute ----------
SERVERS=$(hcloud server list -o json)
VOLUMES=$(hcloud volume list -o json)
SNAPS=$(hcloud image list --type snapshot -o json 2>/dev/null || echo '[]')
FLOATS=$(hcloud floating-ip list -o json 2>/dev/null || echo '[]')
LBS=$(hcloud load-balancer list -o json 2>/dev/null || echo '[]')

# Sum monthly server cost
server_total=$(echo "$SERVERS" | jq '[.[] | .server_type as $t | (
  ([.datacenter.server_types.supported[]? | select(. == $t.id)] | length) * 0
)] | length' 2>/dev/null || echo 0)

# More direct: hcloud server list -o columns=name,type, then look up price per type
servers_lines=$(hcloud server list -o noheader -o columns=name,type 2>/dev/null || echo "")
server_eur=0
while IFS=$'\t' read -r name stype; do
  [[ -z "$name" ]] && continue
  price=$(hcloud server-type describe "$stype" -o json 2>/dev/null | jq -r '.prices[0].price_monthly.gross | tonumber' 2>/dev/null || echo "0")
  server_eur=$(awk -v a="$server_eur" -v b="$price" 'BEGIN { printf "%.2f", a+b }')
done < <(echo "$servers_lines" | sed 's/  */\t/g')

# Volumes: €0.0476/GB/mo
volume_eur=$(echo "$VOLUMES" | jq '[.[] | .size] | add // 0' | awk '{ printf "%.2f", $1 * 0.0476 }')

# Floating IPs: €1/mo each (IPv4); IPv6 free if attached
float_count=$(echo "$FLOATS" | jq 'length')
float_eur=$(awk -v n="$float_count" 'BEGIN { printf "%.2f", n * 1 }')

# Load balancers: depends on type, conservative estimate
lb_count=$(echo "$LBS" | jq 'length')
lb_eur=$(awk -v n="$lb_count" 'BEGIN { printf "%.2f", n * 4.90 }')   # lb11 = €4.90/mo

# Snapshots: ~€0.0119/GB/mo per Hetzner pricing as of 2026
snap_eur=$(echo "$SNAPS" | jq '[.[] | .disk_size] | add // 0' | awk '{ printf "%.2f", $1 * 0.0119 }')

total_eur=$(awk -v a="$server_eur" -v b="$volume_eur" -v c="$float_eur" -v d="$lb_eur" -v e="$snap_eur" \
  'BEGIN { printf "%.2f", a+b+c+d+e }')

# ---------- delta ----------
prev_total=0
if [[ -f "$LAST_FILE" ]]; then
  prev_total=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
fi
delta_pct=0
if (( $(awk -v p="$prev_total" 'BEGIN { print (p > 0) }') )); then
  delta_pct=$(awk -v t="$total_eur" -v p="$prev_total" 'BEGIN { printf "%.1f", (t-p)/p*100 }')
fi

# ---------- compose message ----------
TODAY=$(date +%Y-%m-%d)
msg="*Hetzner spend* — ${TODAY}
\`\`\`
Servers (${server_total:-?}):     €${server_eur}/mo
Volumes:               €${volume_eur}/mo
Floating IPs (${float_count}):    €${float_eur}/mo
Load balancers (${lb_count}):  €${lb_eur}/mo
Snapshots:             €${snap_eur}/mo
─────────────────────────────────────
TOTAL                  €${total_eur}/mo
\`\`\`"
if (( $(awk -v p="$prev_total" 'BEGIN { print (p > 0) }') )); then
  msg+=$'\n'"Δ vs yesterday: ${delta_pct}%"
fi

# ---------- send ----------
should_alert=0
if (( $(awk -v t="$total_eur" -v th="$THRESHOLD_ABS_EUR" 'BEGIN { print (t > th) }') )); then
  msg=$'🚨 *budget threshold crossed* (>€'"$THRESHOLD_ABS_EUR"$')\n'"$msg"
  should_alert=1
fi
if (( $(awk -v d="$delta_pct" -v th="$THRESHOLD_DELTA_PCT" 'BEGIN { print (d > th) }') )); then
  msg=$'📈 *spend up >'"$THRESHOLD_DELTA_PCT"$'% vs yesterday*\n'"$msg"
  should_alert=1
fi

# Always send daily summary at 09:00 (the cron schedule), even if normal,
# so you know the script is alive and you have spend visibility.
curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=$msg" \
  -d "parse_mode=Markdown" >/dev/null

# Persist for tomorrow's delta
echo "$total_eur" > "$LAST_FILE"
exit 0
