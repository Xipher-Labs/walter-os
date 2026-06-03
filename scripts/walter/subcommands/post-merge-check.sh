#!/usr/bin/env bash
# scripts/walter/subcommands/post-merge-check.sh
# Read-only post-merge health classification for the autonomous delivery loop.

set -euo pipefail

RUNTIME_ERROR_EXIT=4
USAGE_ERROR_EXIT=64
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

usage() {
  cat <<'EOF'
Usage: walter-os post-merge-check [--commit <sha>] [--json] [--fixture <path>]
       [--record-feature-state <id>] [--repo <dir>]

Classifies post-merge evidence into one of:
  healthy               All runs green and no high/critical alerts.
  investigate           Pending or failed non-deploy evidence needs follow-up.
  rollback-recommended  High-impact failure or high/critical telemetry alert.
  human-escalation      Fix-attempt cap reached; stop automated looping.

This command is read-only by default. It never opens PRs or reverts commits.
With --record-feature-state, it records the classification in the local
.walter/features/<id>/state.yaml ledger.

Options:
  --commit <sha>                Merge commit to inspect with gh run list.
  --json                        Print machine-readable JSON.
  --fixture <path>              Read post-merge evidence JSON from a file for tests.
  --record-feature-state <id>   Append the decision to a feature-state ledger.
  --repo <dir>                  Repository containing .walter/features/.
EOF
}

runtime_error() {
  echo "walter-os post-merge-check: $1" >&2
  exit "$RUNTIME_ERROR_EXIT"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    runtime_error "jq is required"
  fi
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    runtime_error "gh is required unless --fixture is used"
  fi
}

json_output=0
fixture=""
commit_ref=""
record_feature_id=""
record_repo=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_output=1
      shift
      ;;
    --fixture)
      fixture="${2:-}"
      if [[ -z "$fixture" ]]; then
        echo "walter-os post-merge-check: --fixture requires a path" >&2
        exit "$USAGE_ERROR_EXIT"
      fi
      shift 2
      ;;
    --commit)
      commit_ref="${2:-}"
      if [[ -z "$commit_ref" ]]; then
        echo "walter-os post-merge-check: --commit requires a sha" >&2
        exit "$USAGE_ERROR_EXIT"
      fi
      shift 2
      ;;
    --record-feature-state)
      record_feature_id="${2:-}"
      if [[ -z "$record_feature_id" ]]; then
        echo "walter-os post-merge-check: --record-feature-state requires a feature id" >&2
        exit "$USAGE_ERROR_EXIT"
      fi
      shift 2
      ;;
    --repo)
      record_repo="${2:-}"
      if [[ -z "$record_repo" ]]; then
        echo "walter-os post-merge-check: --repo requires a directory" >&2
        exit "$USAGE_ERROR_EXIT"
      fi
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    -*)
      echo "walter-os post-merge-check: unknown option: $1" >&2
      usage >&2
      exit "$USAGE_ERROR_EXIT"
      ;;
    *)
      echo "walter-os post-merge-check: unexpected argument: $1" >&2
      usage >&2
      exit "$USAGE_ERROR_EXIT"
      ;;
  esac
done

require_jq

if [[ -n "$fixture" && -n "$commit_ref" ]]; then
  echo "walter-os post-merge-check: --fixture cannot be combined with --commit" >&2
  exit "$USAGE_ERROR_EXIT"
fi

if [[ -n "$fixture" ]]; then
  if [[ ! -r "$fixture" ]]; then
    echo "walter-os post-merge-check: fixture is not readable: $fixture" >&2
    exit "$USAGE_ERROR_EXIT"
  fi
  evidence_json="$(cat "$fixture")"
else
  require_gh
  if [[ -z "$commit_ref" ]]; then
    commit_ref="$(git rev-parse HEAD 2>/dev/null || true)"
  fi
  if [[ -z "$commit_ref" ]]; then
    echo "walter-os post-merge-check: --commit is required outside a git repo" >&2
    exit "$USAGE_ERROR_EXIT"
  fi
  gh_error="$(mktemp "${TMPDIR:-/tmp}/walter-post-merge-gh.XXXXXX")"
  if runs_json="$(gh run list --commit "$commit_ref" --limit 30 --json workflowName,status,conclusion,url,createdAt,displayTitle 2>"$gh_error")"; then
    rm -f "$gh_error"
  else
    gh_status=$?
    gh_detail="$(cat "$gh_error" 2>/dev/null || true)"
    rm -f "$gh_error"
    echo "walter-os post-merge-check: unable to inspect GitHub Actions runs for commit $commit_ref (gh exit $gh_status)" >&2
    if [[ -n "$gh_detail" ]]; then
      while IFS= read -r line; do
        printf '  %s\n' "$line" >&2
      done <<<"$gh_detail"
    fi
    exit "$RUNTIME_ERROR_EXIT"
  fi
  if ! evidence_json="$(jq -nc \
    --arg merge_sha "$commit_ref" \
    --argjson runs "$runs_json" \
    '{pr: {merge_sha: $merge_sha}, feature: {fix_attempts: 0, max_fix_attempts: 2}, runs: $runs, alerts: []}')"; then
    runtime_error "unable to build evidence JSON from GitHub Actions runs"
  fi
fi

if ! jq -e . >/dev/null 2>&1 <<<"$evidence_json"; then
  runtime_error "evidence is not valid JSON"
fi

merge_sha="$(jq -r '.pr.merge_sha // empty' <<<"$evidence_json")"

findings_json='[]'
add_finding() {
  findings_json="$(jq -c --arg msg "$1" '. + [$msg]' <<<"$findings_json")"
}

run_filter='
  def lower_or_empty: (. // "") | tostring | ascii_downcase;
  def run_name: (.workflowName // .name // .displayTitle // "unknown");
  def completed: ((.status | lower_or_empty) == "completed");
  def ok_conclusion:
    ((.conclusion | lower_or_empty) == "success")
    or ((.conclusion | lower_or_empty) == "skipped")
    or ((.conclusion | lower_or_empty) == "neutral");
'

runs_total="$(jq '[.runs[]?] | length' <<<"$evidence_json")"
pending_names_json="$(jq -c "${run_filter}"'[.runs[]? | select((completed | not) or ((.conclusion // "") == "")) | run_name]' <<<"$evidence_json")"
failed_names_json="$(jq -c "${run_filter}"'[.runs[]? | select(completed and ((.conclusion // "") != "") and (ok_conclusion | not)) | run_name]' <<<"$evidence_json")"
high_impact_failed_names_json="$(jq -c "${run_filter}"'[.runs[]? | select(completed and ((.conclusion // "") != "") and (ok_conclusion | not)) | select((run_name | test("(deploy|release|migration|production)"; "i"))) | run_name]' <<<"$evidence_json")"
critical_alerts_json="$(jq -c '[.alerts[]? | select(((.severity // "") | tostring | ascii_downcase) == "critical" or ((.severity // "") | tostring | ascii_downcase) == "high") | (.summary // .name // .source // "unnamed alert")]' <<<"$evidence_json")"
pending_names="$(jq -r 'join(", ")' <<<"$pending_names_json")"
failed_names="$(jq -r 'join(", ")' <<<"$failed_names_json")"
high_impact_failed_names="$(jq -r 'join(", ")' <<<"$high_impact_failed_names_json")"
critical_alerts="$(jq -r 'join(", ")' <<<"$critical_alerts_json")"
fix_attempts="$(jq -r '.feature.fix_attempts // 0' <<<"$evidence_json")"
max_fix_attempts="$(jq -r '.feature.max_fix_attempts // 2' <<<"$evidence_json")"

pending_count="$(jq -r 'length' <<<"$pending_names_json")"
failed_count="$(jq -r 'length' <<<"$failed_names_json")"
high_impact_failed_count="$(jq -r 'length' <<<"$high_impact_failed_names_json")"
critical_alert_count="$(jq -r 'length' <<<"$critical_alerts_json")"

decision="healthy"
next_action="no-action"
exit_code=0

if [[ "$runs_total" -eq 0 ]]; then
  add_finding "no post-merge runs found"
  decision="investigate"
  next_action="wait-or-investigate"
  exit_code=1
fi

if [[ "$pending_count" -gt 0 ]]; then
  add_finding "pending runs: $pending_names"
  decision="investigate"
  next_action="wait-or-investigate"
  exit_code=1
fi

if [[ "$failed_count" -gt 0 ]]; then
  add_finding "failed runs: $failed_names"
  decision="investigate"
  next_action="open-fix-pr-candidate"
  exit_code=1
fi

if [[ "$high_impact_failed_count" -gt 0 ]]; then
  add_finding "high-impact failed runs: $high_impact_failed_names"
  decision="rollback-recommended"
  next_action="recommend-rollback"
  exit_code=2
fi

if [[ "$critical_alert_count" -gt 0 ]]; then
  add_finding "critical/high alerts: $critical_alerts"
  decision="rollback-recommended"
  next_action="recommend-rollback"
  exit_code=2
fi

if [[ "$failed_count" -gt 0 && "$fix_attempts" -ge "$max_fix_attempts" ]]; then
  add_finding "max fix attempts reached: ${fix_attempts}/${max_fix_attempts}"
  decision="human-escalation"
  next_action="escalate-human"
  exit_code=3
fi

counts_json="$(jq -nc \
  --argjson runs_total "$runs_total" \
  --argjson pending "$pending_count" \
  --argjson failed "$failed_count" \
  --argjson high_impact_failed "$high_impact_failed_count" \
  --argjson critical_alerts "$critical_alert_count" \
  --argjson fix_attempts "$fix_attempts" \
  --argjson max_fix_attempts "$max_fix_attempts" \
  '{
    runs_total: $runs_total,
    pending_runs: $pending,
    failed_runs: $failed,
    high_impact_failed_runs: $high_impact_failed,
    critical_alerts: $critical_alerts,
    fix_attempts: $fix_attempts,
    max_fix_attempts: $max_fix_attempts
  }')"

signals_json="$(jq -nc \
  --argjson pending_runs "$pending_names_json" \
  --argjson failed_runs "$failed_names_json" \
  --argjson high_impact_failed_runs "$high_impact_failed_names_json" \
  --argjson critical_alerts "$critical_alerts_json" \
  '{
    pending_runs: $pending_runs,
    failed_runs: $failed_runs,
    high_impact_failed_runs: $high_impact_failed_runs,
    critical_alerts: $critical_alerts
  }')"

record_feature_state_if_requested() {
  if [[ -z "$record_feature_id" ]]; then
    return 0
  fi

  if [[ -z "$merge_sha" ]]; then
    runtime_error "unable to record feature state: evidence is missing pr.merge_sha"
  fi

  if [[ ! -f "${WALTER_OS_HOME}/scripts/walter/lib/feature-state.sh" ]]; then
    runtime_error "unable to record feature state: feature-state library not found under WALTER_OS_HOME=${WALTER_OS_HOME}"
  fi

  # shellcheck source=/dev/null
  source "${WALTER_OS_HOME}/scripts/walter/lib/feature-state.sh"

  local repo output status
  repo="$(walter_feature_state_repo_root "$record_repo")"
  if output="$(walter_feature_state_record_post_merge "$repo" "$record_feature_id" "$decision" "$next_action" "$merge_sha" "post-merge-check" 2>&1)"; then
    if [[ "$json_output" -eq 0 && -n "$output" ]]; then
      printf '%s\n' "$output"
    fi
    return 0
  else
    status=$?
  fi

  {
    printf 'walter-os post-merge-check: unable to record feature state'
    printf ' (feature-state exit %s)\n' "$status"
    if [[ -n "$output" ]]; then
      while IFS= read -r line; do
        printf '  %s\n' "$line"
      done <<<"$output"
    fi
  } >&2

  if [[ "$status" -eq "$USAGE_ERROR_EXIT" ]]; then
    exit "$USAGE_ERROR_EXIT"
  fi

  exit "$RUNTIME_ERROR_EXIT"
}

record_feature_state_if_requested

if [[ "$json_output" -eq 1 ]]; then
  jq -nc \
    --arg decision "$decision" \
    --arg next_action "$next_action" \
    --argjson counts "$counts_json" \
    --argjson signals "$signals_json" \
    --argjson findings "$findings_json" \
    '{decision: $decision, next_action: $next_action, counts: $counts, signals: $signals, findings: $findings}'
  exit "$exit_code"
fi

printf 'Decision: %s\n' "$decision"
printf 'Next action: %s\n' "$next_action"
printf '\nCounts:\n'
jq -r 'to_entries[] | "  \(.key): \(.value)"' <<<"$counts_json"
printf '\nFindings:\n'
if [[ "$(jq 'length' <<<"$findings_json")" -eq 0 ]]; then
  printf '  none\n'
else
  jq -r '.[] | "  - \(.)"' <<<"$findings_json"
fi

exit "$exit_code"
