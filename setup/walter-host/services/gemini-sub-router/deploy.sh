#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../subscription-router-pattern/deploy-router.sh" \
  "gemini-sub-router" \
  "1458" \
  "GSR_APIKEY" \
  "gemini-sub,gemini-sub-flash"
