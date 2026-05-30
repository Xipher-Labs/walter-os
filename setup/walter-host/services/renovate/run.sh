#!/usr/bin/env bash
# Run the optional self-hosted Renovate container with secrets already loaded.

set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SERVICE_DIR"

usage() {
  cat <<'USAGE'
Usage: ./run.sh [run|dry-run]

Prerequisite:
  walter_secrets_load

Environment:
  RENOVATE_TOKEN           required, loaded from Infisical
  RENOVATE_REPOSITORIES    comma-separated repo list, unless autodiscover=true
  RENOVATE_AUTODISCOVER    optional, default false

USAGE
}

mode="${1:-run}"
case "$mode" in
  run)
    ;;
  dry-run)
    export RENOVATE_DRY_RUN="${RENOVATE_DRY_RUN:-full}"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "renovate: unknown mode: $mode" >&2
    usage >&2
    exit 2
    ;;
esac

: "${RENOVATE_TOKEN:?RENOVATE_TOKEN must be loaded via walter_secrets_load or walter-run}"

if [[ -z "${RENOVATE_REPOSITORIES:-}" && "${RENOVATE_AUTODISCOVER:-false}" != "true" ]]; then
  echo "renovate: set RENOVATE_REPOSITORIES or RENOVATE_AUTODISCOVER=true." >&2
  exit 2
fi

exec docker compose --profile renovate run --rm renovate
