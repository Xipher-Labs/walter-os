#!/usr/bin/env bash
# Import DevRel analytics n8n workflows via n8n REST API.
#
# Run after n8n is up and credentials are configured.
# Idempotent: uses PUT /workflows/<id> if workflow already exists (by name).
#
# Usage:
#   ./import-workflows.sh
#   N8N_API_KEY=<key> N8N_URL=http://localhost:5678 ./import-workflows.sh
#   N8N_API_KEY=<key> N8N_BASIC_AUTH_USER=<user> N8N_BASIC_AUTH_PASSWORD=<pass> ./import-workflows.sh
#
# Prereqs:
#   - n8n running (docker compose up -d n8n)
#   - N8N_API_KEY set (Settings → API in n8n UI, or via env)
#   - curl + jq installed
#
# Refs: docs/specs/devrel-analytics-stack.md (V-prereq-5)

set -euo pipefail

N8N_URL="${N8N_URL:-http://localhost:5678}"
N8N_API_KEY="${N8N_API_KEY:-}"
N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-}"
N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-}"
WORKFLOWS_DIR="$(cd "$(dirname "$0")/workflows" && pwd)"

if [[ -z "$N8N_API_KEY" ]]; then
  echo "[import-workflows] ERROR: N8N_API_KEY not set." >&2
  echo "  Get it from: n8n UI → Settings → n8n API → Create an API key" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[import-workflows] ERROR: jq is required." >&2
  exit 1
fi

curl_auth_args=()
if [[ -n "$N8N_BASIC_AUTH_USER" || -n "$N8N_BASIC_AUTH_PASSWORD" ]]; then
  if [[ -z "$N8N_BASIC_AUTH_USER" || -z "$N8N_BASIC_AUTH_PASSWORD" ]]; then
    echo "[import-workflows] ERROR: set both N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD, or neither." >&2
    exit 1
  fi
  curl_auth_args=(-u "${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}")
fi

# Verify n8n is reachable
if ! curl -sf "${curl_auth_args[@]}" -o /dev/null "${N8N_URL}/api/v1/workflows" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}"; then
  echo "[import-workflows] ERROR: Cannot reach n8n at ${N8N_URL}" >&2
  echo "  Check that n8n is running: docker compose ps n8n" >&2
  exit 1
fi

import_workflow() {
  local file="$1"
  local name
  name=$(jq -r '.name' "$file")

  echo "[import-workflows] Importing: $name (from $(basename "$file"))"

  # Check if workflow already exists by name
  local existing_id
  existing_id=$(curl -sf "${curl_auth_args[@]}" "${N8N_URL}/api/v1/workflows" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    | jq -r --arg name "$name" '.data[] | select(.name == $name) | .id' \
    | head -1)

  if [[ -n "$existing_id" ]]; then
    # Update existing
    curl -sf "${curl_auth_args[@]}" -X PUT "${N8N_URL}/api/v1/workflows/${existing_id}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "@${file}" >/dev/null
    echo "  [updated] id=${existing_id}"
  else
    # Create new
    local new_id
    new_id=$(curl -sf "${curl_auth_args[@]}" -X POST "${N8N_URL}/api/v1/workflows" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "@${file}" \
      | jq -r '.id')
    echo "  [created] id=${new_id}"
  fi
}

echo "[import-workflows] Starting import from ${WORKFLOWS_DIR}"
echo "[import-workflows] Target n8n: ${N8N_URL}"
echo ""

for workflow_file in "$WORKFLOWS_DIR"/*.json; do
  [[ -f "$workflow_file" ]] || continue
  import_workflow "$workflow_file"
done

echo ""
echo "[import-workflows] Done. Activate workflows in n8n UI or via API:"
echo "  curl -X POST ${N8N_URL}/api/v1/workflows/<id>/activate -H 'X-N8N-API-KEY: <key>'"
echo ""
echo "[import-workflows] NOTE: Workflows are imported as INACTIVE."
echo "  Configure credentials first, then activate each workflow."
echo "  See docs/specs/devrel-analytics-stack.md for credential setup."
