#!/usr/bin/env bash
# scripts/walter/subcommands/explain.sh — walter explain <skill-or-component>
#
# Reads the skill's SKILL.md and produces a plain-English explanation via LLM.
# Falls back to raw SKILL.md content if LLM is not configured (no exit 1).
#
# Refs: docs/specs/phase-w-2-cli-ai.md

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
LLM_LIB="${WALTER_OS_HOME}/scripts/agents/lib/llm.sh"
SKILLS_DIR="${WALTER_OS_HOME}/skills"

# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/log.sh"
# shellcheck source=/dev/null
source "$LLM_LIB"
# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/spend-record.sh"
# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/model-router.sh"

skill_name="${1:-}"

if [[ -z "$skill_name" ]]; then
  log_err "walter explain: no skill name given"
  echo "Usage: walter explain <skill-name>" >&2
  echo "" >&2
  if [[ -d "$SKILLS_DIR" ]]; then
    echo "Available skills:" >&2
    find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
      | sort | sed 's/^/  /' >&2
  fi
  exit 1
fi

skill_md="${SKILLS_DIR}/${skill_name}/SKILL.md"

if [[ ! -f "$skill_md" ]]; then
  log_err "walter explain: skill '${skill_name}' not found"
  echo "" >&2
  if [[ -d "$SKILLS_DIR" ]]; then
    echo "Available skills:" >&2
    find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
      | sort | sed 's/^/  /' >&2
  fi
  exit 1
fi

skill_content="$(cat "$skill_md")"

# Fallback: if LLM unavailable, print raw SKILL.md (not an error for this command)
if ! llm_available; then
  printf '%s\n' "$skill_content"
  exit 0
fi

model_tag=""
walter_model_select_primary longform model_tag

# Build stack context from providers.yaml if present
stack_context=""
providers_file="${HOME}/.config/walter-os/providers.yaml"
if [[ -f "$providers_file" ]]; then
  stack_context="$(cat "$providers_file")"
fi

system_prompt="You are Walter, an AI assistant for Walter-OS operators.
Explain the following skill in 3-5 plain-English sentences. Cover:
1. What the skill does
2. When to use it
3. Any operator-specific relevance given their stack

Operator stack configuration (providers.yaml):
${stack_context:-'(not configured)'}

Be concise and practical. Do not repeat the skill name in the first word."

response="$(llm_invoke_or_mock "walter-explain" "$model_tag" "$system_prompt" "$skill_content" 512)"

printf '%s\n' "$response"

_record_cli_spend "walter explain" "$model_tag" 512
