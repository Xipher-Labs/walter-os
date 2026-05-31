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

WALTER_HOOK_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALTER_OS_HOME="$WALTER_HOOK_REPO_ROOT"
if [[ -f "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" ]]; then
  # shellcheck source=/dev/null
  source "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" || true
fi

audit_branch_flow_decision() {
  local decision="$1" reason="${2:-}" input_summary="${3:-${CMD:-}}"
  if declare -F walter_audit_append >/dev/null 2>&1; then
    walter_audit_append Bash "$input_summary" "$decision" "branch-flow-guard" "$reason" >/dev/null 2>&1 || {
      printf '%s\n' '{"decision":"block","reason":"branch-flow-guard: audit-chain append failed; refusing unaudited decision"}'
      exit 0
    }
  else
    printf '%s\n' '{"decision":"block","reason":"branch-flow-guard: audit-chain writer unavailable; refusing unaudited decision"}'
    exit 0
  fi
}

# Source operator overlay if present. The hook is invoked from Claude Code's
# PreToolUse layer with a minimal inherited env, so WALTER_BRANCH_FLOW set in
# the operator's overlay (~/.config/walter-os/overlay/personal.env) is not
# visible unless we source the file ourselves. set +u/-u guards against
# `set -u` aborts inside the overlay (some operator overlays reference
# variables they themselves define later in the file).
_OVERLAY_PERSONAL_ENV="${HOME}/.config/walter-os/overlay/personal.env"
if [[ -f "$_OVERLAY_PERSONAL_ENV" ]]; then
  set +u
  # shellcheck source=/dev/null
  source "$_OVERLAY_PERSONAL_ENV"
  set -u
fi
unset _OVERLAY_PERSONAL_ENV

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
  audit_branch_flow_decision allow
  echo '{"decision":"allow"}'
  exit 0
}

block() {
  local reason="$1"
  audit_branch_flow_decision block "$reason"
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

# ---------- 2. Branch flow: enforce the mode's PR-base policy ----------
# single-tier — feature/* targets main (or master/repo default) directly;
#               anything else is blocked.
# three-stage — feature → dev → staging → main; --allow-branch-skip
#               bypasses with a justification.

if echo "$CMD" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create'; then
  # Try to extract --base flag; default to repo's default branch.
  BASE="$(echo "$CMD" | grep -oE -- '--base[[:space:]]+[^[:space:]]+' | awk '{print $2}' || echo "")"
  if [[ -z "$BASE" ]]; then
    BASE="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")"
  fi

  if [[ "$BRANCH_FLOW" == "single-tier" ]]; then
    # Default branch is whatever origin/HEAD points at (usually main, sometimes
    # master). Both are acceptable PR bases for feature/* in single-tier mode.
    DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")"
    case "$BRANCH" in
      feature/*|fix/*|chore/*)
        if [[ "$BASE" != "$DEFAULT_BRANCH" && "$BASE" != "main" && "$BASE" != "master" ]]; then
          block "Branch flow (single-tier): feature branches must target the default branch ('${DEFAULT_BRANCH}' / main / master), not '${BASE}'. Set WALTER_BRANCH_FLOW=three-stage in your overlay if you need a dev/staging promotion chain."
        fi
        ;;
    esac
  elif [[ "$BRANCH_FLOW" == "three-stage" ]]; then
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
