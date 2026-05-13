#!/usr/bin/env bash
# devrel-analyst CLI wrapper
# Convenience wrapper: `walter-os analyst <query> [args]` → query.py
#
# Usage:
#   analyst-cli.sh top_threads --since 30d --limit 5
#   analyst-cli.sh optimal_hours --platform twitter
#   analyst-cli.sh pattern_match --topic "solana-rpc"
#   analyst-cli.sh weekly_digest
#   analyst-cli.sh <any> --dry-run
#
# Refs: docs/specs/devrel-analytics-stack.md (AC-13)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUERY_PY="${SCRIPT_DIR}/query.py"

if [[ ! -f "$QUERY_PY" ]]; then
  echo "[devrel-analyst] ERROR: query.py not found at $QUERY_PY" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[devrel-analyst] ERROR: python3 not found." >&2
  exit 1
fi

exec python3 "$QUERY_PY" "$@"
