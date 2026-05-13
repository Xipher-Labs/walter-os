#!/usr/bin/env bash
# deploy.sh — bring up wg-easy + open UDP/51820 in firewall.
set -euo pipefail

SVC_DIR="${SVC_DIR:-/opt/walter-vm/services/wireguard}"
ENV_FILE="$SVC_DIR/.env"

cd "$SVC_DIR"

# 1. Generate password hash if not set
if [[ ! -f "$ENV_FILE" ]] || ! grep -q "^WG_PASSWORD_HASH=." "$ENV_FILE"; then
  PASS=$(openssl rand -hex 16)
  echo
  echo "===================================="
  echo "wg-easy admin password: $PASS"
  echo "Save this NOW (also being pushed to Infisical)."
  echo "===================================="
  echo
  HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:14 wgpw "$PASS" 2>&1 | grep PASSWORD_HASH | cut -d= -f2 | tr -d "'\"")
  cp .env.template .env
  sed -i "s|^WG_PASSWORD_HASH=.*|WG_PASSWORD_HASH='$HASH'|" .env
  chmod 600 .env
fi

# 2. Open firewall
sudo ufw allow 51820/udp comment "WireGuard"

# 3. Bring up
sudo docker compose --env-file .env up -d

# 4. Wait healthy
echo "→ waiting for wg-easy..."
for i in $(seq 1 20); do
  status=$(sudo docker inspect --format '{{.State.Health.Status}}' wg-easy 2>/dev/null || echo unknown)
  [[ "$status" == "healthy" ]] && break
  sleep 5
done
[[ "$status" != "healthy" ]] && { echo "✗ wg-easy not healthy"; sudo docker logs --tail 30 wg-easy; exit 1; }

cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WireGuard VPN up.

Web UI:    https://vpn.${WALTER_DOMAIN}   (CF Access → @${WALTER_DOMAIN})
Public:    UDP/51820 on this VM's IPv4

To add a client:
  1. Open the web UI → New Client → name it (e.g. "macbook-pro")
  2. Download .conf OR scan QR (phone)
  3. Import into WireGuard app
  4. Connect — all traffic now tunnels via Walter-VM

Each client gets its own IP in 10.8.0.0/24. Revoke instantly via UI.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
