#!/usr/bin/env bash
# scripts/walter/subcommands/ask.sh — walter ask "<question>"
#
# Sends a natural-language question to the LLM with Council state as context.
# Requires LITELLM_BASE_URL+LITELLM_API_KEY or ANTHROPIC_API_KEY.
#
# Refs: docs/specs/phase-w-2-cli-ai.md

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
LLM_LIB="${WALTER_OS_HOME}/scripts/agents/lib/llm.sh"

# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/log.sh"
# shellcheck source=/dev/null
source "$LLM_LIB"
# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/spend-record.sh"

_no_ai_message() {
  cat >&2 <<'EOF'
AI not configured. To enable AI-powered commands, set one of:

  1. LiteLLM (preferred — telemetry + budget caps):
       LITELLM_BASE_URL=http://your-litellm:4000
       LITELLM_API_KEY=sk-...

  2. Direct Anthropic API:
       ANTHROPIC_API_KEY=sk-ant-...

Add these to ~/.config/walter-os/env or ~/.env.local.
EOF
}

question="${1:-}"
if [[ -z "$question" ]]; then
  log_err "walter ask: no question given"
  echo "Usage: walter ask \"<question>\"" >&2
  exit 1
fi

if ! llm_available; then
  _no_ai_message
  exit 1
fi

# Collect Council state context (truncated to last 100 lines)
context_parts=()

agents_status=""
if command -v walter-os >/dev/null 2>&1; then
  agents_status="$(walter-os agents status 2>/dev/null | tail -100 || true)"
else
  agents_status="(walter-os not in PATH — agents status unavailable)"
fi
context_parts+=("=== Council Agent Status (last 100 lines) ===
${agents_status}")

mode_json=""
mode_file="${HOME}/.config/walter-os/mode.json"
if [[ -f "$mode_file" ]]; then
  mode_json="$(cat "$mode_file")"
  context_parts+=("=== Current Mode ===
${mode_json}")
fi

spend_summary=""
if command -v walter-os >/dev/null 2>&1; then
  spend_summary="$(walter-os spend report --last 1d 2>/dev/null | tail -30 || true)"
  if [[ -n "$spend_summary" ]]; then
    context_parts+=("=== Last 24h Spend Summary ===
${spend_summary}")
  fi
fi

system_prompt="You are Walter, an AI assistant for the Walter-OS operator system.
Answer the operator's question concisely (1-3 sentences) based on the provided
Council state context. If the context does not contain enough information to
answer, say so clearly.

$(printf '%s\n\n' "${context_parts[@]}")"

response="$(llm_invoke_or_mock "walter-ask" "haiku" "$system_prompt" "$question" 512)"

printf '%s\n' "$response"

_record_cli_spend "walter ask" "haiku" 512
