#!/usr/bin/env bash
# scripts/agents/lib/spend.sh — LiteLLM spend reporting library.
# Sourced (not exec'd) by bin/walter-os cmd_spend_report.
#
# Calls LiteLLM's GET /spend/tags API and formats the response as aligned
# tables. Requires LITELLM_BASE_URL and LITELLM_API_KEY to be set.
#
# Usage:
#   source spend.sh
#   spend_report_by_agent <start_date> <end_date>
#   spend_report_by_task  <start_date> <end_date>
#
# Spec: docs/specs/walter-council-v2.md — Improvement 2 (T-7)
# Refs: T-7

# shellcheck disable=SC2034
WALTER_SPEND_LIB_VERSION=1

# _spend_date_offset <days_ago> — compute a date N days ago in YYYY-MM-DD format.
# Works on both macOS (BSD date) and Linux (GNU date).
_spend_date_offset() {
  local days_ago="${1:-0}"
  if date -v-"${days_ago}"d +%Y-%m-%d >/dev/null 2>&1; then
    # macOS BSD date
    date -v-"${days_ago}"d +%Y-%m-%d
  else
    # GNU date (Linux)
    date -d "-${days_ago} days" +%Y-%m-%d
  fi
}

# _spend_parse_last_flag <last_value> — parse "7d" → number of days.
_spend_parse_last_flag() {
  local last_val="${1:-7d}"
  echo "${last_val%d}"
}

# _spend_api_call <start_date> <end_date> <tag_key> — call LiteLLM /spend/tags.
# Outputs raw JSON from the API.
_spend_api_call() {
  local start_date="$1" end_date="$2" tag_key="${3:-agent_id}"
  local url="${LITELLM_BASE_URL:-}"

  if [[ -z "$url" ]]; then
    echo "spend.sh: LITELLM_BASE_URL is not set" >&2
    return 3
  fi
  if [[ -z "${LITELLM_API_KEY:-}" ]]; then
    echo "spend.sh: LITELLM_API_KEY is not set" >&2
    return 3
  fi

  curl -fsS -m 30 \
    -H "Authorization: Bearer ${LITELLM_API_KEY}" \
    -H "Content-Type: application/json" \
    "${url}/spend/tags?start_date=${start_date}&end_date=${end_date}&group_by=${tag_key}" \
    2>/dev/null
}

# _spend_format_table_agent <json> — format JSON spend data as an agent table.
# Expects JSON array with fields: tag (agent_id), total_cost, total_tokens.
# Prints a header + aligned rows sorted by cost desc.
_spend_format_table_agent() {
  local json_input="${1:-[]}"
  command -v jq >/dev/null 2>&1 || { echo "spend.sh: jq required" >&2; return 3; }

  printf "%-16s %-20s %12s %12s %10s\n" "AGENT" "MODEL" "TOKENS_IN" "TOKENS_OUT" "COST_USD"
  printf "%-16s %-20s %12s %12s %10s\n" "─────" "─────" "─────────" "──────────" "────────"

  echo "$json_input" | jq -r '
    if type == "array" then
      sort_by(.total_cost) | reverse |
      .[] |
      [
        (.tag // "-"),
        (.model // "-"),
        (.prompt_tokens // 0 | tostring),
        (.completion_tokens // 0 | tostring),
        (.total_cost // 0 | . * 10000 | round / 10000 | tostring)
      ] | @tsv
    else
      empty
    end
  ' 2>/dev/null | while IFS=$'\t' read -r agent model tok_in tok_out cost; do
    printf "%-16s %-20s %12s %12s %10s\n" \
      "${agent:0:15}" "${model:0:19}" "$tok_in" "$tok_out" "$cost"
  done
}

# _spend_format_table_task <json> — format JSON spend data as a task table.
# Prints top-20 most expensive tasks.
#
# NOTE: The AGENT column will always show "-" when using LiteLLM's
# /spend/tags?group_by=task_id endpoint. LiteLLM does not support
# multi-group aggregation (group_by=task_id,agent_id) in this endpoint.
# agent_id is not returned as a sibling field alongside task_id in the
# response. This is a known LiteLLM API limitation; use --by-agent to
# see per-agent breakdowns.
_spend_format_table_task() {
  local json_input="${1:-[]}"
  command -v jq >/dev/null 2>&1 || { echo "spend.sh: jq required" >&2; return 3; }

  printf "%-36s %-12s %-20s %10s\n" "TASK_ID" "AGENT" "MODEL" "COST_USD"
  printf "%-36s %-12s %-20s %10s\n" "───────" "─────" "─────" "────────"

  echo "$json_input" | jq -r '
    if type == "array" then
      sort_by(.total_cost) | reverse | .[0:20] |
      .[] |
      [
        (.tag // "-"),
        (.agent_id // "-"),   # Always "-": LiteLLM group_by=task_id does not include agent_id
        (.model // "-"),
        (.total_cost // 0 | . * 10000 | round / 10000 | tostring)
      ] | @tsv
    else
      empty
    end
  ' 2>/dev/null | while IFS=$'\t' read -r task_id agent model cost; do
    printf "%-36s %-12s %-20s %10s\n" \
      "${task_id:0:35}" "${agent:0:11}" "${model:0:19}" "$cost"
  done
}

# spend_report_by_agent <start_date> <end_date> — print spend table by agent.
spend_report_by_agent() {
  local start_date="$1" end_date="$2"
  local json
  json=$(_spend_api_call "$start_date" "$end_date" "agent_id") || return $?
  _spend_format_table_agent "$json"
}

# spend_report_by_task <start_date> <end_date> — print spend table by task.
spend_report_by_task() {
  local start_date="$1" end_date="$2"
  local json
  json=$(_spend_api_call "$start_date" "$end_date" "task_id") || return $?
  _spend_format_table_task "$json"
}
