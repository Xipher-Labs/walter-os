#!/usr/bin/env bash
# Smoke-test an OpenAI-compatible subscription router after deploy.

set -euo pipefail

: "${ROUTER_BASE_URL:?ROUTER_BASE_URL required, for example http://127.0.0.1:1457}"

ROUTER_NAME="${ROUTER_NAME:-subscription-router}"
ROUTER_API_KEY="${ROUTER_API_KEY:-}"
ROUTER_SMOKE_TIMEOUT_SECONDS="${ROUTER_SMOKE_TIMEOUT_SECONDS:-120}"
ROUTER_SMOKE_PROMPT="${ROUTER_SMOKE_PROMPT:-Reply with exactly: ROUTER_SMOKE_OK}"
LITELLM_BASE_URL="${LITELLM_BASE_URL:-http://127.0.0.1:4000}"
LITELLM_SMOKE_MODELS="${LITELLM_SMOKE_MODELS:-}"
LITELLM_ENV_FILE="${LITELLM_ENV_FILE:-/opt/walter-vm/services/litellm/.env}"

env_file_value() {
  local key="$1" line value
  [[ -f "$LITELLM_ENV_FILE" ]] || return 1
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$LITELLM_ENV_FILE" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$line" ]] || return 1
  value="${line#*=}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

LITELLM_API_KEY="${LITELLM_API_KEY:-${LITELLM_MASTER_KEY:-$(env_file_value LITELLM_MASTER_KEY || true)}}"

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

auth_args() {
  local token="$1"
  if [[ -n "$token" ]]; then
    printf '%s\n' "-H" "Authorization: Bearer $token"
  fi
}

completion_payload() {
  local model="$1"
  MODEL="$model" PROMPT="$ROUTER_SMOKE_PROMPT" python3 - <<'PY'
import json
import os

print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
    "max_tokens": 8,
}))
PY
}

post_completion() {
  local label="$1"
  local base_url="$2"
  local model="$3"
  local token="$4"
  local code payload
  local -a auth=()
  payload="$(completion_payload "$model")"

  mapfile -t auth < <(auth_args "$token")
  code="$(curl -sS -o "$tmp_body" -w "%{http_code}" \
    --max-time "$ROUTER_SMOKE_TIMEOUT_SECONDS" \
    -X POST "${base_url%/}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    "${auth[@]}" \
    --data-binary "$payload" 2>/dev/null || echo 000)"

  if [[ "$code" != "200" ]]; then
    echo "✗ ${label} smoke failed for model ${model}: HTTP ${code}" >&2
    sed -n '1,20p' "$tmp_body" >&2 || true
    return 1
  fi

  echo "  ✓ ${label} model ${model}"
}

echo "→ discovering advertised models from ${ROUTER_NAME}..."
mapfile -t router_auth < <(auth_args "$ROUTER_API_KEY")
models_code="$(curl -sS -o "$tmp_body" -w "%{http_code}" \
  --max-time "$ROUTER_SMOKE_TIMEOUT_SECONDS" \
  "${router_auth[@]}" \
  "${ROUTER_BASE_URL%/}/v1/models" 2>/dev/null || echo 000)"

if [[ "$models_code" != "200" ]]; then
  echo "✗ failed to fetch ${ROUTER_NAME} /v1/models: HTTP ${models_code}" >&2
  sed -n '1,20p' "$tmp_body" >&2 || true
  exit 1
fi

if ! models_text="$(python3 -c '
import json
import sys

payload = json.load(sys.stdin)
for item in payload.get("data", []):
    model_id = item.get("id")
    if isinstance(model_id, str) and model_id:
        print(model_id)
' < "$tmp_body")"; then
  echo "✗ failed to parse ${ROUTER_NAME} /v1/models response" >&2
  sed -n '1,20p' "$tmp_body" >&2 || true
  exit 1
fi
router_models=()
while IFS= read -r model; do
  [[ -n "$model" ]] && router_models+=("$model")
done <<< "$models_text"

if [[ "${#router_models[@]}" -eq 0 ]]; then
  echo "✗ ${ROUTER_NAME} reported no advertised models" >&2
  exit 1
fi

echo "→ smoke testing ${#router_models[@]} advertised ${ROUTER_NAME} models..."
for model in "${router_models[@]}"; do
  post_completion "$ROUTER_NAME direct" "$ROUTER_BASE_URL" "$model" "$ROUTER_API_KEY"
done

if [[ -n "$LITELLM_SMOKE_MODELS" ]]; then
  if [[ -z "$LITELLM_API_KEY" ]]; then
    echo "✗ LITELLM_SMOKE_MODELS is set but LITELLM_MASTER_KEY/LITELLM_API_KEY is missing" >&2
    exit 1
  fi

  echo "→ smoke testing LiteLLM alias hop (${LITELLM_SMOKE_MODELS})..."
  IFS=',' read -r -a litellm_models <<< "$LITELLM_SMOKE_MODELS"
  for raw_model in "${litellm_models[@]}"; do
    model="$(printf '%s' "$raw_model" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$model" ]] || continue
    post_completion "LiteLLM" "$LITELLM_BASE_URL" "$model" "$LITELLM_API_KEY"
  done
fi

echo "✓ ${ROUTER_NAME} deploy smoke passed"
