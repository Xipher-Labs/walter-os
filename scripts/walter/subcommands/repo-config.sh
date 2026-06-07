#!/usr/bin/env bash
# walter-os repo-config — validate walter-repo-config.yaml policy files.
#
# Usage:
#   walter-os repo-config validate [repo-dir|config-file]
#   walter-os repo-config defaults [balanced|hackathon]
#   walter-os repo-config verification-plan [repo-dir|config-file] [--risk low|medium|high] [--path <path>]...
#   walter-os repo-config help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
if [[ ! -f "${WALTER_OS_HOME}/scripts/walter/lib/repo-config.sh" ]]; then
  WALTER_OS_HOME="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

if [[ ! -f "${WALTER_OS_HOME}/scripts/walter/lib/repo-config.sh" ]]; then
  echo "repo-config: library not found under WALTER_OS_HOME=${WALTER_OS_HOME}" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/repo-config.sh"

print_help() {
  awk '/^[^#]/ && NR > 1 { exit } /^#( |$)/ { sub(/^# ?/, ""); print }' "$0"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  validate)
    walter_repo_config_validate "${1:-$(pwd)}"
    ;;
  defaults|print-defaults)
    walter_repo_config_defaults "${1:-balanced}"
    ;;
  verification-plan|verify-plan)
    target="${1:-$(pwd)}"
    if [[ "${1:-}" == --* ]]; then
      target="$(pwd)"
    else
      shift || true
    fi
    walter_repo_config_verification_plan "$target" "$@"
    ;;
  -h|--help|help)
    print_help
    ;;
  *)
    echo "repo-config: unknown command: $cmd" >&2
    print_help >&2
    exit 2
    ;;
esac
