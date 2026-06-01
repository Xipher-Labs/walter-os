#!/usr/bin/env bash
# sync.sh — backwards-compatible alias for the Walter-OS upgrade flow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "walter-os sync: compatibility alias for 'walter-os upgrade --local'." >&2
exec "${REPO_ROOT}/scripts/upgrade.sh" "$@" --local
