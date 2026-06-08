#!/usr/bin/env bash
# scripts/agents/lib/vote.sh — Consensus voting library for Walter Council.
# Sourced (not exec'd) by agent runner and approval-gate when consensus mode is ON.
#
# vote_council <task_id> <task_description> <agents_json_array>
#   Invokes up to 3 agents in parallel via llm_invoke. Each agent answers:
#   "Should this task be auto-approved? yes or no + 1-sentence reason."
#   Returns JSON on stdout:
#   {
#     "votes": N,
#     "yes": N,
#     "no": N,
#     "abstain": N,
#     "quorum_met": true|false,
#     "voters": [{"agent": "...", "vote": "yes|no|abstain", "reason": "..."}]
#   }
#
# Quorum: default 3-agent poll; quorum_met=true if yes >= ceil(votes/2).
# Timeout per agent: 15 seconds. Timeouts count as abstain.
# LLM is invoked via $LLM_SH (defaults to the sibling llm.sh in the same dir).
#
# Spec: docs/specs/walter-council-v2.md — Improvement 9 (T-33)

# shellcheck disable=SC2034
WALTER_VOTE_LIB_VERSION=1

WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
CONSENSUS_VOTES_LOG="${WALTER_CONSENSUS_VOTES_LOG:-/var/log/walter-council/consensus-votes.log}"

# Determine LLM library path — allow override via LLM_SH env for testing.
_vote_llm_sh() {
  if [[ -n "${LLM_SH:-}" && -f "${LLM_SH}" ]]; then
    echo "$LLM_SH"
    return 0
  fi
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "${script_dir}/llm.sh"
}

_vote_model_router_sh() {
  if [[ -n "${WALTER_MODEL_ROUTER_SH:-}" && -f "${WALTER_MODEL_ROUTER_SH}" ]]; then
    echo "$WALTER_MODEL_ROUTER_SH"
    return 0
  fi
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "${script_dir}/../../walter/lib/model-router.sh"
}

_vote_select_model() {
  local model="haiku"
  local router_sh
  router_sh="$(_vote_model_router_sh)"

  if [[ -n "${LITELLM_BASE_URL:-}" && -n "${LITELLM_API_KEY:-}" && -f "$router_sh" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$router_sh"
    walter_model_select_primary backend_review model || model="haiku"
  fi

  printf '%s' "$model"
}

# _vote_sanitize_task_desc <raw_desc> → prints sanitized version on stdout
# Strips control characters and prompt-injection markers to prevent:
#   1. Shell injection via shell-interpolation in bash -c
#   2. LLM prompt injection via result markers or special tokens
_vote_sanitize_task_desc() {
  local raw="$1"
  # Strip C0 control chars (except tab/newline) and DEL
  local stripped
  stripped=$(printf '%s' "$raw" | LC_ALL=C tr -d '\000-\010\013-\037\177')
  # Strip Claude result markers
  stripped=$(printf '%s' "$stripped" | sed -E 's/<<<RESULT_[A-Z_]+>>>//g')
  # Strip common LLM special tokens (im_start/im_end, <|...|> style)
  stripped=$(printf '%s' "$stripped" | sed -E 's/<\|[a-zA-Z_]+\|>//g')
  printf '%s' "$stripped"
}

# _vote_log <event> <issue_id> <extra_json_str>
# Appends a JSON log line to CONSENSUS_VOTES_LOG.
_vote_log() {
  local event="$1" issue_id="$2"
  local extra="${3}"
  [[ -z "$extra" ]] && extra="{}"
  [[ -n "$issue_id" ]] || return 0
  local log_dir; log_dir=$(dirname "$CONSENSUS_VOTES_LOG")
  [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || return 0
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -nc \
    --arg ts "$ts" \
    --arg event "$event" \
    --arg issue_id "$issue_id" \
    --argjson extra "$extra" \
    '{ts: $ts, event: $event, issue_id: $issue_id} + $extra' \
    >> "$CONSENSUS_VOTES_LOG" 2>/dev/null || true
}

# _vote_invoke_agent <agent> <task_description> <outfile>
# Writes vote result JSON to outfile. Runs in a subshell for backgrounding.
# Prompts are passed via env vars — NEVER shell-interpolated into bash -c.
_vote_invoke_agent() {
  local agent="$1" task_desc="$2" outfile="$3"
  local llm_sh
  llm_sh="$(_vote_llm_sh)"
  local vote_model
  vote_model="$(_vote_select_model)"

  # Sanitize task_desc before embedding in prompts (defense in depth)
  local task_desc_safe
  task_desc_safe="$(_vote_sanitize_task_desc "$task_desc")"

  local system_prompt="You are ${agent}, a member of the Walter Council. You are voting on whether a task should be auto-approved without human operator review. Respond with ONLY 'yes' or 'no' on the first line, followed by exactly one sentence explaining your reasoning."
  local user_prompt="Should this task be auto-approved without operator review?

Task: ${task_desc_safe}

Answer: yes or no (first line), then one sentence reason."

  local response=""
  if [[ -f "$llm_sh" ]]; then
    # Pass prompts via env vars — no user-controlled data in the bash -c string itself.
    response=$(
      WALTER_VOTE_SYSTEM="$system_prompt" \
      WALTER_VOTE_USER="$user_prompt" \
      WALTER_VOTE_AGENT="$agent" \
      WALTER_VOTE_MODEL="$vote_model" \
        bash -c '
          source "$1"
          llm_invoke "$WALTER_VOTE_AGENT" "$WALTER_VOTE_MODEL" "$WALTER_VOTE_SYSTEM" "$WALTER_VOTE_USER" 100
        ' _ "$llm_sh" 2>/dev/null
    ) || response=""
  fi

  # Parse the response: first word is yes/no, rest is reason
  local vote="abstain" reason="timeout or LLM error"
  if [[ -n "$response" ]]; then
    local first_word
    first_word=$(echo "$response" | head -1 | awk '{print tolower($1)}' | tr -cd '[:lower:]')
    case "$first_word" in
      yes) vote="yes" ;;
      no)  vote="no"  ;;
      *)   vote="abstain" ;;
    esac
    # Reason: everything after the first line (or the full response if one-liner)
    reason=$(echo "$response" | tail -n +2 | head -1)
    [[ -z "$reason" ]] && reason=$(echo "$response" | head -1 | cut -d' ' -f2-)
    [[ -z "$reason" ]] && reason="no reason given"
  fi

  jq -nc \
    --arg agent "$agent" \
    --arg vote "$vote" \
    --arg reason "$reason" \
    '{agent: $agent, vote: $vote, reason: $reason}' > "$outfile"
}

# vote_council <task_id> <task_description> <agents_json_array>
# Polls the given agents and returns the vote JSON.
vote_council() {
  local task_id="$1" task_desc="$2" agents_json="$3"
  command -v jq >/dev/null 2>&1 || {
    echo "vote.sh: jq required" >&2
    return 2
  }

  # Sanitize task_desc once at entry — used for prompts and audit log
  local task_desc_safe
  task_desc_safe="$(_vote_sanitize_task_desc "$task_desc")"

  # Parse agent list (max 3)
  local agents=()
  while IFS= read -r a; do
    agents+=("$a")
  done < <(echo "$agents_json" | jq -r '.[]' 2>/dev/null | head -3)

  if [[ ${#agents[@]} -eq 0 ]]; then
    echo '{"votes":0,"yes":0,"no":0,"abstain":0,"quorum_met":false,"voters":[]}'
    return 0
  fi

  # Require minimum 2 agents for a valid consensus vote.
  # 1 agent auto-approving is not consensus — it's just one opinion.
  if [[ "${#agents[@]}" -lt 2 ]]; then
    _vote_log "consensus_failed" "$task_id" \
      "{\"reason\":\"insufficient_agents\",\"count\":${#agents[@]},\"min\":2}"
    # Also log awaiting_human so summary --since counts it correctly.
    _vote_log "awaiting_human" "$task_id" \
      "{\"reason\":\"insufficient_agents\"}"
    echo '{"votes":0,"yes":0,"no":0,"abstain":0,"quorum_met":false,"voters":[],"error":"insufficient_agents"}'
    return 1
  fi

  # Create temp dir for vote results
  local tmpdir
  tmpdir=$(mktemp -d -t walter-vote-XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  # Invoke agents in parallel with timeout
  local pids=()
  local i=0
  for agent in "${agents[@]}"; do
    local outfile="${tmpdir}/vote-${i}.json"
    (
      # Per-agent timeout: 15 seconds; pass sanitized task_desc
      _vote_invoke_agent "$agent" "$task_desc_safe" "$outfile"
    ) &
    pids+=($!)
    i=$((i + 1))
  done

  # Wait for all with 15s total timeout
  local timeout_epoch=$(( $(date +%s) + 15 ))
  for pid in "${pids[@]}"; do
    local remaining=$(( timeout_epoch - $(date +%s) ))
    [[ "$remaining" -le 0 ]] && break
    # Wait up to remaining seconds for this pid
    # On macOS, `wait -t` not available; use a polling approach
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      [[ "$waited" -ge "$remaining" ]] && { kill "$pid" 2>/dev/null; break; }
      sleep 1
      waited=$((waited + 1))
    done
    wait "$pid" 2>/dev/null || true
  done

  # Collect results
  local total=0 yes_count=0 no_count=0 abstain_count=0
  local voters_json="[]"

  for outfile in "${tmpdir}"/vote-*.json; do
    [[ -f "$outfile" ]] || continue
    local entry
    entry=$(cat "$outfile" 2>/dev/null)
    [[ -z "$entry" ]] && continue
    total=$((total + 1))
    local vote
    vote=$(echo "$entry" | jq -r '.vote' 2>/dev/null || echo "abstain")
    case "$vote" in
      yes)    yes_count=$((yes_count + 1)) ;;
      no)     no_count=$((no_count + 1)) ;;
      *)      abstain_count=$((abstain_count + 1)) ;;
    esac
    voters_json=$(echo "$voters_json" | jq --argjson e "$entry" '. + [$e]' 2>/dev/null || echo "$voters_json")
  done

  # For missing results (timeout), write abstain entries
  for agent in "${agents[@]}"; do
    local found=0
    while IFS= read -r v; do
      [[ "$(echo "$v" | jq -r '.agent' 2>/dev/null)" == "$agent" ]] && found=1 && break
    done < <(echo "$voters_json" | jq -c '.[]' 2>/dev/null || echo "")
    if [[ "$found" -eq 0 ]]; then
      total=$((total + 1))
      abstain_count=$((abstain_count + 1))
      voters_json=$(echo "$voters_json" | jq \
        --arg a "$agent" \
        '. + [{"agent": $a, "vote": "abstain", "reason": "timeout"}]' 2>/dev/null || echo "$voters_json")
    fi
  done

  # Quorum: majority of voters (yes > votes/2)
  local quorum_met="false"
  if [[ "$total" -gt 0 && "$yes_count" -gt $((total / 2)) ]]; then
    quorum_met="true"
  fi

  local result
  result=$(jq -nc \
    --argjson votes "$total" \
    --argjson yes "$yes_count" \
    --argjson no "$no_count" \
    --argjson abstain "$abstain_count" \
    --argjson quorum_met "$([[ $quorum_met == "true" ]] && echo true || echo false)" \
    --argjson voters "$voters_json" \
    '{votes: $votes, yes: $yes, no: $no, abstain: $abstain, quorum_met: $quorum_met, voters: $voters}')

  echo "$result"

  # Log the vote to consensus-votes.log if task_id is non-empty.
  # Include task_description (sanitized) so Phase U Decision Timeline can
  # reconstruct context without extra Plane API calls per log line.
  if [[ -n "$task_id" ]]; then
    local event_type="consensus_failed"
    [[ "$quorum_met" == "true" ]] && event_type="consensus_approved"
    local task_desc_json
    task_desc_json=$(jq -cn --arg d "$task_desc_safe" '$d')
    local log_extra
    log_extra=$(jq -cn \
      --arg td "$task_desc_safe" \
      --argjson vr "$result" \
      '{task_description: $td, vote_result: $vr}')
    _vote_log "$event_type" "$task_id" "$log_extra"
  fi
}
