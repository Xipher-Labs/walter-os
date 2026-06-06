#!/usr/bin/env bash
# Shared deploy helper for subscription routers.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-router.sh <router-name> <port> <api-key-env> <litellm-smoke-aliases>

Run from a router wrapper (for example chatgpt-codex-router/deploy.sh).
EOF
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 2
fi

ROUTER_NAME="$1"
ROUTER_PORT="$2"
ROUTER_API_KEY_ENV="$3"
DEFAULT_LITELLM_SMOKE_MODELS="$4"

PATTERN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVC_DIR="${SVC_DIR:-$(cd "$PATTERN_DIR/../$ROUTER_NAME" && pwd)}"
ENV_FILE="${ENV_FILE:-$SVC_DIR/.env}"

cd "$SVC_DIR"

env_value() {
  local key="$1" value line
  value="${!key-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi
  [[ -f "$ENV_FILE" ]] || return 1
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$ENV_FILE" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$line" ]] || return 1
  value="${line#*=}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

if [[ ! -f "$ENV_FILE" && -f .env.template && -z "${!ROUTER_API_KEY_ENV-}" ]]; then
  cp .env.template "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "✗ scaffolded $ENV_FILE. Fill $ROUTER_API_KEY_ENV and re-run deploy." >&2
  exit 2
fi

compose=(docker compose)
if [[ -f "$ENV_FILE" ]]; then
  compose+=(--env-file "$ENV_FILE")
fi

echo "→ validating ${ROUTER_NAME} compose config"
"${compose[@]}" config >/dev/null

echo "→ pulling ${ROUTER_NAME}"
"${compose[@]}" pull

echo "→ starting ${ROUTER_NAME}"
"${compose[@]}" up -d

echo "→ waiting for ${ROUTER_NAME} to become healthy..."
status="unknown"
for _ in $(seq 1 90); do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$ROUTER_NAME" 2>/dev/null || echo unknown)"
  [[ "$status" == "healthy" ]] && break
  sleep 10
done

if [[ "$status" != "healthy" ]]; then
  echo "✗ ${ROUTER_NAME} did not become healthy" >&2
  docker logs --tail 80 "$ROUTER_NAME" >&2 || true
  exit 1
fi

ROUTER_API_KEY="$(env_value "$ROUTER_API_KEY_ENV" || true)"
export ROUTER_NAME
export ROUTER_BASE_URL="http://127.0.0.1:${ROUTER_PORT}"
export ROUTER_API_KEY
export LITELLM_SMOKE_MODELS="${LITELLM_SMOKE_MODELS:-$DEFAULT_LITELLM_SMOKE_MODELS}"

"$PATTERN_DIR/deploy-smoke.sh"
