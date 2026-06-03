#!/usr/bin/env bash
# walter-os feature-state — persistent AD-2 feature-state ledger.
#
# Usage:
#   walter-os feature-state init <id> [--repo <dir>] [--title <text>] [--issue <id>] [--idea <text>] [--spec <path>] [--force]
#   walter-os feature-state validate [repo-dir|state-file]
#   walter-os feature-state record-post-merge <id> --decision <decision> --next-action <action> --commit <sha> [--source <name>] [--repo <dir>]
#   walter-os feature-state help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

if [[ ! -f "${WALTER_OS_HOME}/scripts/walter/lib/feature-state.sh" ]]; then
  echo "feature-state: library not found under WALTER_OS_HOME=${WALTER_OS_HOME}" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/feature-state.sh"

print_help() {
  awk '/^[^#]/ && NR > 1 { exit } /^#( |$)/ { sub(/^# ?/, ""); print }' "$0"
}

require_value() {
  local flag="$1" value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "feature-state: ${flag} requires a value" >&2
    exit 64
  fi
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  init)
    id="${1:-}"
    if [[ -z "$id" ]]; then
      echo "feature-state: init requires a feature id" >&2
      exit 64
    fi
    shift

    repo="$(walter_feature_state_repo_root)"
    title=""
    issue=""
    idea=""
    spec_path=""
    force="0"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo)
          repo="${2:-}"
          require_value "--repo" "$repo"
          shift 2
          ;;
        --title)
          title="${2:-}"
          require_value "--title" "$title"
          shift 2
          ;;
        --issue)
          issue="${2:-}"
          require_value "--issue" "$issue"
          shift 2
          ;;
        --idea)
          idea="${2:-}"
          require_value "--idea" "$idea"
          shift 2
          ;;
        --spec)
          spec_path="${2:-}"
          require_value "--spec" "$spec_path"
          shift 2
          ;;
        --force)
          force="1"
          shift
          ;;
        -h|--help|help)
          print_help
          exit 0
          ;;
        -*)
          echo "feature-state: unknown option: $1" >&2
          exit 64
          ;;
        *)
          echo "feature-state: unexpected argument: $1" >&2
          exit 64
          ;;
      esac
    done

    walter_feature_state_init "$repo" "$id" "$title" "$issue" "$idea" "$spec_path" "$force"
    ;;

  validate)
    walter_feature_state_validate_target "${1:-$(pwd)}"
    ;;

  record-post-merge)
    id="${1:-}"
    if [[ -z "$id" ]]; then
      echo "feature-state: record-post-merge requires a feature id" >&2
      exit 64
    fi
    shift

    repo="$(walter_feature_state_repo_root)"
    decision=""
    next_action=""
    merge_sha=""
    source="post-merge-check"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo)
          repo="${2:-}"
          require_value "--repo" "$repo"
          shift 2
          ;;
        --decision)
          decision="${2:-}"
          require_value "--decision" "$decision"
          shift 2
          ;;
        --next-action)
          next_action="${2:-}"
          require_value "--next-action" "$next_action"
          shift 2
          ;;
        --commit|--merge-sha)
          merge_sha="${2:-}"
          require_value "$1" "$merge_sha"
          shift 2
          ;;
        --source)
          source="${2:-}"
          require_value "--source" "$source"
          shift 2
          ;;
        -h|--help|help)
          print_help
          exit 0
          ;;
        -*)
          echo "feature-state: unknown option: $1" >&2
          exit 64
          ;;
        *)
          echo "feature-state: unexpected argument: $1" >&2
          exit 64
          ;;
      esac
    done

    if [[ -z "$decision" || -z "$next_action" || -z "$merge_sha" ]]; then
      echo "feature-state: record-post-merge requires --decision, --next-action, and --commit" >&2
      exit 64
    fi

    walter_feature_state_record_post_merge "$repo" "$id" "$decision" "$next_action" "$merge_sha" "$source"
    ;;

  -h|--help|help)
    print_help
    ;;

  *)
    echo "feature-state: unknown command: $cmd" >&2
    print_help >&2
    exit 64
    ;;
esac
