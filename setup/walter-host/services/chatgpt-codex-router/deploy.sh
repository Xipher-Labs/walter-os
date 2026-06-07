#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../subscription-router-pattern/deploy-router.sh" \
  "chatgpt-codex-router" \
  "1456" \
  "CCR_APIKEY" \
  "codex-sub,codex-sub-think"
