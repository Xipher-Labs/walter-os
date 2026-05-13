#!/usr/bin/env bash
# LiteLLM client helper — calls walter-VM gateway at llm.${WALTER_DOMAIN}

# Resolves master key from Infisical or local secrets.env
litellm_master_key() {
  if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
    echo "$LITELLM_MASTER_KEY"
    return
  fi
  if [[ -f "$HOME/.config/walter-os/secrets.env" ]]; then
    grep -E '^export LITELLM_MASTER_KEY=' "$HOME/.config/walter-os/secrets.env" | head -1 | cut -d= -f2- | tr -d "'\""
  fi
}

# Calls LiteLLM chat completion. Single-turn.
# Usage:
#   prompt='Tell me a joke'
#   litellm_chat "$prompt" "claude-sonnet-4-5"
litellm_chat() {
  local prompt="$1" model="${2:-sonnet}"
  local key
  key=$(litellm_master_key)
  if [[ -z "$key" ]]; then
    log_err "No LITELLM_MASTER_KEY found. Source ~/.config/walter-os/secrets.env" >&2
    return 1
  fi
  local body
  body=$(jq -nc --arg m "$model" --arg p "$prompt" \
    '{model:$m, messages:[{role:"user", content:$p}]}')
  local base_url="${LITELLM_BASE_URL:-https://llm.${WALTER_DOMAIN:-}}"
  if [[ -z "${base_url}" || "${base_url}" == "https://llm." ]]; then
    echo "ERROR: LITELLM_BASE_URL not set and WALTER_DOMAIN not set — cannot construct LiteLLM endpoint" >&2
    return 2
  fi
  curl -fsS -X POST "${base_url}/v1/chat/completions" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "$body" | jq -r '.choices[0].message.content // .error.message // "(empty response)"'
}

# Same but with file-based prompt (multiline + larger)
litellm_chat_from_file() {
  local file="$1" model="${2:-sonnet}"
  litellm_chat "$(cat "$file")" "$model"
}
