#!/usr/bin/env bash
# walter vm <connect|status|snapshot>
set -euo pipefail
[[ -f "$HOME/.config/walter-os/secrets.env" ]] && source "$HOME/.config/walter-os/secrets.env"
sub="${1:-status}"

case "$sub" in
  connect|ssh)
    exec ssh walter-vm
    ;;
  status)
    if command -v hcloud >/dev/null; then
      hcloud server describe walter-os | head -20
    else
      ssh walter-vm 'uptime; df -h / /mnt/walter-vm-data; free -m | head -2'
    fi
    ;;
  snapshot)
    desc="${2:-manual-$(date +%F-%H%M)}"
    hcloud server create-image walter-os --type snapshot --description "$desc"
    ;;
  *)
    echo "Usage: walter vm <connect|status|snapshot> [snapshot-description]"; exit 2 ;;
esac
