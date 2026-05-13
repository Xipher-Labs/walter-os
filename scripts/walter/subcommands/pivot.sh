#!/usr/bin/env bash
# scripts/walter/subcommands/pivot.sh — walter pivot
#
# Invokes the project-pivot skill (W-3) for reconfiguring an existing project.
# Effectively new project --interactive scoped to reconfiguration mode.
# Requires AGENTS.md in cwd.
#
# Refs: docs/specs/phase-w-2-cli-ai.md

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
LLM_LIB="${WALTER_OS_HOME}/scripts/agents/lib/llm.sh"
SKILLS_DIR="${WALTER_OS_HOME}/skills"
PIVOT_SKILL="${SKILLS_DIR}/project-pivot"

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

# Check for AGENTS.md in cwd
if [[ ! -f "AGENTS.md" ]]; then
  log_err "walter pivot: no AGENTS.md found in current directory"
  cat >&2 <<'EOF'

walter pivot requires an existing project with AGENTS.md in the current directory.

If you want to start a new project from scratch, use:
  walter new project --interactive

Navigate to your project's root directory first, then run:
  walter pivot
EOF
  exit 1
fi

# Check for project-pivot skill — exit cleanly if not installed (W-3)
if [[ ! -d "$PIVOT_SKILL" ]]; then
  log_warn "project-pivot skill not installed"
  echo "Run: walter skill install project-pivot" >&2
  echo "Or check that ${PIVOT_SKILL} exists" >&2
  exit 1
fi

if ! llm_available; then
  _no_ai_message
  exit 1
fi

skill_content="$(cat "${PIVOT_SKILL}/SKILL.md")"
existing_agents_md="$(cat AGENTS.md 2>/dev/null || echo '')"

system_prompt="${skill_content}

Existing AGENTS.md for context:
${existing_agents_md}

Answer the 4 questions according to the skill's interview flow."

user_prompt="Please help me pivot/reconfigure this project. Generate the updated configuration."

response="$(llm_invoke_or_mock "walter-pivot" "sonnet" "$system_prompt" "$user_prompt" 2048)"

printf '%s\n' "$response"

_record_cli_spend "walter pivot" "sonnet" 2048
