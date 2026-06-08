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

random_hex() {
  local bytes="$1"
  if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl is required to generate n8n bootstrap secrets." >&2
    exit 1
  fi
  openssl rand -hex "$bytes"
}

env_value_present() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key && length($2) > 0 { found=1 } END { exit found ? 0 : 1 }' "$ENV_FILE"
}

upsert_env_key() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "${ENV_FILE}.tmp.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { written=0 }
    $0 ~ "^" key "=" { print key "=" value; written=1; next }
    { print }
    END { if (!written) print key "=" value }
  ' "$ENV_FILE" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
}

ensure_env_key() {
  local key="$1" value="$2"
  if env_value_present "$key"; then
    echo "  ✓ $key already set"
    return 0
  fi
  upsert_env_key "$key" "$value"
  echo "  ✓ $key generated"
}

# 1. Generate/complete .env with all secrets required by compose.yml.
if [[ ! -f "$ENV_FILE" ]]; then
  echo "→ generating $ENV_FILE with fresh secrets"
  cp .env.template "$ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  echo "→ $ENV_FILE exists, completing any missing required keys"
fi

ensure_env_key "N8N_PG_PASS" "${N8N_PG_PASS:-$(random_hex 24)}"
ensure_env_key "N8N_ENCRYPTION_KEY" "${N8N_ENCRYPTION_KEY:-$(random_hex 32)}"
ensure_env_key "N8N_BASIC_AUTH_USER" "${N8N_BASIC_AUTH_USER:-walter-admin}"
ensure_env_key "N8N_BASIC_AUTH_PASSWORD" "${N8N_BASIC_AUTH_PASSWORD:-$(random_hex 24)}"

echo "  ✓ .env ready (0600). Back up N8N_ENCRYPTION_KEY and n8n basic-auth credentials to your secrets manager."

if [[ "${N8N_DEPLOY_ENV_ONLY:-0}" == "1" ]]; then
  echo "→ N8N_DEPLOY_ENV_ONLY=1 set; stopping before docker/cloudflared work."
  exit 0
fi

# 2. Make sure cloudflared route exists for n8n.${WALTER_DOMAIN}
if command -v cloudflared >/dev/null; then
  if ! cloudflared tunnel route ip list 2>/dev/null | grep -q "n8n.${WALTER_DOMAIN}"; then
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
echo
echo "Basic-auth credentials were written to $ENV_FILE; copy them to your password manager / Infisical."
grep N8N_BASIC_AUTH_USER "$ENV_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
