#!/usr/bin/env bash
# scripts/agents/plane-pr-sync.sh
# Sync Plane issue state with a Forgejo PR lifecycle event.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PLANE_LIB="${WALTER_OS_HOME}/scripts/agents/lib/plane.sh"

usage() {
  cat <<'EOF'
Usage: plane-pr-sync.sh <link|merged> --issue <id> --pr-url <url> --pr-number <n> --repo <owner/repo> --branch <name> [--merge-sha <sha>]

Events:
  link     Link an open PR to a Plane issue and move Plane to review.
  merged   Record a merged PR and move Plane to done.

This script never merges PRs, pushes branches, or approves reviews.
EOF
}

if [[ ! -f "$PLANE_LIB" ]]; then
  echo "plane-pr-sync: missing Plane helper: $PLANE_LIB" >&2
  exit 3
fi
# shellcheck source=/dev/null
source "$PLANE_LIB"

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "plane-pr-sync: jq is required" >&2
    exit 3
  fi
}

event="${1:-}"
if [[ "$event" == "-h" || "$event" == "--help" || "$event" == "help" ]]; then
  usage
  exit 0
fi
if [[ -z "$event" ]]; then
  echo "plane-pr-sync: missing event" >&2
  usage >&2
  exit 2
fi
shift

case "$event" in
  link|merged) ;;
  *)
    echo "plane-pr-sync: unknown event: $event" >&2
    usage >&2
    exit 2
    ;;
esac

issue=""
pr_url=""
pr_number=""
repo=""
branch=""
merge_sha=""

require_option_value() {
  local flag="$1" value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "plane-pr-sync: missing value for $flag" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) require_option_value "$1" "${2:-}"; issue="$2"; shift 2 ;;
    --pr-url) require_option_value "$1" "${2:-}"; pr_url="$2"; shift 2 ;;
    --pr-number) require_option_value "$1" "${2:-}"; pr_number="$2"; shift 2 ;;
    --repo) require_option_value "$1" "${2:-}"; repo="$2"; shift 2 ;;
    --branch) require_option_value "$1" "${2:-}"; branch="$2"; shift 2 ;;
    --merge-sha) require_option_value "$1" "${2:-}"; merge_sha="$2"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "plane-pr-sync: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

reject_newline() {
  local name="$1" value="$2"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "plane-pr-sync: $name contains a newline" >&2
    exit 2
  fi
}

for pair in \
  "issue:$issue" \
  "pr-url:$pr_url" \
  "pr-number:$pr_number" \
  "repo:$repo" \
  "branch:$branch" \
  "merge-sha:$merge_sha"; do
  reject_newline "${pair%%:*}" "${pair#*:}"
done

require_value() {
  local name="$1" value="$2"
  if [[ -z "$value" ]]; then
    echo "plane-pr-sync: missing --$name" >&2
    exit 2
  fi
}

require_value issue "$issue"
require_value pr-url "$pr_url"
require_value pr-number "$pr_number"
require_value repo "$repo"
require_value branch "$branch"

if [[ "$event" == "merged" ]]; then
  require_value merge-sha "$merge_sha"
fi

acquire_lock() {
  local lock_dir lock_key lock_file
  lock_dir="${TMPDIR:-/tmp}/walter-os-plane-pr-sync"
  lock_key="$(printf '%s' "${repo}-${pr_number}" | tr -c 'A-Za-z0-9._-' '_')"
  lock_file="${lock_dir}/${lock_key}.lock"
  mkdir -p "$lock_dir"

  if ! command -v flock >/dev/null 2>&1; then
    echo "plane-pr-sync: WARN flock not found; continuing without concurrency lock" >&2
    return 0
  fi

  exec 9>"$lock_file"
  if ! flock -n 9; then
    echo "plane-pr-sync: another sync is already running for ${repo}#${pr_number}" >&2
    exit 3
  fi
}

require_jq
acquire_lock
_plane_check_env || exit $?

plane_comment_once() {
  local marker="$1" body="$2"
  local existing jq_status
  if ! existing="$(_plane_curl GET "/issues/$issue/comments/")"; then
    echo "plane-pr-sync: failed to inspect Plane comments; aborting" >&2
    exit 3
  fi
  if jq -e --arg marker "$marker" \
      '[.results[]? | ((.comment_stripped // .comment_html // "") | contains($marker))] | any' \
      >/dev/null <<<"$existing"; then
    return 0
  else
    jq_status=$?
  fi
  if [[ "$jq_status" -gt 1 ]]; then
    echo "plane-pr-sync: failed to parse Plane comments; aborting" >&2
    exit 3
  fi
  plane_issue_comment "$issue" "$body"
}

forgejo_comment_once() {
  local marker="$1" body="$2" existing
  if ! command -v tea >/dev/null 2>&1; then
    echo "plane-pr-sync: WARN tea not found; skipped Forgejo PR comment" >&2
    return 0
  fi
  if existing="$(tea issues "$pr_number" --repo "$repo" --comments --output json 2>/dev/null)"; then
    if jq -e --arg marker "$marker" '.. | strings | select(contains($marker))' \
        >/dev/null <<<"$existing"; then
      return 0
    fi
  else
    echo "plane-pr-sync: WARN could not inspect Forgejo PR comments; attempting comment" >&2
  fi
  if ! tea issues comment "$pr_number" --repo "$repo" --comment "$body" >/dev/null 2>&1; then
    echo "plane-pr-sync: WARN Forgejo PR comment failed; continuing" >&2
  fi
}

short_sha() {
  printf '%s\n' "$1" | cut -c1-12
}

marker="[walter-pr-sync:${repo}#${pr_number}:${event}]"

case "$event" in
  link)
    comment="${marker} PR linked: ${pr_url} (branch: ${branch}). Requesting Plane issue move to review."
    plane_comment_once "$marker" "$comment"
    plane_issue_set_state "$issue" "review"
    forgejo_comment_once "$marker" "$comment"
    ;;
  merged)
    comment="${marker} PR merged: ${pr_url} at $(short_sha "$merge_sha"). Requesting Plane issue move to done."
    plane_comment_once "$marker" "$comment"
    plane_issue_set_state "$issue" "done"
    forgejo_comment_once "$marker" "$comment"
    ;;
esac

echo "plane-pr-sync: ${event} synced for ${repo}#${pr_number} -> Plane ${issue}"
