#!/usr/bin/env bash
# branch-flow-guard.sh
# Enforces the Walter-OS branch policy at the Claude Code PreToolUse layer.
#
# Two modes are supported (see docs/decisions/0013-solo-operator-merge-policy.md):
#
#   WALTER_BRANCH_FLOW=single-tier  (default — solo operator, small team)
#     - feature/<slug> can target main directly
#     - direct push to main / master / staging / production is forbidden
#
#   WALTER_BRANCH_FLOW=three-stage  (team with dev / staging environments)
#     - feature/* must target dev
#     - dev must target staging
#     - staging must target main
#     - --allow-branch-skip with justification is the documented bypass
#     - direct push to main / master / staging / production is still forbidden
#
# Set WALTER_BRANCH_FLOW in your overlay (~/.config/walter-os/overlay/personal.env)
# to opt in to three-stage. When unset, the hook behaves as single-tier.
#
# Additional optional gate (independent of branch flow):
#   WALTER_MANUAL_PR_REMOTE_PATTERN — substring of remote URL forces
#     manual PR creation on matching remotes (agent prints the command
#     instead of running it). Override via WALTER_MANUAL_PR_OVERRIDE_FLAG
#     (default: --allow-manual-pr).
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

# Branch-flow mode: defaults to single-tier when unset or set to anything
# other than the recognized "three-stage" value.
BRANCH_FLOW="${WALTER_BRANCH_FLOW:-single-tier}"
if [[ "$BRANCH_FLOW" != "single-tier" && "$BRANCH_FLOW" != "three-stage" ]]; then
  # Treat unknown values as single-tier rather than blocking entirely —
  # a typo in the operator's overlay should not break the day's workflow.
  BRANCH_FLOW="single-tier"
fi

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

# ---------- 2. Branch flow: three-stage mode enforces next-level merge ----------
# In single-tier mode this section is a no-op; feature/* can target main
# directly. In three-stage mode it enforces the original gate.

if [[ "$BRANCH_FLOW" == "three-stage" ]] && \
   echo "$CMD" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create'; then
  # Try to extract --base flag; default to current default branch.
  BASE="$(echo "$CMD" | grep -oE -- '--base[[:space:]]+[^[:space:]]+' | awk '{print $2}' || echo "")"
  if [[ -z "$BASE" ]]; then
    BASE="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")"
  fi

  case "$BRANCH" in
    feature/*|fix/*|chore/*)
      if [[ "$BASE" != "dev" ]]; then
        if ! echo "$CMD" | grep -q -- '--allow-branch-skip'; then
          block "Branch flow (three-stage): feature branches must target 'dev', not '${BASE}'. Use --allow-branch-skip with justification for hotfixes."
        fi
      fi
      ;;
    dev)
      if [[ "$BASE" != "staging" ]]; then
        if ! echo "$CMD" | grep -q -- '--allow-branch-skip'; then
          block "Branch flow (three-stage): 'dev' must merge to 'staging', not '${BASE}'."
        fi
      fi
      ;;
    staging)
      if [[ "$BASE" != "main" ]]; then
        if ! echo "$CMD" | grep -q -- '--allow-branch-skip'; then
          block "Branch flow (three-stage): 'staging' must merge to 'main', not '${BASE}'."
        fi
      fi
      ;;
  esac
fi

# ---------- 3. Block direct push to (or from) protected branches ----------
# This applies in both modes.

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
