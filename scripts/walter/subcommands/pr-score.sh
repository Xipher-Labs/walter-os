#!/usr/bin/env bash
# scripts/walter/subcommands/pr-score.sh
# Score PR readiness from observable GitHub evidence.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
PROTECTED_PATHS_LIB="${WALTER_OS_HOME}/scripts/walter/lib/protected-paths.sh"

if [[ -f "$PROTECTED_PATHS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$PROTECTED_PATHS_LIB"
else
  declare -a WALTER_PROTECTED_PATH_PATTERNS=(
    '.github/workflows/*'
    'hooks/*'
    'AGENTS.md'
    'install.sh'
    'mcp/servers.json'
    'auth/*'
    'crypto/*'
    '*.env'
    '*.pem'
    '*.key'
    '*migration*'
  )
fi

usage() {
  cat <<'EOF'
Usage: walter-os pr-score [PR] [--json] [--fixture <path>] [--preview-plan <path>] [--preview-report <path>]

Scores a pull request from checks, reviews, title format, issue linkage,
verification notes, sensitive path risk, and optional preview evidence.

Decisions:
  block              Failing checks, invalid title, or low score.
  human-review       Clean enough to inspect, but not policy-auto-merge safe.
  policy-auto-merge  Clean, low-risk PR with score >= 90.

Options:
  --json             Print machine-readable JSON.
  --fixture <path>   Read PR evidence JSON from a file for tests/local audits.
  --preview-plan <path>
                     Read preview-plan.json evidence.
  --preview-report <path>
                     Read preview-report.json evidence.
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

is_protected_path() {
  local path="$1" pattern
  for pattern in "${WALTER_PROTECTED_PATH_PATTERNS[@]}"; do
    # shellcheck disable=SC2053 # Protected path patterns are glob expressions.
    if [[ "$path" == $pattern ]]; then
      return 0
    fi
  done
  return 1
}

title_is_valid() {
  local candidate="$1"
  local validator="${WALTER_OS_HOME}/hooks/pr-title-validator.sh"
  if [[ -x "$validator" ]]; then
    if "$validator" "$candidate" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi

  local title_regex
  title_regex='^\[(FEAT|FIX|DOCS|CHORE|TEST)\] -(SECURITY|BUSINESS|COMPLIANCE|OPERATIONS|TECHNICAL|CUSTOMER|CONTENT|LEARNING)- [^[:space:]].{0,58}[^[:space:].]$'
  grep -qE "$title_regex" <<<"$candidate"
}

json_output=0
fixture=""
pr_ref=""
preview_plan_path=""
preview_report_path=""

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
    --preview-plan)
      preview_plan_path="${2:-}"
      if [[ -z "$preview_plan_path" ]]; then
        echo "walter-os pr-score: --preview-plan requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --preview-report)
      preview_report_path="${2:-}"
      if [[ -z "$preview_report_path" ]]; then
        echo "walter-os pr-score: --preview-report requires a path" >&2
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

read_json_evidence() {
  local label="$1" path="$2"
  if [[ -L "$path" ]]; then
    echo "walter-os pr-score: ${label} is a symlink: $path" >&2
    exit 2
  fi
  if [[ ! -f "$path" || ! -r "$path" ]]; then
    echo "walter-os pr-score: ${label} is not readable: $path" >&2
    exit 2
  fi
  if ! jq -c '.' < "$path"; then
    echo "walter-os pr-score: ${label} is not valid JSON: $path" >&2
    exit 2
  fi
}

preview_report_status() {
  local payload="$1" expected_pr="$2"
  jq -nc --argjson report "$payload" --argjson expected_pr "$expected_pr" '
    def sha256_ok: type == "string" and test("^[A-Fa-f0-9]{64}$");
    ($report | if type == "object" then . else {} end) as $r |
    ($r.seed_manifest | if type == "object" then . else {} end) as $seed |
    ($r.screenshots | if type == "array" then . else [] end) as $screenshots |
    ($r.safety | if type == "object" then . else {} end) as $safety |
    {
      provided: true,
      valid: (
        ($r.schema_version == 1) and
        ($r.pr == $expected_pr) and
        (($r.url // "") | type == "string" and test("^https?://")) and
        (($seed.sha256 // "") | sha256_ok) and
        ($screenshots | length > 0) and
        ([$screenshots[] | select(((if type == "object" then (.sha256 // "") else "" end) | sha256_ok) | not)] | length == 0) and
        ($safety.production_secrets == "rejected") and
        ($safety.credentials == "not minted") and
        ($safety.deploy == "not performed") and
        ($safety.hard_limit_floor == "preserved")
      )
    }'
}

preview_plan_status() {
  local payload="$1" expected_pr="$2"
  jq -nc --argjson plan "$payload" --argjson expected_pr "$expected_pr" '
    def sha256_ok: type == "string" and test("^[A-Fa-f0-9]{64}$");
    ($plan | if type == "object" then . else {} end) as $p |
    ($p.seed_manifest | if type == "object" then . else {} end) as $seed |
    ($p.actions | if type == "array" then . else [] end) as $actions |
    ($p.safety | if type == "object" then . else {} end) as $safety |
    {
      provided: true,
      valid: (
        ($p.schema_version == 1) and
        ($p.kind == "preview-plan") and
        ($p.pr == $expected_pr) and
        (($p.provider // "") | type == "string" and length > 0) and
        (($p.app // "") | type == "string" and length > 0) and
        (($p.branch // "") | type == "string" and length > 0) and
        (($seed.sha256 // "") | sha256_ok) and
        ($actions | index("deploy_ephemeral_preview") != null) and
        ($actions | index("apply_seed_fixture") != null) and
        ($actions | index("capture_screenshots") != null) and
        ($actions | index("write_preview_bundle") != null) and
        ($safety.dry_run == true) and
        ($safety.preview_deploy == true) and
        ($safety.production_secrets == "rejected") and
        ($safety.credentials == "not minted") and
        ($safety.deploy == "not performed") and
        ($safety.hard_limit_floor == "preserved")
      )
    }'
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
if grep -Eiq '(^|[^[:alnum:]_])(Closes|Fixes|Resolves|Refs):?[[:space:]]+#?[0-9]+' <<<"$body"; then
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
  if is_protected_path "$path"; then
    sensitive_count=$((sensitive_count + 1))
    sensitive_paths="${sensitive_paths}${sensitive_paths:+, }${path}"
  fi
done <<<"$file_paths"

risk_points=10
if [[ "$sensitive_count" -gt 0 ]]; then
  risk_points=0
  add_finding "sensitive path changes require human review: $sensitive_paths"
fi

preview_points=0
preview_invalid=0
preview_incomplete=0
preview_plan_status_json='{"provided":false,"valid":null}'
preview_report_status_json='{"provided":false,"valid":null}'

if [[ -n "$preview_plan_path" ]]; then
  preview_plan_json="$(read_json_evidence "preview plan" "$preview_plan_path")"
  preview_plan_status_json="$(preview_plan_status "$preview_plan_json" "$(jq -r '.number // 0' <<<"$pr_json")")"
  if [[ "$(jq -r '.valid' <<<"$preview_plan_status_json")" != "true" ]]; then
    preview_invalid=1
    add_finding "invalid preview plan"
  fi
fi

if [[ -n "$preview_report_path" ]]; then
  preview_report_json="$(read_json_evidence "preview report" "$preview_report_path")"
  preview_report_status_json="$(preview_report_status "$preview_report_json" "$(jq -r '.number // 0' <<<"$pr_json")")"
  if [[ "$(jq -r '.valid' <<<"$preview_report_status_json")" != "true" ]]; then
    preview_invalid=1
    add_finding "invalid preview report"
  fi
fi

if [[ "$(jq -r '.valid' <<<"$preview_report_status_json")" == "true" ]]; then
  preview_points=10
elif [[ "$(jq -r '.valid' <<<"$preview_plan_status_json")" == "true" ]]; then
  preview_points=5
  preview_incomplete=1
  add_finding "preview report missing for preview plan"
fi

preview_json="$(jq -nc \
  --argjson plan "$preview_plan_status_json" \
  --argjson report "$preview_report_status_json" \
  '{plan: $plan, report: $report}')"

score=$((checks_points + review_points + title_points + link_points + verification_points + risk_points))
score=$((score + preview_points))

decision="human-review"
exit_code=0
if [[ "$preview_invalid" -eq 1 || "$checks_failed" -gt 0 || "$title_ok" -eq 0 || "$mergeable" == "CONFLICTING" || "$score" -lt 70 ]]; then
  decision="block"
  exit_code=1
elif [[ "$preview_incomplete" -eq 0 && "$checks_pending" -eq 0 && "$unresolved_threads" -eq 0 && "$review_requests" -eq 0 && "$review_threads_total" -le "$review_threads_fetched" && "$mergeable" == "MERGEABLE" && "$sensitive_count" -eq 0 && "$score" -ge 90 ]]; then
  decision="policy-auto-merge"
fi

components_json="$(jq -nc \
  --argjson checks "$checks_points" \
  --argjson reviews "$review_points" \
  --argjson title "$title_points" \
  --argjson links "$link_points" \
  --argjson verification "$verification_points" \
  --argjson risk "$risk_points" \
  --argjson preview "$preview_points" \
  '{
    checks: {points: $checks, max: 30},
    reviews: {points: $reviews, max: 20},
    title: {points: $title, max: 10},
    issue_links: {points: $links, max: 10},
    verification: {points: $verification, max: 10},
    risk: {points: $risk, max: 10},
    preview: {points: $preview, max: 10}
  }')"

if [[ "$json_output" -eq 1 ]]; then
  jq -nc \
    --argjson score "$score" \
    --arg decision "$decision" \
    --arg title "$title" \
    --argjson components "$components_json" \
    --argjson preview "$preview_json" \
    --argjson findings "$findings_json" \
    '{score: $score, decision: $decision, title: $title, components: $components, preview: $preview, findings: $findings}'
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
