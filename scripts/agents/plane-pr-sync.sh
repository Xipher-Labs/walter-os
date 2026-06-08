#!/usr/bin/env bash
# scripts/agents/plane-pr-sync.sh
# Sync Plane issue state with a Forgejo PR lifecycle event.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PLANE_LIB="${WALTER_OS_HOME}/scripts/agents/lib/plane.sh"

usage() {
  cat <<'EOF'
Usage:
  plane-pr-sync.sh link --issue <id> --pr-url <url> --pr-number <n> --repo <owner/repo> --branch <name>
  plane-pr-sync.sh merged --issue <id> --pr-url <url> --pr-number <n> --repo <owner/repo> --branch <name> --merge-sha <sha>

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
if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "plane-pr-sync: --pr-number must be numeric" >&2
  exit 2
fi

if [[ "$event" == "merged" ]]; then
  require_value merge-sha "$merge_sha"
fi

acquire_lock() {
  local lock_dir lock_key lock_file
  lock_dir="${TMPDIR:-/tmp}/walter-os-plane-pr-sync"
  lock_key="$(printf '%s' "${repo}-${pr_number}" | tr -c 'A-Za-z0-9._-' '_')"
  lock_file="${lock_dir}/${lock_key}.lock"

  if ! command -v flock >/dev/null 2>&1; then
    echo "plane-pr-sync: WARN flock not found; continuing without concurrency lock" >&2
    return 0
  fi

  if [[ -L "$lock_dir" ]]; then
    echo "plane-pr-sync: WARN unsafe symlink lock dir; continuing without concurrency lock" >&2
    return 0
  fi
  if ! mkdir -p "$lock_dir"; then
    echo "plane-pr-sync: WARN failed to create lock dir; continuing without concurrency lock" >&2
    return 0
  fi
  if [[ -L "$lock_dir" || ! -O "$lock_dir" ]]; then
    echo "plane-pr-sync: WARN unsafe lock dir ownership; continuing without concurrency lock" >&2
    return 0
  fi
  if ! chmod 700 "$lock_dir"; then
    echo "plane-pr-sync: WARN failed to secure lock dir; continuing without concurrency lock" >&2
    return 0
  fi
  if [[ -e "$lock_file" && ( -L "$lock_file" || ! -f "$lock_file" ) ]]; then
    echo "plane-pr-sync: WARN unsafe lock file; continuing without concurrency lock" >&2
    return 0
  fi

  if ! exec 9>"$lock_file"; then
    echo "plane-pr-sync: WARN failed to open lock file; continuing without concurrency lock" >&2
    return 0
  fi
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

forgejo_trusted_authors_json() {
  jq -Rn --arg authors "${WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS:-}" '
    $authors
    | split(",")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))
  '
}

forgejo_author_allowlist_was_set() {
  [[ -n "${WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS+x}" ]]
}

forgejo_require_nonempty_explicit_author_allowlist() {
  local trusted_authors_json="$1" trusted_author_count
  if ! forgejo_author_allowlist_was_set; then
    return 0
  fi
  trusted_author_count="$(jq -r 'length' <<<"$trusted_authors_json")"
  if [[ "$trusted_author_count" -eq 0 ]]; then
    echo "plane-pr-sync: empty WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS allowlist; aborting before Plane state change" >&2
    exit 3
  fi
}

forgejo_comments_have_marker() {
  local comments_json="$1" marker="$2" trusted_authors_json="$3"
  jq -e --arg marker "$marker" --argjson trusted_authors "$trusted_authors_json" '
    def comment_author:
      .user.login? //
      .author.login? //
      .author.username? //
      .poster.login? //
      .poster.username? //
      .username? //
      .user? //
      .author? //
      empty;
    def trusted_comment:
      ($trusted_authors | length) == 0 or
      ((comment_author | strings) as $login | ($trusted_authors | index($login)));
    def comment_bodies:
      if type == "array" then
        .[]?
      elif type == "object" then
        .comments[]?, .Comments[]?
      else
        empty
      end
      | select(trusted_comment)
      | (.body? // .Body? // empty);
    [comment_bodies | strings | select(contains($marker))] | length > 0
  ' >/dev/null <<<"$comments_json"
}

forgejo_comments_have_conflicting_plane_marker() {
  local comments_json="$1" marker="$2" trusted_authors_json="$3" expected_issue
  expected_issue="${marker#\[walter-plane-issue:}"
  expected_issue="${expected_issue%\]}"
  jq -e --arg expected_issue "$expected_issue" --argjson trusted_authors "$trusted_authors_json" '
    def comment_author:
      .user.login? //
      .author.login? //
      .author.username? //
      .poster.login? //
      .poster.username? //
      .username? //
      .user? //
      .author? //
      empty;
    def trusted_comment:
      ($trusted_authors | length) == 0 or
      ((comment_author | strings) as $login | ($trusted_authors | index($login)));
    def comment_bodies:
      if type == "array" then
        .[]?
      elif type == "object" then
        .comments[]?, .Comments[]?
      else
        empty
      end
      | select(trusted_comment)
      | (.body? // .Body? // empty);
    [
      comment_bodies
      | strings
      | scan("\\[walter-plane-issue:([^]\\r\\n\\]]+)\\]")
      | .[0]
    ]
    | unique
    | map(select(. != $expected_issue))
    | length > 0
  ' >/dev/null <<<"$comments_json"
}

forgejo_comment_once() {
  local marker="$1" body="$2" mode="${3:-optional}" existing trusted_authors_json trusted_author_count jq_status
  if ! command -v tea >/dev/null 2>&1; then
    if [[ "$mode" == "required" ]]; then
      echo "plane-pr-sync: tea is required to persist the Forgejo PR marker" >&2
      exit 3
    fi
    echo "plane-pr-sync: WARN tea not found; skipped Forgejo PR comment" >&2
    return 0
  fi
  if existing="$(tea issues view "$pr_number" --repo "$repo" --comments --output json 2>/dev/null)"; then
    trusted_authors_json="$(forgejo_trusted_authors_json)"
    if [[ "$mode" == "required" ]]; then
      forgejo_require_nonempty_explicit_author_allowlist "$trusted_authors_json"
    fi
    if [[ "$mode" == "required" && "$marker" == \[walter-plane-issue:* ]]; then
      if forgejo_comments_have_conflicting_plane_marker "$existing" "$marker" "$trusted_authors_json"; then
        echo "plane-pr-sync: conflicting walter-plane-issue marker already exists; aborting before Plane state change" >&2
        exit 3
      else
        jq_status=$?
      fi
      if [[ "$jq_status" -gt 1 ]]; then
        echo "plane-pr-sync: failed to parse Forgejo PR comments before marker persistence" >&2
        exit 3
      fi
    fi
    if forgejo_comments_have_marker "$existing" "$marker" "$trusted_authors_json"; then
      return 0
    else
      jq_status=$?
    fi
    if [[ "$jq_status" -gt 1 ]]; then
      if [[ "$mode" == "required" ]]; then
        echo "plane-pr-sync: failed to parse Forgejo PR comments before marker persistence" >&2
        exit 3
      fi
      echo "plane-pr-sync: WARN could not parse Forgejo PR comments; attempting comment" >&2
    fi
  else
    if [[ "$mode" == "required" ]]; then
      echo "plane-pr-sync: failed to inspect Forgejo PR comments before marker persistence" >&2
      exit 3
    fi
    echo "plane-pr-sync: WARN could not inspect Forgejo PR comments; attempting comment" >&2
  fi
  if ! tea issues comment "$pr_number" --repo "$repo" --comment "$body" >/dev/null 2>&1; then
    if [[ "$mode" == "required" ]]; then
      echo "plane-pr-sync: Forgejo PR marker comment failed; aborting before Plane state change" >&2
      exit 3
    fi
    echo "plane-pr-sync: WARN Forgejo PR comment failed; continuing" >&2
  fi
  if [[ "$mode" != "required" ]]; then
    return 0
  fi
  trusted_author_count="$(jq -r 'length' <<<"$trusted_authors_json")"
  if existing="$(tea issues view "$pr_number" --repo "$repo" --comments --output json 2>/dev/null)"; then
    if [[ "$marker" == \[walter-plane-issue:* ]]; then
      if forgejo_comments_have_conflicting_plane_marker "$existing" "$marker" "$trusted_authors_json"; then
        echo "plane-pr-sync: conflicting walter-plane-issue marker exists after marker persistence" >&2
        exit 3
      else
        jq_status=$?
      fi
      if [[ "$jq_status" -gt 1 ]]; then
        echo "plane-pr-sync: failed to parse Forgejo PR comments after marker persistence" >&2
        exit 3
      fi
    fi
    if forgejo_comments_have_marker "$existing" "$marker" "$trusted_authors_json"; then
      return 0
    else
      jq_status=$?
    fi
    if [[ "$jq_status" -gt 1 ]]; then
      echo "plane-pr-sync: failed to parse Forgejo PR comments after marker persistence" >&2
      exit 3
    fi
    if [[ "$trusted_author_count" -gt 0 ]]; then
      echo "plane-pr-sync: Forgejo PR marker comment is not trusted; aborting before Plane state change" >&2
    else
      echo "plane-pr-sync: Forgejo PR marker comment was not persisted; aborting before Plane state change" >&2
    fi
    exit 3
  fi
  echo "plane-pr-sync: failed to verify Forgejo PR marker after persistence" >&2
  exit 3
}

short_sha() {
  printf '%s\n' "$1" | cut -c1-12
}

marker="[walter-pr-sync:${repo}#${pr_number}:${event}]"

case "$event" in
  link)
    comment="${marker} [walter-plane-issue:${issue}] PR linked: ${pr_url} (branch: ${branch}). Requesting Plane issue move to review."
    issue_marker="[walter-plane-issue:${issue}]"
    forgejo_comment_once "$issue_marker" "$comment" "required"
    plane_comment_once "$marker" "$comment"
    plane_issue_set_state "$issue" "review"
    ;;
  merged)
    comment="${marker} [walter-plane-issue:${issue}] PR merged: ${pr_url} at $(short_sha "$merge_sha"). Requesting Plane issue move to done."
    plane_comment_once "$marker" "$comment"
    plane_issue_set_state "$issue" "done"
    forgejo_comment_once "$marker" "$comment"
    ;;
esac

echo "plane-pr-sync: ${event} synced for ${repo}#${pr_number} -> Plane ${issue}"
