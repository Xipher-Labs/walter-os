#!/usr/bin/env bash
# setup/walter-host/services/headscale/deploy.sh
#
# Renders config.yaml.template → config.yaml via envsubst, then starts
# the Headscale stack via docker compose.
#
# Headscale's YAML loader does NOT expand ${...} shell variables.
# The template pattern (render at deploy time) is the same approach used
# for Synapse's element/config.json (commit 60966f2).
#
# Usage:
#   WALTER_DOMAIN=yourdomain.com ./deploy.sh
#   WALTER_DOMAIN=yourdomain.com ./deploy.sh --down      # stop stack
#   ./deploy.sh --diagnose                              # inspect registration drift
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--diagnose" ]]; then
  shift
  exec "${SCRIPT_DIR}/diagnose.sh" "$@"
fi

: "${WALTER_DOMAIN:?WALTER_DOMAIN required for Headscale deploy — set it in your environment or .env.local}"

# Render config template
envsubst < "${SCRIPT_DIR}/config.yaml.template" > "${SCRIPT_DIR}/config.yaml"
echo "Rendered config.yaml for domain: ${WALTER_DOMAIN}"

if [[ "${1:-}" == "--down" ]]; then
  docker compose -f "${SCRIPT_DIR}/compose.yml" down
  exit 0
fi

docker compose -f "${SCRIPT_DIR}/compose.yml" up -d
echo "Headscale started. If client registration fails, run: ${SCRIPT_DIR}/deploy.sh --diagnose"
