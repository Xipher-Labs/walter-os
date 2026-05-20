#!/usr/bin/env bash
# branch-flow-guard.sh
# Enforces the Walter-OS branch policy at the Claude Code PreToolUse layer.
#
# Policy (see docs/decisions/0013-solo-operator-merge-policy.md):
#   - Direct push to main / master / staging / production is forbidden.
#   - Direct push from main / master / staging / production is forbidden
#     (the operator should be on a feature branch).
#   - PR creation does NOT require a specific base branch: feature/* can
#     target main directly. The previous three-stage flow
#     (feature → dev → staging → main) was retired in ADR 0013.
#   - Optional: WALTER_MANUAL_PR_REMOTE_PATTERN forces manual PR creation
#     on matching remotes (opt-in, default disabled).
#
# Hooked into Claude Code's PreToolUse for the Bash tool, matching commands
# that look like `gh pr create` or `git push origin <branch>`.
#
# Stdin: JSON with {tool: "Bash", tool_input: {command: "..."}}
# Stdout: JSON {decision: "allow"|"block", reason: "..."}

set -euo pipefail

# Read the tool call from stdin
INPUT="$(cat)"

# Extract command (using jq if available, basic grep fallback otherwise)
if command -v jq >/dev/null 2>&1; then
  CMD="$(echo "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
fi

# Get current branch and remote
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"

allow() {
  echo '{"decision":"allow"}'
  exit 0
}

block() {
  local reason="$1"
  echo "{\"decision\":\"block\",\"reason\":\"${reason}\"}"
  exit 0
}

# ---------- 1. Optional: block automated PR creation on matching remotes ----------
# Set WALTER_MANUAL_PR_REMOTE_PATTERN to a substring of your remote URL to enforce
# manual PR creation (agent prints the command instead of running it).
# Set WALTER_MANUAL_PR_OVERRIDE_FLAG to a custom --flag to allow bypass (default:
# --allow-manual-pr). Leave WALTER_MANUAL_PR_REMOTE_PATTERN empty (the default) to
# disable enforcement entirely.

MANUAL_PR_PATTERN="${WALTER_MANUAL_PR_REMOTE_PATTERN:-}"
MANUAL_PR_OVERRIDE="${WALTER_MANUAL_PR_OVERRIDE_FLAG:---allow-manual-pr}"

if [[ -n "$MANUAL_PR_PATTERN" ]]; then
  case "$REMOTE_URL" in
    *"$MANUAL_PR_PATTERN"*)
      if echo "$CMD" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create'; then
        if ! echo "$CMD" | grep -q -- "$MANUAL_PR_OVERRIDE"; then
          block "Manual-PR-only remote (${MANUAL_PR_PATTERN}): PRs must be created manually by the operator. Print the command instead. Override with ${MANUAL_PR_OVERRIDE}."
        fi
      fi
      ;;
  esac
fi

# ---------- 2. Block direct push to (or from) protected branches ----------
# The previous three-stage branch-flow gate (feature → dev → staging → main)
# was retired in ADR 0013. The protected-branch push block stays.

if echo "$CMD" | grep -qE '^[[:space:]]*git[[:space:]]+push'; then
  for protected in main master staging production; do
    if echo "$CMD" | grep -qE "(:|[[:space:]])${protected}[[:space:]]*$"; then
      block "Direct push to '${protected}' is forbidden. Use a PR."
    fi
  done
  if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || "$BRANCH" == "staging" || "$BRANCH" == "production" ]]; then
    if echo "$CMD" | grep -qE '^[[:space:]]*git[[:space:]]+push([[:space:]]|$)'; then
      block "Pushing while on '${BRANCH}' branch is forbidden. Switch to a feature branch."
    fi
  fi
fi

allow
