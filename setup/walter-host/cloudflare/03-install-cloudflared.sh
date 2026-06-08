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
CLOUDFLARED_METRICS_ADDR="${CLOUDFLARED_METRICS_ADDR:-127.0.0.1:49312}"
cloudflared_was_active=0
if systemctl is-active --quiet cloudflared 2>/dev/null; then
  cloudflared_was_active=1
fi

cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=cloudflared
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=0
Type=notify
ExecStart=/usr/bin/cloudflared --config /etc/cloudflared/config.yml --no-autoupdate --metrics "${CLOUDFLARED_METRICS_ADDR}" --ha-connections 4 tunnel run
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/walter-vm
touch /etc/walter-vm/alerting.env
chown root:root /etc/walter-vm/alerting.env
chmod 0600 /etc/walter-vm/alerting.env
CLOUDFLARED_METRICS="${CLOUDFLARED_METRICS_ADDR}"
if grep -q "^CLOUDFLARED_METRICS=" /etc/walter-vm/alerting.env; then
  sed -i "s|^CLOUDFLARED_METRICS=.*|CLOUDFLARED_METRICS=\"${CLOUDFLARED_METRICS}\"|" /etc/walter-vm/alerting.env
else
  printf "\nCLOUDFLARED_METRICS=\"%s\"\n" "${CLOUDFLARED_METRICS}" >> /etc/walter-vm/alerting.env
fi

cat > /usr/local/sbin/walter-cloudflared-ready-check <<EOF
#!/usr/bin/env bash
set -euo pipefail
CLOUDFLARED_METRICS_ADDR="${CLOUDFLARED_METRICS_ADDR}"
if ! systemctl is-active --quiet cloudflared; then
  exit 0
fi
if ready_code=\$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://\${CLOUDFLARED_METRICS_ADDR}/ready" 2>/dev/null); then
  :
else
  ready_code=000
fi
case "\${ready_code}" in
  200) exit 0 ;;
  000)
    logger -t walter-cloudflared-ready-check "cloudflared /ready unreachable; leaving service running"
    exit 0
    ;;
  *)
    logger -t walter-cloudflared-ready-check "cloudflared /ready returned HTTP \${ready_code}; restarting cloudflared"
    systemctl restart cloudflared
    exit 0
    ;;
esac
EOF
chmod 0755 /usr/local/sbin/walter-cloudflared-ready-check

cat > /etc/systemd/system/walter-cloudflared-ready-check.service <<EOF
[Unit]
Description=Walter cloudflared /ready restart guard
After=cloudflared.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/walter-cloudflared-ready-check
EOF

cat > /etc/systemd/system/walter-cloudflared-ready-check.timer <<EOF
[Unit]
Description=Run Walter cloudflared /ready restart guard

[Timer]
OnBootSec=60s
OnUnitActiveSec=60s
AccuracySec=10s
Unit=walter-cloudflared-ready-check.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable cloudflared
if [ "${cloudflared_was_active}" -eq 1 ]; then
  systemctl restart cloudflared
else
  systemctl start cloudflared
fi
systemctl enable --now walter-cloudflared-ready-check.timer
sleep 3
echo "--- service state ---"
systemctl is-active cloudflared
echo "--- ready endpoint ---"
curl -fsS --max-time 5 "http://${CLOUDFLARED_METRICS_ADDR}/ready" || true
echo "--- recent logs ---"
journalctl -u cloudflared -n 10 --no-pager
'
echo
echo "==> Done. cloudflared running on VM."
echo "==> Test (after zone is active and Access app configured):"
echo "    curl -I https://vault.${WALTER_DOMAIN:-example.com}"
