#!/usr/bin/env bash
# scripts/walter/subcommands/post-merge-check.sh
# Read-only post-merge health classification for the autonomous delivery loop.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: walter-os post-merge-check [--commit <sha>] [--json] [--fixture <path>]

Classifies post-merge evidence into one of:
  healthy               All runs green and no high/critical alerts.
  investigate           Pending or failed non-deploy evidence needs follow-up.
  rollback-recommended  High-impact failure or high/critical telemetry alert.
  human-escalation      Fix-attempt cap reached; stop automated looping.

This command is read-only. It never opens PRs, reverts commits, or mutates
feature-state ledgers.

Options:
  --commit <sha>      Merge commit to inspect with gh run list.
  --json              Print machine-readable JSON.
  --fixture <path>    Read post-merge evidence JSON from a file for tests.
EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "walter-os post-merge-check: jq is required" >&2
    exit 3
  fi
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "walter-os post-merge-check: gh is required unless --fixture is used" >&2
    exit 3
  fi
}

json_output=0
fixture=""
commit_ref=""

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
        exit 2
      fi
      shift 2
      ;;
    --commit)
      commit_ref="${2:-}"
      if [[ -z "$commit_ref" ]]; then
        echo "walter-os post-merge-check: --commit requires a sha" >&2
        exit 2
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
      exit 2
      ;;
    *)
      echo "walter-os post-merge-check: unexpected argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_jq

if [[ -n "$fixture" && -n "$commit_ref" ]]; then
  echo "walter-os post-merge-check: --fixture cannot be combined with --commit" >&2
  exit 2
fi

if [[ -n "$fixture" ]]; then
  if [[ ! -r "$fixture" ]]; then
    echo "walter-os post-merge-check: fixture is not readable: $fixture" >&2
    exit 2
  fi
  evidence_json="$(cat "$fixture")"
else
  require_gh
  if [[ -z "$commit_ref" ]]; then
    commit_ref="$(git rev-parse HEAD 2>/dev/null || true)"
  fi
  if [[ -z "$commit_ref" ]]; then
    echo "walter-os post-merge-check: --commit is required outside a git repo" >&2
    exit 2
  fi
  runs_json="$(gh run list --commit "$commit_ref" --limit 30 --json workflowName,status,conclusion,url,createdAt,displayTitle)"
  evidence_json="$(jq -nc \
    --arg merge_sha "$commit_ref" \
    --argjson runs "$runs_json" \
    '{pr: {merge_sha: $merge_sha}, feature: {fix_attempts: 0, max_fix_attempts: 2}, runs: $runs, alerts: []}')"
fi

if ! jq -e . >/dev/null 2>&1 <<<"$evidence_json"; then
  echo "walter-os post-merge-check: evidence is not valid JSON" >&2
  exit 2
fi

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
pending_names="$(jq -r "${run_filter}"'[.runs[]? | select((completed | not) or ((.conclusion // "") == "")) | run_name] | join(", ")' <<<"$evidence_json")"
failed_names="$(jq -r "${run_filter}"'[.runs[]? | select(completed and ((.conclusion // "") != "") and (ok_conclusion | not)) | run_name] | join(", ")' <<<"$evidence_json")"
high_impact_failed_names="$(jq -r "${run_filter}"'[.runs[]? | select(completed and ((.conclusion // "") != "") and (ok_conclusion | not)) | select((run_name | test("(deploy|release|migration|production)"; "i"))) | run_name] | join(", ")' <<<"$evidence_json")"
critical_alerts="$(jq -r '[.alerts[]? | select(((.severity // "") | tostring | ascii_downcase) == "critical" or ((.severity // "") | tostring | ascii_downcase) == "high") | (.summary // .name // .source // "unnamed alert")] | join(", ")' <<<"$evidence_json")"
fix_attempts="$(jq -r '.feature.fix_attempts // 0' <<<"$evidence_json")"
max_fix_attempts="$(jq -r '.feature.max_fix_attempts // 2' <<<"$evidence_json")"

pending_count=0
failed_count=0
high_impact_failed_count=0
critical_alert_count=0
[[ -n "$pending_names" ]] && pending_count="$(awk -F', ' '{print NF}' <<<"$pending_names")"
[[ -n "$failed_names" ]] && failed_count="$(awk -F', ' '{print NF}' <<<"$failed_names")"
[[ -n "$high_impact_failed_names" ]] && high_impact_failed_count="$(awk -F', ' '{print NF}' <<<"$high_impact_failed_names")"
[[ -n "$critical_alerts" ]] && critical_alert_count="$(awk -F', ' '{print NF}' <<<"$critical_alerts")"

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

if [[ "$json_output" -eq 1 ]]; then
  jq -nc \
    --arg decision "$decision" \
    --arg next_action "$next_action" \
    --argjson counts "$counts_json" \
    --argjson findings "$findings_json" \
    '{decision: $decision, next_action: $next_action, counts: $counts, findings: $findings}'
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
