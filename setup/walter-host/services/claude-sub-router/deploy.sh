#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../subscription-router-pattern/deploy-router.sh" \
  "claude-sub-router" \
  "1457" \
  "CSR_APIKEY" \
  "claude-sub,claude-sub-opus"
