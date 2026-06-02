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
  exit 2
fi
# shellcheck source=/dev/null
source "$PLANE_LIB"

event="${1:-}"
if [[ -z "$event" || "$event" == "-h" || "$event" == "--help" || "$event" == "help" ]]; then
  usage
  [[ -z "$event" || "$event" == "help" || "$event" == "-h" || "$event" == "--help" ]] && exit 0
fi
shift || true

issue=""
pr_url=""
pr_number=""
repo=""
branch=""
merge_sha=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) issue="${2:-}"; shift 2 ;;
    --pr-url) pr_url="${2:-}"; shift 2 ;;
    --pr-number) pr_number="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --branch) branch="${2:-}"; shift 2 ;;
    --merge-sha) merge_sha="${2:-}"; shift 2 ;;
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

case "$event" in
  link|merged) ;;
  *)
    echo "plane-pr-sync: unknown event: $event" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$event" == "merged" ]]; then
  require_value merge-sha "$merge_sha"
fi

_plane_check_env || exit $?

plane_comment_once() {
  local marker="$1" body="$2"
  local existing
  existing="$(_plane_curl GET "/issues/$issue/comments/" 2>/dev/null || printf '{"results":[]}')"
  if jq -e --arg marker "$marker" \
      '[.results[]? | ((.comment_stripped // .comment_html // "") | contains($marker))] | any' \
      >/dev/null <<<"$existing"; then
    return 0
  fi
  plane_issue_comment "$issue" "$body"
}

forgejo_comment() {
  local body="$1"
  if ! command -v tea >/dev/null 2>&1; then
    echo "plane-pr-sync: WARN tea not found; skipped Forgejo PR comment" >&2
    return 0
  fi
  tea issues comment "$pr_number" --repo "$repo" --comment "$body" >/dev/null
}

short_sha() {
  printf '%s\n' "$1" | cut -c1-12
}

marker="[walter-pr-sync:${repo}#${pr_number}:${event}]"

case "$event" in
  link)
    comment="${marker} PR linked: ${pr_url} (branch: ${branch}). Moving Plane issue to review."
    plane_comment_once "$marker" "$comment"
    plane_issue_set_state "$issue" "review"
    forgejo_comment "$comment"
    ;;
  merged)
    comment="${marker} PR merged: ${pr_url} at $(short_sha "$merge_sha"). Moving Plane issue to done."
    plane_comment_once "$marker" "$comment"
    plane_issue_set_state "$issue" "done"
    forgejo_comment "$comment"
    ;;
esac

echo "plane-pr-sync: ${event} synced for ${repo}#${pr_number} -> Plane ${issue}"
