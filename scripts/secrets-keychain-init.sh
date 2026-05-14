#!/usr/bin/env bash
# Compatibility shim. The canonical command is now:
#   walter-os secrets-identity-init

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/secrets-identity-init.sh" "$@"
