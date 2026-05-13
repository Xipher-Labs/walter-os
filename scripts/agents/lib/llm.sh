#!/usr/bin/env bash
# scripts/agents/lib/llm.sh — LLM invocation helper for the agent runner.
# Sourced (not exec'd).
#
# For O1 we call the Anthropic Messages API directly via curl. This is
# the simplest path that doesn't depend on the subscription pool (which
# lands in O5). When the pool is ready, we add a litellm-router branch
# here and the agent runner becomes pool-aware automatically.
#
# Required env (any one of):
#   ANTHROPIC_API_KEY              — used for personal context
#   ANTHROPIC_ENTERPRISE_KEY       — used for context:work
#   LITELLM_BASE_URL + LITELLM_API_KEY — preferred; routed through walter-vm
#                                       LiteLLM (already has 5 routes,
#                                       budget caps, telemetry)
#
# Usage:
#   source llm.sh
#   llm_invoke <agent-name> <model> <system-prompt> <user-prompt> <max-tokens>
#   → response text on stdout, status to stderr.

# shellcheck disable=SC2034 # used by callers via source
WALTER_LLM_LIB_VERSION=1

_llm_pick_endpoint() {
  # Prefer LiteLLM (telemetry + budget caps + future pool routing).
  if [[ -n "${LITELLM_BASE_URL:-}" && -n "${LITELLM_API_KEY:-}" ]]; then
    echo "litellm"
    return 0
  fi
  # Direct Anthropic if pool not available.
  if [[ -n "${ANTHROPIC_ENTERPRISE_KEY:-}" || -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "anthropic"
    return 0
  fi
  return 1
}

_llm_pick_anthropic_key() {
  # context:work uses enterprise; everything else uses personal API key.
  local context="${WALTER_AGENT_CONTEXT:-personal}"
  if [[ "$context" == "work" && -n "${ANTHROPIC_ENTERPRISE_KEY:-}" ]]; then
    echo "$ANTHROPIC_ENTERPRISE_KEY"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "$ANTHROPIC_API_KEY"
  else
    return 1
  fi
}

# Map our short model tags to actual model IDs.
_llm_resolve_model() {
  case "$1" in
    cheap)  echo "claude-haiku-4-5" ;;
    haiku)  echo "claude-haiku-4-5" ;;
    sonnet) echo "claude-sonnet-4-5" ;;
    opus)   echo "claude-opus-4-5" ;;
    *)      echo "$1" ;;  # passthrough
  esac
}

# llm_available — returns 0 if at least one LLM endpoint is configured, 1 otherwise.
# Also returns 0 when WALTER_LLM_MOCK_FILE is set (test/CI mock mode).
# Used by CLI commands before attempting LLM calls to provide graceful degradation.
llm_available() {
  # Mock mode counts as "available" — used in tests and CI.
  if [[ -n "${WALTER_LLM_MOCK_FILE:-}" && -f "${WALTER_LLM_MOCK_FILE}" ]]; then
    return 0
  fi
  _llm_pick_endpoint > /dev/null 2>&1
}

# llm_invoke_or_mock — if WALTER_LLM_MOCK_FILE is set, reads .mock_response from
# that JSON file instead of calling the real LLM. Enables deterministic CLI tests.
#
# Debug mode: when WALTER_LLM_DEBUG=1 is set, the system prompt is written to
# WALTER_LLM_DEBUG_FILE (default: mktemp-generated path under TMPDIR, 0600 perms)
# before invocation.
# Used in tests to verify prompt construction without an LLM credential.
llm_invoke_or_mock() {
  local agent="$1" model_tag="$2" system_prompt="$3" user_prompt="$4" max_tokens="${5:-2048}"

  # Debug logging — write system prompt to file for test inspection.
  if [[ "${WALTER_LLM_DEBUG:-}" == "1" ]]; then
    local debug_file="${WALTER_LLM_DEBUG_FILE:-$(mktemp -t walter-llm-debug.XXXXXX)}"
    chmod 600 "$debug_file" 2>/dev/null || true
    printf '%s\n' "$system_prompt" > "$debug_file"
  fi

  if [[ -n "${WALTER_LLM_MOCK_FILE:-}" && -f "${WALTER_LLM_MOCK_FILE}" ]]; then
    echo "[WARN] WALTER_LLM_MOCK_FILE is set — using mock LLM responses (not real AI)" >&2
    jq -r '.mock_response // "mock response"' "${WALTER_LLM_MOCK_FILE}"
    return 0
  fi
  llm_invoke "$agent" "$model_tag" "$system_prompt" "$user_prompt" "$max_tokens"
}

llm_invoke() {
  local agent="$1" model_tag="$2" system_prompt="$3" user_prompt="$4" max_tokens="${5:-2048}"
  local model endpoint
  model=$(_llm_resolve_model "$model_tag")
  endpoint=$(_llm_pick_endpoint) || {
    echo "llm.sh: no LLM endpoint available (set LITELLM_* or ANTHROPIC_* env)" >&2
    return 2
  }

  # Cost-attribution metadata — sourced from agent runner env vars.
  # task_id: Plane issue ID (WALTER_AGENT_PLANE_ISSUE)
  # context: work/personal/[project-b] (WALTER_AGENT_CONTEXT)
  # model_alias: short model tag (haiku/sonnet/opus) used for routing
  local task_id="${WALTER_AGENT_PLANE_ISSUE:-}"
  local context="${WALTER_AGENT_CONTEXT:-personal}"

  # WALTER_LLM_RAW_FILE: if set, write raw API JSON response to this file
  # before extracting text. Allows callers to read usage.total_tokens from
  # the raw response without reparsing post-extraction output.
  local raw_file="${WALTER_LLM_RAW_FILE:-}"

  case "$endpoint" in
    litellm)
      local payload
      payload=$(jq -nc \
        --arg model "$model_tag" \
        --arg sys "$system_prompt" \
        --arg usr "$user_prompt" \
        --argjson max "$max_tokens" \
        --arg agent_id "$agent" \
        --arg task_id "$task_id" \
        --arg context "$context" \
        --arg model_alias "$model_tag" \
        '{model: $model, max_tokens: $max, messages: [
            {role: "system", content: $sys},
            {role: "user", content: $usr}
          ], metadata: {
            agent_id: $agent_id,
            task_id: $task_id,
            context: $context,
            model_alias: $model_alias
          }}')

      local raw_response
      raw_response=$(curl -fsS -m 600 \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${LITELLM_BASE_URL}/v1/chat/completions")
      if [[ -n "$raw_file" ]]; then
        printf '%s\n' "$raw_response" > "$raw_file"
      fi
      printf '%s\n' "$raw_response" | jq -r '.choices[0].message.content // empty'
      ;;

    anthropic)
      local key
      key=$(_llm_pick_anthropic_key) || return 3
      local payload
      payload=$(jq -nc \
        --arg model "$model" \
        --arg sys "$system_prompt" \
        --arg usr "$user_prompt" \
        --argjson max "$max_tokens" \
        '{model: $model, max_tokens: $max, system: $sys, messages: [
            {role: "user", content: $usr}
          ]}')

      # For the direct Anthropic path, add litellm-compatible tag headers so future
      # routing can pick up cost attribution without a schema change.
      local tags_json
      tags_json=$(jq -nc \
        --arg agent_id "$agent" \
        --arg task_id "$task_id" \
        --arg context "$context" \
        --arg model_alias "$model_tag" \
        '{agent_id: $agent_id, task_id: $task_id, context: $context, model_alias: $model_alias}')

      local raw_response
      raw_response=$(curl -fsS -m 600 \
        -H "x-api-key: $key" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -H "x-litellm-tags: ${tags_json}" \
        -d "$payload" \
        "https://api.anthropic.com/v1/messages")
      if [[ -n "$raw_file" ]]; then
        printf '%s\n' "$raw_response" > "$raw_file"
      fi
      printf '%s\n' "$raw_response" | jq -r '.content[0].text // empty'
      ;;
  esac
}
