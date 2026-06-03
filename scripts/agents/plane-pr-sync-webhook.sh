#!/usr/bin/env bash
# scripts/agents/plane-pr-sync-webhook.sh
# Verify a signed Forgejo/Gitea PR webhook before syncing Plane state.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SYNC_SCRIPT="${WALTER_PLANE_PR_SYNC_SCRIPT:-${WALTER_OS_HOME}/scripts/agents/plane-pr-sync.sh}"

usage() {
  cat <<'EOF'
Usage:
  plane-pr-sync-webhook.sh --event pull_request --signature <hex|sha256=hex> --payload-file <path|-> [--comments-file <path|->] [--secret-env <name>]

Verifies a Forgejo/Gitea pull_request webhook signature, resolves exactly one
walter-plane-issue:<id> marker from Forgejo PR comments, and calls
plane-pr-sync.sh for closed merged PRs.

This script is a CLI adapter for n8n or another webhook entrypoint. It is not an
HTTP server. The caller must pass the original raw request body, not
re-serialized JSON.

Headers:
  --event      Value from X-Gitea-Event / X-Forgejo-Event.
  --signature Value from X-Gitea-Signature / X-Forgejo-Signature.

Secret:
  Defaults to WALTER_FORGEJO_WEBHOOK_SECRET. Use --secret-env to point at a
  different environment variable. Do not pass secrets on argv.

Trust boundary:
  WALTER_FORGEJO_WEBHOOK_REPOS must list accepted owner/repo names.
  WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS must list trusted comment author
  logins whose walter-plane-issue markers may bind Plane issues.
EOF
}

fail_usage() {
  echo "plane-pr-sync-webhook: $1" >&2
  exit 2
}

fail_runtime() {
  echo "plane-pr-sync-webhook: $1" >&2
  exit 3
}

require_option_value() {
  local flag="$1" value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    fail_usage "missing value for $flag"
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail_runtime "$command_name is required"
  fi
}

reject_control() {
  local name="$1" value="$2" control_status
  set +e
  CONTROL_VALUE="$value" python3 -c 'import os, sys; value = os.environ.get("CONTROL_VALUE", ""); sys.exit(42 if any(ord(char) < 32 or ord(char) == 127 for char in value) else 0)'
  control_status=$?
  set -e
  if [[ "$control_status" -eq 42 ]]; then
    fail_usage "$name contains control characters"
  fi
  if [[ "$control_status" -ne 0 ]]; then
    fail_runtime "control-character validation failed"
  fi
}

trim_ascii_space() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

require_value() {
  local name="$1" value="$2"
  if [[ -z "$value" ]]; then
    fail_usage "missing $name"
  fi
}

event="${FORGEJO_EVENT:-${GITEA_EVENT:-}}"
signature="${FORGEJO_SIGNATURE:-${GITEA_SIGNATURE:-}}"
payload_file=""
comments_file=""
secret_env="WALTER_FORGEJO_WEBHOOK_SECRET"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event) require_option_value "$1" "${2:-}"; event="$2"; shift 2 ;;
    --signature) require_option_value "$1" "${2:-}"; signature="$2"; shift 2 ;;
    --payload-file) require_option_value "$1" "${2:-}"; payload_file="$2"; shift 2 ;;
    --comments-file) require_option_value "$1" "${2:-}"; comments_file="$2"; shift 2 ;;
    --secret-env) require_option_value "$1" "${2:-}"; secret_env="$2"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "plane-pr-sync-webhook: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

require_value "--event" "$event"
require_value "--signature" "$signature"
require_command python3
reject_control "event" "$event"
reject_control "signature" "$signature"
reject_control "secret-env" "$secret_env"

if [[ "$comments_file" == "-" && ( "$payload_file" == "-" || -z "$payload_file" ) ]]; then
  fail_usage "--comments-file - cannot be used when payload is read from stdin"
fi

if [[ "$event" != "pull_request" ]]; then
  fail_usage "unsupported event: $event"
fi

require_command jq

if [[ ! -f "$SYNC_SCRIPT" ]]; then
  fail_runtime "missing sync primitive: $SYNC_SCRIPT"
fi

cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]}"; do
    rm -f "$path"
  done
}
trap cleanup EXIT

materialize_payload() {
  local tmp_payload
  if [[ -n "$payload_file" ]]; then
    if [[ "$payload_file" == "-" ]]; then
      tmp_payload="$(mktemp "${TMPDIR:-/tmp}/walter-forgejo-payload.XXXXXX")"
      cleanup_paths+=("$tmp_payload")
      cat > "$tmp_payload"
      printf '%s\n' "$tmp_payload"
      return 0
    fi
    if [[ ! -r "$payload_file" || ! -f "$payload_file" ]]; then
      fail_usage "payload file is not readable: $payload_file"
    fi
    printf '%s\n' "$payload_file"
    return 0
  fi

  if [[ -t 0 ]]; then
    fail_usage "missing --payload-file or stdin payload"
  fi
  tmp_payload="$(mktemp "${TMPDIR:-/tmp}/walter-forgejo-payload.XXXXXX")"
  cleanup_paths+=("$tmp_payload")
  cat > "$tmp_payload"
  printf '%s\n' "$tmp_payload"
}

payload_path="$(materialize_payload)"

verify_signature() {
  local normalized_signature="$signature" status
  case "$normalized_signature" in
    sha256=*) normalized_signature="${normalized_signature#sha256=}" ;;
  esac

  set +e
  WEBHOOK_SECRET_ENV="$secret_env" \
    WEBHOOK_SIGNATURE="$normalized_signature" \
    WEBHOOK_PAYLOAD_FILE="$payload_path" \
    python3 -c '
import hashlib
import hmac
import os
import re
import sys

secret_env = os.environ["WEBHOOK_SECRET_ENV"]
secret = os.environ.get(secret_env, "")
signature = os.environ["WEBHOOK_SIGNATURE"]
payload_file = os.environ["WEBHOOK_PAYLOAD_FILE"]

if not secret:
    print(f"plane-pr-sync-webhook: missing secret env: {secret_env}", file=sys.stderr)
    sys.exit(3)
if not re.fullmatch(r"[0-9a-fA-F]{64}", signature):
    print("plane-pr-sync-webhook: malformed webhook signature", file=sys.stderr)
    sys.exit(2)

with open(payload_file, "rb") as handle:
    payload = handle.read()

expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
if not hmac.compare_digest(expected.lower(), signature.lower()):
    print("plane-pr-sync-webhook: invalid webhook signature", file=sys.stderr)
    sys.exit(4)
'
  status=$?
  set -e

  case "$status" in
    0) return 0 ;;
    2) exit 2 ;;
    3) exit 3 ;;
    4) exit 4 ;;
    *) fail_runtime "signature verification failed unexpectedly" ;;
  esac
}

verify_signature

if ! jq -e . >/dev/null 2>&1 < "$payload_path"; then
  fail_usage "payload is not valid JSON"
fi

jq_string() {
  local name="$1" expr="$2" value
  value="$(jq -er "$expr // empty" "$payload_path" 2>/dev/null || true)"
  require_value "$name" "$value"
  reject_control "$name" "$value"
  printf '%s\n' "$value"
}

action="$(jq_string "action" '.action')"

if [[ "$action" != "closed" ]]; then
  echo "plane-pr-sync-webhook: no sync action for pull_request action: $action"
  exit 0
fi

merged="$(jq -r '(.pull_request.merged // false) | tostring' "$payload_path")"
reject_control "pull_request.merged" "$merged"
if [[ "$merged" != "true" ]]; then
  echo "plane-pr-sync-webhook: no sync action for closed unmerged PR"
  exit 0
fi

repo="$(jq_string "repo" '.repository.full_name')"
pr_url="$(jq_string "pr-url" '.pull_request.html_url // .pull_request.url')"
pr_number="$(jq_string "pr-number" '.pull_request.number | tostring')"
branch="$(jq_string "branch" '.pull_request.head.ref')"
merge_sha="$(jq_string "merge sha" '.pull_request.merged_commit_sha // .pull_request.merge_commit_sha // .after')"

if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
  fail_usage "pull_request.number must be numeric"
fi

if [[ -z "${WALTER_FORGEJO_WEBHOOK_REPOS:-}" ]]; then
  fail_usage "missing WALTER_FORGEJO_WEBHOOK_REPOS allowlist"
fi

reject_control "repo allowlist" "$WALTER_FORGEJO_WEBHOOK_REPOS"
repo_allowed=0
IFS=',' read -r -a allowed_repos <<<"$WALTER_FORGEJO_WEBHOOK_REPOS"
for allowed_repo in "${allowed_repos[@]}"; do
  allowed_repo="$(trim_ascii_space "$allowed_repo")"
  if [[ -z "$allowed_repo" ]]; then
    continue
  fi
  if [[ "$repo" == "$allowed_repo" ]]; then
    repo_allowed=1
    break
  fi
done
if [[ "$repo_allowed" -ne 1 ]]; then
  fail_usage "repo is not allowlisted: $repo"
fi

if [[ -z "${WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS:-}" ]]; then
  fail_usage "missing WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS allowlist"
fi

reject_control "comment author allowlist" "$WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS"
trusted_authors_json="$(
  jq -Rn --arg authors "$WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS" '
    $authors
    | split(",")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))
  '
)"
trusted_author_count="$(jq -r 'length' <<<"$trusted_authors_json")"
if [[ "$trusted_author_count" -eq 0 ]]; then
  fail_usage "empty WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS allowlist"
fi

read_comments_json() {
  if [[ -n "$comments_file" ]]; then
    if [[ "$comments_file" == "-" ]]; then
      cat
      return 0
    fi
    if [[ ! -r "$comments_file" || ! -f "$comments_file" ]]; then
      fail_usage "comments file is not readable: $comments_file"
    fi
    cat "$comments_file"
    return 0
  fi

  require_command tea
  if ! tea issues view "$pr_number" --repo "$repo" --comments --output json; then
    fail_runtime "failed to fetch Forgejo PR comments"
  fi
}

comments_json="$(read_comments_json)"
if ! jq -e . >/dev/null 2>&1 <<<"$comments_json"; then
  fail_runtime "Forgejo comments output is not valid JSON"
fi

markers_json="$(
  TRUSTED_COMMENT_AUTHORS="$trusted_authors_json" jq -c '
    ($ENV.TRUSTED_COMMENT_AUTHORS | fromjson) as $trusted_authors |
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
    def trusted_comment_bodies:
      if type == "array" then
        .[]?
      elif type == "object" then
        .comments[]?, .Comments[]?
      else
        empty
      end
      | select((comment_author | strings) as $login | ($trusted_authors | index($login)))
      | (.body? // .Body? // empty);
    [trusted_comment_bodies | strings | scan("\\[walter-plane-issue:([^]\\r\\n\\]]+)\\]") | .[0]]
  ' <<<"$comments_json"
)"
marker_occurrence_count="$(jq -r 'length' <<<"$markers_json")"
if [[ "$marker_occurrence_count" -eq 0 ]]; then
  fail_usage "missing walter-plane-issue marker"
fi
distinct_markers_json="$(jq -c 'unique' <<<"$markers_json")"
distinct_marker_count="$(jq -r 'length' <<<"$distinct_markers_json")"
if [[ "$distinct_marker_count" -gt 1 ]]; then
  fail_usage "ambiguous walter-plane-issue markers"
fi
issue="$(jq -r '.[0]' <<<"$distinct_markers_json")"
reject_control "issue marker" "$issue"

sync_args=(
  merged
  --issue "$issue"
  --pr-url "$pr_url"
  --pr-number "$pr_number"
  --repo "$repo"
  --branch "$branch"
  --merge-sha "$merge_sha"
)

bash "$SYNC_SCRIPT" "${sync_args[@]}"
