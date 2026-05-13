#!/usr/bin/env bash
# deploy.sh — bring up Syncthing on Walter-VM as always-on hub.
#
# Usage on the VM:
#   sudo bash /opt/walter-vm/services/syncthing/deploy.sh

set -euo pipefail

SVC_DIR="${SVC_DIR:-/opt/walter-vm/services/syncthing}"
SYNC_DIR="/mnt/walter-vm-data/sync"

cd "$SVC_DIR"

# 1. Ensure sync folders exist on the volume
sudo install -d -m 755 -o walter -g walter \
  "$SYNC_DIR" \
  "$SYNC_DIR/obsidian-vault" \
  "$SYNC_DIR/projects-personal" \
  "$SYNC_DIR/personal" \
  "$SYNC_DIR/screenshots"

# 2. Open firewall for sync port (22000)
if command -v ufw >/dev/null 2>&1; then
  if ! sudo ufw status | grep -q "22000"; then
    sudo ufw allow 22000/tcp comment "Syncthing TCP"
    sudo ufw allow 22000/udp comment "Syncthing UDP/QUIC"
  fi
fi

# 3. Bring up
sudo docker compose up -d

# 4. Wait for healthy
echo "→ waiting for Syncthing to be healthy..."
for i in $(seq 1 20); do
  status=$(sudo docker inspect --format '{{.State.Health.Status}}' syncthing 2>/dev/null || echo "unknown")
  [[ "$status" == "healthy" ]] && break
  sleep 5
done
[[ "$status" != "healthy" ]] && { echo "✗ syncthing not healthy"; sudo docker logs --tail 30 syncthing; exit 1; }

# 5. Print device ID for operator
DEVICE_ID=$(sudo docker exec syncthing syncthing --device-id 2>/dev/null | tr -d '[:space:]')
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Syncthing hub is up: https://sync.${WALTER_DOMAIN}/"
echo
echo "Hub device ID (paste this on each peer to add hub as a device):"
echo "  $DEVICE_ID"
echo
echo "Next steps (from the hub web UI):"
echo "  1. Set GUI Authentication User+Pass (Settings → GUI)"
echo "     → critical: CF Access already protects, but defense-in-depth"
echo "  2. Add folders pointing at /sync/{obsidian-vault,projects-personal,personal,screenshots}"
echo "     using the existing folder paths"
echo "  3. On each peer device (Mac, phone, etc.), add this hub as a remote device"
echo "     using the ID printed above. Mark folders as 'Receive Encrypted' if device"
echo "     is mobile (so phone never has plaintext of vault)."
echo "  4. On Mac: install Syncthing via Homebrew → set hub device ID + folders."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
