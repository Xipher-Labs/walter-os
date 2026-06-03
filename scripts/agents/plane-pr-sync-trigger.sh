#!/usr/bin/env bash
# scripts/agents/plane-pr-sync-trigger.sh
# Translate Forgejo pull_request webhook payloads into plane-pr-sync.sh events.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SYNC_SCRIPT="${WALTER_PLANE_PR_SYNC_SCRIPT:-${WALTER_OS_HOME}/scripts/agents/plane-pr-sync.sh}"

usage() {
  cat <<'EOF'
Usage:
  plane-pr-sync-trigger.sh --event pull_request --issue <plane-issue-id> [--payload-file <path|->]

Reads a Forgejo pull_request webhook payload from --payload-file or stdin and
calls plane-pr-sync.sh with one of the supported sync events:
  opened, reopened, synchronized  -> link
  closed with merged=true         -> merged
  closed with merged=false        -> no-op

The Plane issue ID must be supplied by the caller. This wrapper does not parse
arbitrary PR bodies.
EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "plane-pr-sync-trigger: jq is required" >&2
    exit 3
  fi
}

require_option_value() {
  local flag="$1" value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "plane-pr-sync-trigger: missing value for $flag" >&2
    exit 2
  fi
}

reject_newline() {
  local name="$1" value="$2"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "plane-pr-sync-trigger: $name contains a newline" >&2
    exit 2
  fi
}

require_value() {
  local name="$1" value="$2"
  if [[ -z "$value" ]]; then
    echo "plane-pr-sync-trigger: missing $name" >&2
    exit 2
  fi
}

event="${FORGEJO_EVENT:-${GITEA_EVENT:-}}"
issue=""
payload_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event) require_option_value "$1" "${2:-}"; event="$2"; shift 2 ;;
    --issue) require_option_value "$1" "${2:-}"; issue="$2"; shift 2 ;;
    --payload-file) require_option_value "$1" "${2:-}"; payload_file="$2"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "plane-pr-sync-trigger: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

require_value "--event" "$event"
require_value "--issue" "$issue"
reject_newline "event" "$event"
reject_newline "issue" "$issue"

if [[ "$event" != "pull_request" ]]; then
  echo "plane-pr-sync-trigger: unsupported event: $event" >&2
  exit 2
fi

require_jq

if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo "plane-pr-sync-trigger: missing sync primitive: $SYNC_SCRIPT" >&2
  exit 3
fi

read_payload() {
  if [[ -n "$payload_file" ]]; then
    if [[ "$payload_file" == "-" ]]; then
      cat
      return 0
    fi
    if [[ ! -f "$payload_file" ]]; then
      echo "plane-pr-sync-trigger: payload file not found: $payload_file" >&2
      exit 2
    fi
    cat "$payload_file"
    return 0
  fi

  if [[ -t 0 ]]; then
    echo "plane-pr-sync-trigger: missing --payload-file or stdin payload" >&2
    exit 2
  fi
  cat
}

payload="$(read_payload)"
if ! jq -e . >/dev/null 2>&1 <<<"$payload"; then
  echo "plane-pr-sync-trigger: payload is not valid JSON" >&2
  exit 2
fi

jq_string() {
  local name="$1" expr="$2" value
  value="$(jq -er "$expr // empty" <<<"$payload" 2>/dev/null || true)"
  require_value "$name" "$value"
  reject_newline "$name" "$value"
  printf '%s\n' "$value"
}

action="$(jq_string "action" '.action')"
repo="$(jq_string "repo" '.repository.full_name')"
pr_url="$(jq_string "pr-url" '.pull_request.html_url // .pull_request.url')"
pr_number="$(jq_string "pr-number" '.pull_request.number | tostring')"
branch="$(jq_string "branch" '.pull_request.head.ref')"
merged="$(jq -r '(.pull_request.merged // false) | tostring' <<<"$payload")"
reject_newline "pull_request.merged" "$merged"

if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "plane-pr-sync-trigger: pull_request.number must be numeric" >&2
  exit 2
fi

sync_args=()
case "$action" in
  opened|reopened|synchronized)
    sync_args=(
      link
      --issue "$issue"
      --pr-url "$pr_url"
      --pr-number "$pr_number"
      --repo "$repo"
      --branch "$branch"
    )
    ;;
  closed)
    if [[ "$merged" != "true" ]]; then
      echo "plane-pr-sync-trigger: no sync action for closed unmerged PR"
      exit 0
    fi
    merge_sha="$(jq_string "merge sha" '.pull_request.merged_commit_sha // .pull_request.merge_commit_sha // .after')"
    sync_args=(
      merged
      --issue "$issue"
      --pr-url "$pr_url"
      --pr-number "$pr_number"
      --repo "$repo"
      --branch "$branch"
      --merge-sha "$merge_sha"
    )
    ;;
  *)
    echo "plane-pr-sync-trigger: unsupported pull_request action: $action" >&2
    exit 2
    ;;
esac

bash "$SYNC_SCRIPT" "${sync_args[@]}"
