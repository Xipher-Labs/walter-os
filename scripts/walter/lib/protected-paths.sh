#!/usr/bin/env bash
# Shared protected-path policy for Walter-OS hook gates.
#
# approval-gate.sh uses this list to require operator approval. capability-check.sh
# uses the same list to require a session capability token after approval.
# shellcheck disable=SC2034

declare -a WALTER_PROTECTED_PATH_PATTERNS=(
  # Walter-OS contract files
  'hooks/*.sh'
  '.claude/settings.json'
  '.github/workflows/*'
  'install.sh'
  'bin/walter-os'
  'AGENTS.md'
  'CLAUDE.md'
  'mcp/servers.json'
  'scripts/walter/lib/capability-token.sh'
  'scripts/walter/lib/session-state.sh'
  'scripts/walter/subcommands/cap.sh'
  # Self-modification
  'agents/*.md'
  'skills/*/SKILL.md'
  # Auth / crypto / PHI
  # Operators: extend this list for project-specific PHI / sensitive paths.
  'auth/*'
  'crypto/*'
  'personal/health/*'
  '*.key'
  '*.pem'
  '*.crt'
  '.ssh/*'
  '*/.ssh/*'
  # Secrets
  '*.env'
  '*.env.*'
)
