#!/usr/bin/env bash
# branch-flow-guard.sh
# Enforces: feature/* → dev → staging → main
# Also: blocks auto-PR creation on remotes matching WALTER_MANUAL_PR_REMOTE_PATTERN
# (opt-in, default disabled).
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
#
# Example (.env.local or secrets.env):
#   WALTER_MANUAL_PR_REMOTE_PATTERN=acme-corp   # enforce on remotes containing "acme-corp"
#   WALTER_MANUAL_PR_OVERRIDE_FLAG=--allow-acme-pr  # optional custom bypass flag

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

# ---------- 2. Branch flow: enforce next-level merge ----------

if echo "$CMD" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create'; then
  # Try to extract --base flag; default to current default branch
  BASE="$(echo "$CMD" | grep -oE -- '--base[[:space:]]+[^[:space:]]+' | awk '{print $2}' || echo "")"
  if [[ -z "$BASE" ]]; then
    BASE="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")"
  fi

  case "$BRANCH" in
    feature/*|fix/*|chore/*)
      if [[ "$BASE" != "dev" ]]; then
        if ! echo "$CMD" | grep -q -- '--allow-branch-skip'; then
          block "Branch flow: feature branches must target 'dev', not '${BASE}'. Use --allow-branch-skip with justification for hotfixes."
        fi
      fi
      ;;
    dev)
      if [[ "$BASE" != "staging" ]]; then
        if ! echo "$CMD" | grep -q -- '--allow-branch-skip'; then
          block "Branch flow: 'dev' must merge to 'staging', not '${BASE}'."
        fi
      fi
      ;;
    staging)
      if [[ "$BASE" != "main" ]]; then
        if ! echo "$CMD" | grep -q -- '--allow-branch-skip'; then
          block "Branch flow: 'staging' must merge to 'main', not '${BASE}'."
        fi
      fi
      ;;
  esac
fi

# ---------- 3. Block direct push to protected branches ----------

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
