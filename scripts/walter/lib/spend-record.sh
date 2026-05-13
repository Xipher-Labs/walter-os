#!/usr/bin/env bash
# scripts/walter/lib/spend-record.sh — shared CLI spend recording helper.
#
# Sourced by walter CLI subcommands that call the LLM so every successful
# AI invocation appends a structured entry to ~/.config/walter-os/cli-spend.jsonl.
#
# Usage:
#   source "$WALTER_OS_HOME/scripts/walter/lib/spend-record.sh"
#   _record_cli_spend "walter ask" "haiku" 512
#
# Refs: docs/specs/phase-w-2-cli-ai.md [AC-7]

# _record_cli_spend <command> <model> <approx_tokens>
#
# Appends one JSON line to ~/.config/walter-os/cli-spend.jsonl with:
#   timestamp, command, model, approx_tokens
#
# Requires jq on PATH. Returns 1 with an error message if jq is absent.
_record_cli_spend() {
  local command="$1" model="${2:-unknown}" approx_tokens="${3:-0}"
  local spend_file="${HOME}/.config/walter-os/cli-spend.jsonl"

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq required for cost recording" >&2
    return 1
  fi

  mkdir -p "$(dirname "$spend_file")"

  local entry
  entry="$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cmd "$command" \
    --arg model "$model" \
    --argjson tokens "$approx_tokens" \
    '{timestamp: $ts, command: $cmd, model: $model, approx_tokens: $tokens}')"
  printf '%s\n' "$entry" >> "$spend_file"
}
