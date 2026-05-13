#!/usr/bin/env bash
# deploy.sh — bring up OpenClaw on Walter-VM.
#
# Idempotent. Safe to re-run. Patterns from setup/walter-host/services/n8n/deploy.sh.
#
# Secrets architecture: the current public compose reads required values from
# `.env` or exported environment variables. The Infisical sidecar migration is
# documented separately and should not be assumed by this deploy helper until
# setup/walter-host/services/openclaw/compose.yml includes that sidecar.
#
# Usage (from operator workstation):
#   scp -r setup/walter-host/services/openclaw walter-vm:/tmp/openclaw-deploy
#   ssh walter-vm "sudo rsync -a --delete /tmp/openclaw-deploy/ /opt/walter-vm/services/openclaw/ && \
#                  cd /opt/walter-vm/services/openclaw && bash deploy.sh"

set -euo pipefail

SVC_DIR="${SVC_DIR:-/opt/walter-vm/services/openclaw}"
ENV_FILE="${SVC_DIR}/.env"
IDENTITY_FILE="/etc/walter-os/infisical-identity"
PORT="18789"

cd "$SVC_DIR"

# ---- helpers -------------------------------------------------------------
env_value() {
  local key="$1"
  local value="${!key-}"

  if [[ -z "$value" && -f "$ENV_FILE" ]]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  fi

  value="${value%"${value##*[![:space:]]}"}"   # rtrim
  value="${value#"${value%%[![:space:]]*}"}"   # ltrim
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

# ---- 0. .env bootstrap ---------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  cp .env.template "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "  ✓ .env scaffolded; fill required values before re-running"
fi

# ---- 1. Domain configuration --------------------------------------------
WALTER_DOMAIN="$(env_value WALTER_DOMAIN)"
TUNNEL_HOSTNAME="$(env_value OPENCLAW_TUNNEL_HOSTNAME)"

if [[ -z "$WALTER_DOMAIN" ]]; then
  echo "✗ set WALTER_DOMAIN in $ENV_FILE or export it before deploy." >&2
  echo "  Example: WALTER_DOMAIN=example.com bash deploy.sh" >&2
  exit 1
fi

if [[ -z "$TUNNEL_HOSTNAME" ]]; then
  TUNNEL_HOSTNAME="claw.${WALTER_DOMAIN}"
fi

# ---- 2. Required runtime configuration ----------------------------------
missing=()
for required_key in \
  WALTER_DOMAIN \
  OPENCLAW_TELEGRAM_BOT_TOKEN \
  OPENCLAW_OPERATOR_CHAT_ID \
  LITELLM_OPENCLAW_KEY \
  OPENCLAW_GATEWAY_TOKEN
do
  required_value="$(env_value "$required_key")"
  if [[ -z "$required_value" ]]; then
    missing+=("$required_key")
  else
    printf -v "$required_key" '%s' "$required_value"
    export "${required_key?}"
  fi
done

if ((${#missing[@]} > 0)); then
  echo "✗ missing required OpenClaw config in $ENV_FILE or environment:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "  Fill $ENV_FILE from Infisical or another secret store, then re-run." >&2
  exit 1
fi
echo "  ✓ required OpenClaw config present"

# ---- 3. Verify upstream dependencies ------------------------------------
echo "→ checking LiteLLM reachability..."
if ! curl -fsS -m 5 http://127.0.0.1:4000/health/liveliness >/dev/null; then
  echo "  ✗ LiteLLM not reachable at 127.0.0.1:4000" >&2
  exit 1
fi
echo "  ✓ LiteLLM live"

# claude-sub-router is required only if the effective model asks for it.
# compose.yml defaults to sonnet, so an absent override must not require CCR.
default_model="$(env_value OPENCLAW_DEFAULT_MODEL)"
default_model="${default_model:-sonnet}"
if [[ "$default_model" == claude-sub* ]]; then
  if ! curl -fsS -m 5 http://127.0.0.1:1457/health >/dev/null 2>&1; then
    echo "  ✗ claude-sub-router not responding on 1457 and OPENCLAW_DEFAULT_MODEL=${default_model}." >&2
    echo "    Either bring the bridge up, OR switch model to a working route in compose.yml." >&2
    exit 1
  fi
  echo "  ✓ claude-sub-router live (required for default model ${default_model})"
fi

# ---- 4. Verify cloudflared tunnel route ---------------------------------
if [[ -f /etc/cloudflared/config.yml ]]; then
  if ! grep -Fq "${TUNNEL_HOSTNAME}" /etc/cloudflared/config.yml; then
    echo "  ⚠ cloudflared route for ${TUNNEL_HOSTNAME} NOT found in /etc/cloudflared/config.yml"
    echo "    Add:  - hostname: ${TUNNEL_HOSTNAME}"
    echo "          service: http://127.0.0.1:${PORT}"
    echo "    Then: sudo systemctl restart cloudflared"
  else
    echo "  ✓ cloudflared route for ${TUNNEL_HOSTNAME} present"
  fi
fi

# ---- 5. Optional Infisical host hint -------------------------------------
if [[ -r "$IDENTITY_FILE" ]] || sudo -n test -r "$IDENTITY_FILE" 2>/dev/null; then
  echo "  ✓ machine identity present at $IDENTITY_FILE"
else
  echo "  ⚠ $IDENTITY_FILE not present; using $ENV_FILE/env values for this deploy"
fi

# ---- 6. Pull + up -------------------------------------------------------
echo "→ docker compose pull"
docker compose --env-file "$ENV_FILE" pull

echo "→ validating docker compose config"
docker compose --env-file "$ENV_FILE" config >/dev/null

echo "→ docker compose up -d"
docker compose --env-file "$ENV_FILE" up -d

# ---- 7. Wait for health --------------------------------------------------
echo "→ waiting for openclaw to become healthy (this may take 2-3min on first run)..."
for i in $(seq 1 30); do
  status="$(docker inspect --format '{{.State.Health.Status}}' openclaw 2>/dev/null || echo unknown)"
  if [[ "$status" == "healthy" ]]; then
    echo "  ✓ openclaw is healthy"
    break
  fi
  if [[ "$status" == "unhealthy" ]]; then
    if docker logs openclaw 2>&1 | tail -5 | grep -q "not onboarded yet"; then
      echo "  ⚠ openclaw has never been onboarded. Run:"
      echo "    docker exec -it openclaw /workspace/.npm-global/bin/openclaw onboard"
      echo "  Then re-run this script."
      exit 20
    fi
  fi
  if [[ $i -eq 30 ]]; then
    echo "  ✗ openclaw did not become healthy in 5min. Recent logs:"
    docker logs --tail 50 openclaw
    exit 1
  fi
  sleep 10
done

# ---- 8. Smoke test -------------------------------------------------------
echo "→ smoke testing /healthz and /readyz..."
curl -fsS -m 5 "http://127.0.0.1:${PORT}/healthz" | grep -q '"ok":true' || {
  echo "  ✗ /healthz did not return ok"; exit 1; }
curl -fsS -m 5 "http://127.0.0.1:${PORT}/readyz" | grep -q '"ready":true' || {
  echo "  ✗ /readyz did not return ready"; exit 1; }
echo "  ✓ healthz + readyz OK"

# ---- 9. Verify env→JSON provisioning succeeded --------------------------
echo "→ verifying gateway config provisioned into runtime JSON..."
json_gateway_token="$(docker exec openclaw node -e "console.log(JSON.parse(require('fs').readFileSync('/workspace/.openclaw/openclaw.json','utf8')).gateway.auth.token)" 2>/dev/null)"
if [[ -n "$json_gateway_token" ]] && [[ "${#json_gateway_token}" -ge 32 ]]; then
  echo "  ✓ gateway token populated in runtime JSON (length=${#json_gateway_token})"
else
  echo "  ✗ gateway token not propagated into runtime JSON" >&2
  exit 1
fi

# ---- 10. Plugin capability matrix sanity check ---------------------------
echo "→ plugin capability matrix (manual check required):"
echo "  Per spec §3, these plugins MUST be remote=deny in"
echo "  https://${TUNNEL_HOSTNAME}/ → Settings → Plugins:"
echo "    - browser"
echo "    - file-transfer"
echo "    - phone-control"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OpenClaw is up: https://${TUNNEL_HOSTNAME}/"
echo
echo "Gateway token: keep it out of git and rotate it on suspected exposure."
echo "  Current compose consumes it from $ENV_FILE or the process environment."
echo
echo "Rotate any secret:"
if [[ -n "$WALTER_DOMAIN" ]]; then
  echo "  1. Edit in Infisical UI (https://secrets.${WALTER_DOMAIN})"
else
  echo "  1. Edit in the Infisical UI for this deployment"
fi
echo "  2. Update $ENV_FILE or exported env values on the host"
echo "  3. docker compose --env-file $ENV_FILE up -d --force-recreate openclaw"
echo
if [[ -n "$WALTER_DOMAIN" ]]; then
  echo "Monitor: https://status.${WALTER_DOMAIN} (look for 'OpenClaw')"
else
  echo "Monitor: your deployment status dashboard (look for 'OpenClaw')"
fi
echo "Logs:    docker logs -f openclaw"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
