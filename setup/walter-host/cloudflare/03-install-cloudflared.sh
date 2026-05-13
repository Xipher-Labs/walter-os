#!/usr/bin/env bash
# 03-install-cloudflared.sh — install cloudflared on the VM as systemd service.
#
# Args: $1 = vm host (e.g. root@1.2.3.4 or walter@walter-vm.${WALTER_DOMAIN} after lockdown)
#
# Requires: /tmp/walter-cf/credentials.json + /tmp/walter-cf/config.yml
# (output from 02-create-tunnel.sh)

set -euo pipefail

VM="${1:?usage: $0 <vm-host>  (e.g. root@46.62.131.179)}"

if [[ ! -f /tmp/walter-cf/credentials.json ]] || [[ ! -f /tmp/walter-cf/config.yml ]]; then
  echo "ERROR: run 02-create-tunnel.sh first (need credentials.json + config.yml in /tmp/walter-cf/)"
  exit 1
fi

echo "==> Upload credentials + config to $VM..."
scp /tmp/walter-cf/credentials.json /tmp/walter-cf/config.yml "$VM":/tmp/

echo "==> Install cloudflared on VM + register systemd service..."
ssh "$VM" 'set -e
if ! command -v cloudflared >/dev/null 2>&1; then
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cloudflared
fi
echo "cloudflared: $(cloudflared --version 2>&1 | head -1)"

mkdir -p /etc/cloudflared
mv -f /tmp/credentials.json /etc/cloudflared/credentials.json
mv -f /tmp/config.yml /etc/cloudflared/config.yml
chmod 600 /etc/cloudflared/credentials.json
chmod 644 /etc/cloudflared/config.yml
chown -R root:root /etc/cloudflared

cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=cloudflared
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=0
Type=notify
ExecStart=/usr/bin/cloudflared --config /etc/cloudflared/config.yml --no-autoupdate tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudflared
sleep 3
echo "--- service state ---"
systemctl is-active cloudflared
echo "--- recent logs ---"
journalctl -u cloudflared -n 10 --no-pager
'
echo
echo "==> Done. cloudflared running on VM."
echo "==> Test (after zone is active and Access app configured):"
echo "    curl -I https://vault.${WALTER_DOMAIN:-example.com}"
