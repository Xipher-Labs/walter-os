#!/usr/bin/env bash
# scripts/walter/subcommands/pr-score.sh
# Score PR readiness from observable GitHub evidence.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

usage() {
  cat <<'EOF'
Usage: walter-os pr-score [PR] [--json] [--fixture <path>]

Scores a pull request from checks, reviews, title format, issue linkage,
verification notes, and sensitive path risk.

Decisions:
  block              Failing checks, invalid title, or low score.
  human-review       Clean enough to inspect, but not policy-auto-merge safe.
  policy-auto-merge  Clean, low-risk PR with score >= 90.

Options:
  --json             Print machine-readable JSON.
  --fixture <path>   Read PR evidence JSON from a file for tests/local audits.
EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "walter-os pr-score: jq is required" >&2
    exit 3
  fi
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "walter-os pr-score: gh is required unless --fixture is used" >&2
    exit 3
  fi
}

title_is_valid() {
  local candidate="$1"
  local validator="${WALTER_OS_HOME}/hooks/pr-title-validator.sh"
  if [[ -x "$validator" ]]; then
    "$validator" "$candidate" >/dev/null 2>&1
    return $?
  fi

  local title_regex
  title_regex='^\[(FEAT|FIX|DOCS|CHORE|TEST)\] -(SECURITY|BUSINESS|COMPLIANCE|OPERATIONS|TECHNICAL|CUSTOMER|CONTENT|LEARNING)- [^[:space:]].{0,58}[^[:space:].]$'
  grep -qE "$title_regex" <<<"$candidate"
}

json_output=0
fixture=""
pr_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_output=1
      shift
      ;;
    --fixture)
      fixture="${2:-}"
      if [[ -z "$fixture" ]]; then
        echo "walter-os pr-score: --fixture requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    -*)
      echo "walter-os pr-score: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$pr_ref" ]]; then
        echo "walter-os pr-score: only one PR reference is supported" >&2
        exit 2
      fi
      pr_ref="$1"
      shift
      ;;
  esac
done

if [[ -n "$fixture" && -n "$pr_ref" ]]; then
  echo "walter-os pr-score: PR reference cannot be combined with --fixture" >&2
  exit 2
fi

require_jq

fetch_pr_json() {
  require_gh

  local view_args=()
  if [[ -n "$pr_ref" ]]; then
    view_args+=("$pr_ref")
  fi

  local pr_json repo_json owner repo number threads_json
  if ! pr_json="$(gh pr view "${view_args[@]}" \
      --json number,title,body,mergeable,reviewRequests,statusCheckRollup,files)"; then
    echo "walter-os pr-score: failed to read PR data with gh" >&2
    exit 3
  fi
  number="$(printf '%s\n' "$pr_json" | jq -r '.number')"
  if ! repo_json="$(gh repo view --json owner,name)"; then
    echo "walter-os pr-score: failed to read repository data with gh" >&2
    exit 3
  fi
  owner="$(printf '%s\n' "$repo_json" | jq -r '.owner.login')"
  repo="$(printf '%s\n' "$repo_json" | jq -r '.name')"

  # shellcheck disable=SC2016 # GraphQL variables are intentionally literal.
  if ! threads_json="$(gh api graphql \
    -f owner="$owner" \
    -f repo="$repo" \
    -F number="$number" \
    -f query='query($owner:String!, $repo:String!, $number:Int!) {
      repository(owner:$owner, name:$repo) {
        pullRequest(number:$number) {
          reviewThreads(first:100) {
            totalCount
            nodes { isResolved isOutdated }
          }
        }
      }
    }' \
      --jq '.data.repository.pullRequest.reviewThreads')"; then
    echo "walter-os pr-score: failed to read PR review threads with gh" >&2
    exit 3
  fi

  jq -c \
    --argjson threads "$threads_json" \
    '. + {
      reviewThreads: ($threads.nodes // []),
      reviewThreadsTotalCount: ($threads.totalCount // ($threads.nodes // [] | length))
    }' <<<"$pr_json"
}

if [[ -n "$fixture" ]]; then
  if [[ ! -r "$fixture" ]]; then
    echo "walter-os pr-score: fixture is not readable: $fixture" >&2
    exit 2
  fi
  pr_json="$(cat "$fixture")"
else
  pr_json="$(fetch_pr_json)"
fi

findings_json='[]'
add_finding() {
  findings_json="$(jq -c --arg msg "$1" '. + [$msg]' <<<"$findings_json")"
}

title="$(jq -r '.title // ""' <<<"$pr_json")"
body="$(jq -r '.body // ""' <<<"$pr_json")"
mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr_json")"

checks_total="$(jq '[.statusCheckRollup[]?] | length' <<<"$pr_json")"
checks_failed="$(jq '[.statusCheckRollup[]? | select((.status // "") == "COMPLETED") | select((.conclusion // "") != "") | select((.conclusion // "") != "SUCCESS" and (.conclusion // "") != "SKIPPED" and (.conclusion // "") != "NEUTRAL")] | length' <<<"$pr_json")"
checks_pending="$(jq '[.statusCheckRollup[]? | select((.status // "") != "COMPLETED" or (.conclusion // "") == "")] | length' <<<"$pr_json")"

checks_points=0
if [[ "$checks_failed" -gt 0 ]]; then
  add_finding "failing checks: $checks_failed"
elif [[ "$checks_pending" -gt 0 ]]; then
  checks_points=15
  add_finding "pending checks: $checks_pending"
elif [[ "$checks_total" -eq 0 ]]; then
  checks_points=10
  add_finding "no status checks found"
else
  checks_points=30
fi

unresolved_threads="$(jq '[.reviewThreads[]? | select(.isResolved != true and (.isOutdated != true))] | length' <<<"$pr_json")"
review_threads_fetched="$(jq '[.reviewThreads[]?] | length' <<<"$pr_json")"
review_threads_total="$(jq '.reviewThreadsTotalCount // ([.reviewThreads[]?] | length)' <<<"$pr_json")"
review_requests="$(jq '[.reviewRequests[]?] | length' <<<"$pr_json")"
review_points=20
if [[ "$review_threads_total" -gt "$review_threads_fetched" ]]; then
  review_points=10
  add_finding "review thread page incomplete: fetched $review_threads_fetched of $review_threads_total"
elif [[ "$unresolved_threads" -gt 0 ]]; then
  review_points=0
  add_finding "unresolved review threads: $unresolved_threads"
elif [[ "$review_requests" -gt 0 ]]; then
  review_points=10
  add_finding "pending review requests: $review_requests"
fi

case "$mergeable" in
  MERGEABLE)
    ;;
  CONFLICTING)
    add_finding "PR is not mergeable: conflicts must be resolved"
    ;;
  *)
    add_finding "PR mergeability is unknown"
    ;;
esac

title_points=0
title_ok=0
if title_is_valid "$title"; then
  title_ok=1
  title_points=10
fi
if [[ "$title_ok" -eq 0 ]]; then
  add_finding "title does not match Walter-OS convention"
fi

link_points=0
if grep -Eiq '(Closes|Fixes|Resolves|Refs):?[[:space:]]+#?[0-9]+' <<<"$body"; then
  link_points=10
else
  add_finding "missing issue reference in PR body"
fi

verification_points=0
if grep -Eiq '(Verification|Test plan)' <<<"$body" \
    && grep -Eiq '(bats|shellcheck|pytest|pnpm|npm|git diff --check|cargo test|go test)' <<<"$body"; then
  verification_points=10
else
  add_finding "missing concrete verification evidence"
fi

sensitive_count=0
sensitive_paths=""
file_paths="$(jq -r '.files[]?.path // empty' <<<"$pr_json")"
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  case "$path" in
    .github/workflows/*|hooks/*|AGENTS.md|*/AGENTS.md|install.sh|mcp/servers.json|auth/*|crypto/*|*.env|*.pem|*.key|*migration*)
      sensitive_count=$((sensitive_count + 1))
      sensitive_paths="${sensitive_paths}${sensitive_paths:+, }${path}"
      ;;
  esac
done <<<"$file_paths"

risk_points=20
if [[ "$sensitive_count" -gt 0 ]]; then
  risk_points=10
  add_finding "sensitive path changes require human review: $sensitive_paths"
fi

score=$((checks_points + review_points + title_points + link_points + verification_points + risk_points))

decision="human-review"
exit_code=0
if [[ "$checks_failed" -gt 0 || "$title_ok" -eq 0 || "$mergeable" == "CONFLICTING" || "$score" -lt 70 ]]; then
  decision="block"
  exit_code=1
elif [[ "$checks_pending" -eq 0 && "$unresolved_threads" -eq 0 && "$review_requests" -eq 0 && "$review_threads_total" -le "$review_threads_fetched" && "$mergeable" == "MERGEABLE" && "$sensitive_count" -eq 0 && "$score" -ge 90 ]]; then
  decision="policy-auto-merge"
fi

components_json="$(jq -nc \
  --argjson checks "$checks_points" \
  --argjson reviews "$review_points" \
  --argjson title "$title_points" \
  --argjson links "$link_points" \
  --argjson verification "$verification_points" \
  --argjson risk "$risk_points" \
  '{
    checks: {points: $checks, max: 30},
    reviews: {points: $reviews, max: 20},
    title: {points: $title, max: 10},
    issue_links: {points: $links, max: 10},
    verification: {points: $verification, max: 10},
    risk: {points: $risk, max: 20}
  }')"

if [[ "$json_output" -eq 1 ]]; then
  jq -nc \
    --argjson score "$score" \
    --arg decision "$decision" \
    --arg title "$title" \
    --argjson components "$components_json" \
    --argjson findings "$findings_json" \
    '{score: $score, decision: $decision, title: $title, components: $components, findings: $findings}'
  exit "$exit_code"
fi

printf 'Walter Score: %s/100\n' "$score"
printf 'Decision: %s\n' "$decision"
printf '\nComponents:\n'
jq -r 'to_entries[] | "  \(.key): \(.value.points)/\(.value.max)"' <<<"$components_json"
printf '\nFindings:\n'
if [[ "$(jq 'length' <<<"$findings_json")" -eq 0 ]]; then
  printf '  none\n'
else
  jq -r '.[] | "  - \(.)"' <<<"$findings_json"
fi

exit "$exit_code"
