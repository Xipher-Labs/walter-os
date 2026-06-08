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

trim_whitespace() {
  local value="$1"
  case "$value" in
    *$'\n'*|*$'\r'*)
      printf '%s\n' "$value"
      return 0
      ;;
  esac
  printf '%s\n' "$value" | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }'
}

env_or_default() {
  local name="$1" default="$2" value trimmed
  if [[ -z "${!name+x}" ]]; then
    printf '%s\n' "$default"
    return 0
  fi
  value="${!name}"
  trimmed="$(trim_whitespace "$value")"
  if [[ -z "$trimmed" ]]; then
    printf '%s\n' "$default"
    return 0
  fi
  printf '%s\n' "$trimmed"
}

env_value_present() {
  local key="$1"
  awk -v key="$key" '
    index($0, "=") > 0 && substr($0, 1, index($0, "=") - 1) == key {
      last = substr($0, index($0, "=") + 1)
    }
    END {
      if (last == "") exit 1
      value = last
      if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
          (substr(value, 1, 1) == "'"'"'" && substr(value, length(value), 1) == "'"'"'")) {
        value = substr(value, 2, length(value) - 2)
      }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      exit length(value) > 0 ? 0 : 1
    }
  ' "$ENV_FILE"
}

upsert_env_key() {
  local key="$1" value="$2" tmp
  case "$value" in
    *$'\n'*|*$'\r'*)
      echo "ERROR: $key must be a single-line value." >&2
      return 1
      ;;
  esac
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
  local key="$1" value_spec="$2" value
  if env_value_present "$key"; then
    echo "  ✓ $key already set"
    return 0
  fi
  case "$value_spec" in
    hex:*) value="$(random_hex "${value_spec#hex:}")" ;;
    *) value="$value_spec" ;;
  esac
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
chmod 600 "$ENV_FILE"

ensure_env_key "N8N_PG_PASS" "$(env_or_default "N8N_PG_PASS" "hex:24")"
ensure_env_key "N8N_ENCRYPTION_KEY" "$(env_or_default "N8N_ENCRYPTION_KEY" "hex:32")"
ensure_env_key "N8N_BASIC_AUTH_USER" "$(env_or_default "N8N_BASIC_AUTH_USER" "walter-admin")"
ensure_env_key "N8N_BASIC_AUTH_PASSWORD" "$(env_or_default "N8N_BASIC_AUTH_PASSWORD" "hex:24")"

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
echo "ENCRYPTION KEY backup — copy N8N_ENCRYPTION_KEY from $ENV_FILE to Infisical workspace=walter-vm-internal env=prod."
echo
echo "Basic-auth credentials were written to $ENV_FILE; copy N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD to your password manager / Infisical."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
