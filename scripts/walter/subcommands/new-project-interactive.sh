#!/usr/bin/env bash
# scripts/walter/subcommands/new-project-interactive.sh
# walter new project --interactive
#
# LLM-driven project interview (5 questions: name, domain, stack, compliance,
# type). Outputs to stdout: AGENTS.md draft + spec charter + Plane epic command.
# Pass --write to persist files to disk.
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
# shellcheck source=/dev/null
source "${WALTER_OS_HOME}/scripts/walter/lib/model-router.sh"

_no_ai_message() {
  cat >&2 <<'EOF'
AI not configured. To enable AI-powered commands, set one of:

  1. LiteLLM (preferred — telemetry + budget caps):
       LITELLM_BASE_URL=http://your-litellm:4000
       LITELLM_API_KEY=sk-...

  2. Direct Anthropic API:
       ANTHROPIC_API_KEY=sk-ant-...

Add these to ~/.config/walter-os/env or ~/.env.local.

For the non-interactive form-based flow, use:
  walter new project <type> [name]
EOF
}

# Parse --write flag
write_to_disk=false
pivot_mode=false
for arg in "$@"; do
  case "$arg" in
    --write) write_to_disk=true ;;
    --pivot) pivot_mode=true ;;
  esac
done

if ! llm_available; then
  _no_ai_message
  exit 1
fi

model_tag=""
walter_model_select_primary brainstorm model_tag

# -----------------------------------------------------------------------
# Interview: 5 questions sent to LLM in one shot for structured output.
# In a real interactive session the operator would answer sequentially,
# but since this is a CLI tool (not a REPL), we collect answers via
# read from stdin. When WALTER_LLM_MOCK_FILE is set, we skip all stdin
# and use the mock response directly.
# -----------------------------------------------------------------------

if [[ -n "${WALTER_LLM_MOCK_FILE:-}" && -f "${WALTER_LLM_MOCK_FILE}" ]]; then
  # Test / CI path: use mock response directly
  mock_response="$(jq -r '.mock_response // "mock response"' "${WALTER_LLM_MOCK_FILE}")"
  printf '%s\n' "$mock_response"

  if [[ "$write_to_disk" == "true" ]]; then
    # Write AGENTS.md to cwd
    printf '%s\n' "$mock_response" | grep -A 1000 '# AGENTS.md' > AGENTS.md
    mkdir -p docs/specs
    # Write a spec file named from first word after project
    printf '%s\n' "$mock_response" > "docs/specs/new-project.md"
    log_ok "Files written to disk (mock mode)." >&2
  fi

  _record_cli_spend "walter new project --interactive" "$model_tag" 2048
  exit 0
fi

# Real interactive path
if [[ "$pivot_mode" == "true" ]]; then
  mode_instruction="The operator wants to reconfigure an existing project."
else
  mode_instruction="The operator wants to create a new project."
fi

cat >&2 <<'BANNER'
Walter — New Project Interview (AI-powered)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Answer 5 questions. The LLM will generate:
  • AGENTS.md draft
  • Spec charter (docs/specs/ format)
  • Plane epic creation command

Press Ctrl-C to abort.
BANNER

read -r -p "1. Project name (slug, kebab-case): " answer_name
read -r -p "2. Domain (e.g. fintech, devtools, health, gaming): " answer_domain
read -r -p "3. Stack (e.g. Next.js + Supabase, Rust + Solana, React Native): " answer_stack
read -r -p "4. Compliance/regulatory constraints (e.g. HIPAA, GDPR, local patient-rights law, none): " answer_compliance
read -r -p "5. Project type (projects/hackaton/work/personal): " answer_type

user_content="Project name: ${answer_name}
Domain: ${answer_domain}
Stack: ${answer_stack}
Compliance: ${answer_compliance}
Project type: ${answer_type}"

system_prompt="You are Walter, an AI assistant for the Walter-OS operator system.
${mode_instruction}

Based on the operator's 5 answers, generate exactly three sections separated
by the markers below. Do not add any other text outside these sections.

=== AGENTS.md ===
(Full AGENTS.md starting with '# AGENTS.md'. Include: operator profile section,
stack details, active project, compliance rules, skill loading. ≤200 lines.)

=== SPEC CHARTER ===
(Spec charter starting with '## Problem'. Include sections: Problem, Proposed solution,
Acceptance Criteria (AC-1 through AC-N), Non-goals, Implementation plan. ≤150 lines.)

=== PLANE EPIC ===
(A bash command block that creates the Plane epic, e.g.:
\`\`\`bash
# Run to create Plane epic (requires PLANE_API_TOKEN):
walter plane create-epic --name \"<project>\" --description \"<desc>\"
\`\`\`
)"

log_info "Sending to LLM..." >&2

response="$(llm_invoke_or_mock "walter-new-interactive" "$model_tag" "$system_prompt" "$user_content" 3000)"

# Output to stdout
printf '%s\n' "$response"

if [[ "$write_to_disk" == "true" ]]; then
  # Extract and write AGENTS.md
  agents_section="$(printf '%s\n' "$response" | awk '/^=== AGENTS\.md ===/,/^=== SPEC CHARTER ===/' | grep -v '^===' || true)"
  if [[ -n "$agents_section" ]]; then
    printf '%s\n' "$agents_section" > AGENTS.md
    log_ok "Written: AGENTS.md" >&2
  fi

  # Extract and write spec charter
  spec_section="$(printf '%s\n' "$response" | awk '/^=== SPEC CHARTER ===/,/^=== PLANE EPIC ===/' | grep -v '^===' || true)"
  if [[ -n "$spec_section" ]]; then
    mkdir -p docs/specs
    # Sanitize: strip all chars except alnum, dash, underscore; max 64 chars.
    # Prevents path traversal via malicious project names (e.g. ../../etc/passwd).
    local_name="$(printf '%s' "${answer_name:-new-project}" | tr -cd '[:alnum:]-_' | head -c 64)"
    [[ -z "$local_name" ]] && local_name="new-project"
    printf '%s\n' "$spec_section" > "docs/specs/${local_name}.md"
    log_ok "Written: docs/specs/${local_name}.md" >&2
  fi
fi

_record_cli_spend "walter new project --interactive" "$model_tag" 3000
