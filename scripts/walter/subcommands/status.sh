#!/usr/bin/env bash
# walter status — Walter-VM service health snapshot

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
# shellcheck source=/dev/null
source "$WALTER_OS_HOME/scripts/walter/lib/log.sh"
[[ -f "$HOME/.config/walter-os/secrets.env" ]] && source "$HOME/.config/walter-os/secrets.env"
: "${WALTER_DOMAIN:?WALTER_DOMAIN not set — copy .env.example to .env.local and configure}"

log_step "Walter-VM status"

if ! command -v ssh >/dev/null; then
  log_err "ssh required"; exit 2
fi

# Fast SSH check
if ! ssh -o ConnectTimeout=5 walter-vm 'true' 2>/dev/null; then
  log_err "Cannot reach walter-vm via ssh (CF Access expired? Run: cloudflared access login ssh.${WALTER_DOMAIN})"
  exit 1
fi

# Resource snapshot
ssh walter-vm '
echo "uptime:    $(uptime -p)"
echo "load:      $(awk "{print \$1, \$2, \$3}" /proc/loadavg)"
echo "ram:       $(free -m | awk "/^Mem:/ {printf \"%d / %d MiB used (%.0f%%)\n\", \$3, \$2, \$3/\$2*100}")"
echo "disk-/:    $(df -h / | awk "NR==2 {print \$3 \" / \" \$2 \" (\" \$5 \")\"}")"
echo "disk-vol:  $(df -h /mnt/walter-vm-data | awk "NR==2 {print \$3 \" / \" \$2 \" (\" \$5 \")\"}")"
echo
echo "containers (sorted by CPU):"
sudo docker ps --format "{{.Names}}|{{.Status}}" | sort
' 2>/dev/null

echo
log_step "Recent backups"
ssh walter-vm 'ls -t /var/log/walter-vm-restic/*.log 2>/dev/null | head -1 | xargs -I {} sh -c "tail -1 {} 2>/dev/null"' || true

echo
log_step "Hetzner spend (latest cron run)"
ssh walter-vm 'tail -8 /var/log/hetzner-spend.log 2>/dev/null | grep -E "TOTAL|servers|volumes" | head -3' 2>/dev/null || log_dim "(no spend log yet)"
