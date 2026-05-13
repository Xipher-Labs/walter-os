#!/usr/bin/env bash
# deploy.sh — bring up n8n on Walter-VM.
#
# Idempotent. Safe to re-run. Run via:
#   ssh walter-vm "bash -s" < deploy.sh
# Or copy the entire dir and run on the VM:
#   scp -r setup/walter-host/services/n8n walter-vm:/opt/walter-vm/services/
#   ssh walter-vm "cd /opt/walter-vm/services/n8n && bash deploy.sh"

set -euo pipefail

SVC_DIR="${SVC_DIR:-/opt/walter-vm/services/n8n}"
ENV_FILE="${SVC_DIR}/.env"

cd "$SVC_DIR"

# 1. Generate .env if missing
if [[ ! -f "$ENV_FILE" ]]; then
  echo "→ generating $ENV_FILE with fresh secrets"
  cp .env.template "$ENV_FILE"
  sed -i "s|^N8N_PG_PASS=.*|N8N_PG_PASS=$(openssl rand -hex 24)|" "$ENV_FILE"
  sed -i "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "  ✓ .env generated. Save the encryption key elsewhere too:"
  grep N8N_ENCRYPTION_KEY "$ENV_FILE"
else
  echo "→ $ENV_FILE exists, leaving as is"
fi

# 2. Make sure cloudflared route exists for n8n.${WALTER_DOMAIN}
if command -v cloudflared >/dev/null; then
  if ! cloudflared tunnel route ip list 2>/dev/null | grep -q n8n.${WALTER_DOMAIN}; then
    echo "→ cloudflared route for n8n.${WALTER_DOMAIN} not detected"
    echo "  Add manually to your cloudflared config.yml:"
    echo "    - hostname: n8n.${WALTER_DOMAIN}"
    echo "      service: http://localhost:5678"
    echo "  Then: systemctl restart cloudflared"
  fi
fi

# 3. Pull + up
echo "→ docker compose pull"
docker compose pull

echo "→ docker compose up -d"
docker compose --env-file "$ENV_FILE" up -d

# 4. Wait for healthcheck
echo "→ waiting for n8n to become healthy..."
for i in $(seq 1 30); do
  status=$(docker inspect --format '{{.State.Health.Status}}' n8n 2>/dev/null || echo "unknown")
  if [[ "$status" == "healthy" ]]; then
    echo "  ✓ n8n is healthy"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "  ✗ n8n did not become healthy in 5min. Logs:"
    docker logs --tail 50 n8n
    exit 1
  fi
  sleep 10
done

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "n8n is up: https://n8n.${WALTER_DOMAIN}/"
echo
echo "First-time setup (in browser, after CF Access auth):"
echo "  1. Create owner account (email + password)"
echo "  2. Skip telemetry / personalization"
echo "  3. Add credentials for: Anthropic (via LiteLLM at llm.${WALTER_DOMAIN}),"
echo "     GitHub (PAT), Plane (PAT), Telegram bot (token from BotFather)"
echo
echo "ENCRYPTION KEY backup — copy to Infisical workspace=walter-vm-internal env=prod:"
grep N8N_ENCRYPTION_KEY "$ENV_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
