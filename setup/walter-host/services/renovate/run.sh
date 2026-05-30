#!/usr/bin/env bash
# Run the optional self-hosted Renovate container with secrets already loaded.

set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SERVICE_DIR"

load_nonsecret_env_file() {
  local env_file="$SERVICE_DIR/.env"
  [[ -f "$env_file" ]] || return 0

  local allowed_keys=(
    RENOVATE_PLATFORM
    RENOVATE_ENDPOINT
    RENOVATE_REPOSITORIES
    RENOVATE_AUTODISCOVER
    RENOVATE_AUTODISCOVER_FILTER
    RENOVATE_AUTODISCOVER_NAMESPACES
    RENOVATE_DRY_RUN
    RENOVATE_LOG_LEVEL
    WALTER_TIMEZONE
  )
  local line key value allowed allowed_key

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    if [[ ! "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      echo "renovate: ignoring invalid .env line: $line" >&2
      continue
    fi

    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ "$key" == "RENOVATE_TOKEN" ]]; then
      echo "renovate: refuse to load RENOVATE_TOKEN from .env; use walter_secrets_load." >&2
      exit 2
    fi

    allowed=0
    for allowed_key in "${allowed_keys[@]}"; do
      if [[ "$key" == "$allowed_key" ]]; then
        allowed=1
        break
      fi
    done
    if [[ "$allowed" -ne 1 ]]; then
      echo "renovate: ignoring unsupported .env key: $key" >&2
      continue
    fi

    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi

    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$env_file"
}

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

load_nonsecret_env_file

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

if [[ "${RENOVATE_AUTODISCOVER:-false}" == "true" \
    && -z "${RENOVATE_AUTODISCOVER_FILTER:-}" \
    && -z "${RENOVATE_AUTODISCOVER_NAMESPACES:-}" ]]; then
  echo "renovate: RENOVATE_AUTODISCOVER=true requires RENOVATE_AUTODISCOVER_FILTER or RENOVATE_AUTODISCOVER_NAMESPACES." >&2
  exit 2
fi

exec docker compose --profile renovate run --rm renovate
