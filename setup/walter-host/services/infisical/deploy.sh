#!/usr/bin/env bash
# deploy.sh — deploy Infisical on Walter-VM.
#
# Idempotent. First run: creates DB, runs 122 migrations, generates KMS root key.
# Subsequent runs: just updates containers + restarts.
#
# Usage:
#   ssh root@<vm-ip> "bash" < setup/walter-host/services/infisical/deploy.sh
#   OR (preferred — operator on Mac):
#   bash setup/walter-host/services/infisical/deploy.sh root@<vm-ip>

set -euo pipefail

VM="${1:-}"
SERVICE_DIR="/opt/walter-vm/services/infisical"

# If VM arg present, run remote
if [[ -n "$VM" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "==> Upload compose + secrets to $VM..."
  ssh "$VM" "mkdir -p $SERVICE_DIR && chown -R walter:walter /opt/walter-vm"
  scp "$SCRIPT_DIR/compose.yml" "$VM":$SERVICE_DIR/compose.yml

  if [[ -f "$HOME/.config/walter-os/secrets.env" ]]; then
    source "$HOME/.config/walter-os/secrets.env"
    : "${INFISICAL_ENCRYPTION_KEY:?missing — add to ~/.config/walter-os/secrets.env}"
    : "${INFISICAL_AUTH_SECRET:?}"
    : "${INFISICAL_DB_PASS:?}"
    : "${INFISICAL_REDIS_PASS:?}"

    cat > /tmp/infisical-deploy.env <<ENVEOF
INFISICAL_ENCRYPTION_KEY=$INFISICAL_ENCRYPTION_KEY
INFISICAL_AUTH_SECRET=$INFISICAL_AUTH_SECRET
INFISICAL_DB_PASS=$INFISICAL_DB_PASS
INFISICAL_REDIS_PASS=$INFISICAL_REDIS_PASS
ENVEOF
    scp /tmp/infisical-deploy.env "$VM":$SERVICE_DIR/.env
    rm -f /tmp/infisical-deploy.env
  else
    echo "ERROR: ~/.config/walter-os/secrets.env not found"
    exit 1
  fi

  echo "==> Run docker compose on VM..."
  ssh "$VM" "cd $SERVICE_DIR && chmod 600 .env && docker compose pull && docker compose up -d"

  echo "==> Wait for backend ready..."
  for i in 1 2 3 4 5 6; do
    sleep 10
    code=$(ssh "$VM" "curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8800/api/status" 2>&1)
    echo "  attempt $i: HTTP $code"
    [[ "$code" == "200" ]] && break
  done

  echo "==> Done."
  echo "==> First-run admin signup: open https://secrets.${WALTER_DOMAIN}/admin/signup"
  echo "==> (CF Access policy must be active — only @${WALTER_DOMAIN} can pass)"
  exit 0
fi

# Run locally on VM
cd "$SERVICE_DIR"
docker compose pull
docker compose up -d
