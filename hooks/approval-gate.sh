#!/usr/bin/env bash
# approval-gate.sh — block destructive operations unless the parent
# Plane issue carries the `approved-by-operator` label (or the
# operation matches a `auto-approved:*` standing approval).
#
# Hot-reload: this script is a short-lived process invoked per PreToolUse
# hook event (not a daemon). It reads trust-tiers.yml and agent-approvals.yml
# fresh on every invocation. Changes to those files take effect immediately
# on the next hook call — no daemon restart required.
#
# Operates in TWO modes:
#
# 1. Claude Code PreToolUse hook (default invocation, JSON stdin/stdout):
#       echo '<event-json>' | hooks/approval-gate.sh
#    Returns: {"decision": "allow"} or {"decision": "block", "reason": "..."}
#
# 2. CLI for the agent runner pre-flight (matches before invoking):
#       hooks/approval-gate.sh check "<command-string>" [--tool Bash|Edit|Write|...] [--category <cat>]
#    Returns: exit 0 (allow) | exit 7 (block, reason on stderr) | exit 8 (awaiting-consensus)
#
# Approval source-of-truth:
#   $WALTER_AGENT_PLANE_ISSUE     — Plane issue ID for current invocation
#   ~/.config/walter-os/agent-approvals.yml — standing approvals
#
# When a block is hit during an agent invocation, the agent runner is
# expected to post to Plane and flip the issue to `needs-operator`.
# This hook just decides + reports.
#
# Spec: docs/specs/multi-agent-autonomy.md §7

set -uo pipefail

WALTER_CONFIG="${WALTER_CONFIG:-$HOME/.config/walter-os}"
STANDING_APPROVALS="${WALTER_STANDING_APPROVALS:-$WALTER_CONFIG/agent-approvals.yml}"
TRUST_TIERS="${WALTER_TRUST_TIERS:-$WALTER_CONFIG/trust-tiers.yml}"

# ---------- block patterns (keep in lockstep with §7.1 of the spec) ----------

# Bash command patterns that match destructive ops. Each line: regex.
# These are extended regex (grep -E). Whitespace at start of pattern allowed.
declare -a BLOCK_BASH_PATTERNS=(
  # Push to protected branches
  'git[[:space:]]+push.*[[:space:]](main|master|staging|release)([[:space:]]|$|\.)'
  'git[[:space:]]+push.*--force([^-]|$)'
  'git[[:space:]]+push.*--force-with-lease'
  # Merge
  'gh[[:space:]]+pr[[:space:]]+merge'
  # Destructive shell
  '(^|[[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rRf][a-zA-Z]*[[:space:]]+|-r[[:space:]]+|-rf[[:space:]]+).*(/|~)'
  '(^|[[:space:]])dd[[:space:]]+if='
  '(^|[[:space:]])mkfs\.'
  ':\(\)\{[[:space:]]*:\|'
  '(^|[[:space:]])truncate[[:space:]]+'
  # SQL destructive (any case)
  '[Dd][Rr][Oo][Pp][[:space:]]+([Tt][Aa][Bb][Ll][Ee]|[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]|[Ss][Cc][Hh][Ee][Mm][Aa])'
  '[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]([[:space:]]|;)'
  '[Dd][Ee][Ll][Ee][Tt][Ee][[:space:]]+[Ff][Rr][Oo][Mm]'
  # Hetzner provisioning
  'hcloud[[:space:]]+(server|volume|network)[[:space:]]+(create|delete|destroy|resize)'
  # Domain registrar
  'dnscontrol[[:space:]]+push'
  # Git history rewrite
  'git[[:space:]]+filter-(branch|repo)'
  'git[[:space:]]+reset[[:space:]]+--hard'
  # Disable hooks
  'git[[:space:]]+(commit|push).*--no-verify'
  '--no-gpg-sign'
)

# Edit / Write paths that require approval. POSIX-glob style; we shell-match.
declare -a BLOCK_PATH_PATTERNS=(
  # Walter-OS contract files
  'hooks/*.sh'
  '.claude/settings.json'
  '.github/workflows/*'
  'install.sh'
  'AGENTS.md'
  'CLAUDE.md'
  'mcp/servers.json'
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

# ---------- trust tier matrix ----------
# Maps operation categories to minimum tier required.
# Categories not listed here default to allow-all (any tier can do them).
# "blocked-all" categories are hardcoded above (BLOCK_BASH_PATTERNS, BLOCK_PATH_PATTERNS)
# and cannot be overridden by trust tiers.
#
# medium-required: low tier is blocked unless the agent has an explicit override.
# high-required: low and medium tier are blocked unless override.

declare -A CATEGORY_MIN_TIER=(
  [git-push-feature-branch]="medium"
  [gh-pr-create]="medium"
  [write-source-files-feature-branch]="medium"
  [write-wiki-pages]="medium"
  [create-plane-issue]="low"    # low+ = everyone
  [read-any-file]="low"
  [run-tests-linters]="low"
  [gh-pr-comment]="low"
  [gh-pr-review-approve]="high"
)

# Tier ordering: low=1, medium=2, high=3
_tier_rank() {
  case "$1" in
    low)    echo 1 ;;
    medium) echo 2 ;;
    high)   echo 3 ;;
    *)      echo 0 ;;
  esac
}

# classify_command <tool> <payload> → category name or empty string
# Returns the category slug for a command, or empty if not categorizable.
_classify_command() {
  local tool="$1" payload="$2"
  case "$tool" in
    Bash)
      # git push to feature/* — but NOT force push (force-push is blocked-all)
      if [[ "$payload" =~ git[[:space:]]+push.*feature/ ]] && \
         ! [[ "$payload" =~ --force([^-]|$)|--force-with-lease ]]; then
        echo "git-push-feature-branch"; return
      fi
      # gh pr create
      if [[ "$payload" =~ gh[[:space:]]+pr[[:space:]]+create ]]; then
        echo "gh-pr-create"; return
      fi
      # gh pr comment
      if [[ "$payload" =~ gh[[:space:]]+pr[[:space:]]+comment ]]; then
        echo "gh-pr-comment"; return
      fi
      # gh pr review --approve
      if [[ "$payload" =~ gh[[:space:]]+pr[[:space:]]+review.*--approve ]]; then
        echo "gh-pr-review-approve"; return
      fi
      # Test / lint runners
      if [[ "$payload" =~ (bats|pytest|cargo[[:space:]]+test|pnpm[[:space:]]+test|npm[[:space:]]+test|eslint|shellcheck|ruff|clippy) ]]; then
        echo "run-tests-linters"; return
      fi
      ;;
    Edit|Write|MultiEdit|NotebookEdit)
      # Never apply trust-tier override to paths that are in BLOCK_PATH_PATTERNS
      # (those are blocked-for-all and cannot be tier-overridden).
      if matches_any_glob "$payload" "${BLOCK_PATH_PATTERNS[@]}"; then
        echo ""; return
      fi
      # Wiki pages
      if [[ "$payload" =~ ^wiki/ ]]; then
        echo "write-wiki-pages"; return
      fi
      # Source files — categorize for tier enforcement
      if [[ "$payload" =~ \.(ts|tsx|js|jsx|py|rs|go|sh|md)$ ]]; then
        echo "write-source-files-feature-branch"; return
      fi
      ;;
  esac
  echo ""
}

# trust_tier_allows <agent> <category> -> 0 (allow) | 1 (block by tier)
# Returns 0 if the agent's trust tier (+ overrides) permits this category.
# Fail-closed for protected tiered categories when trust-tiers.yml or yq is
# missing. Low-risk categories remain allowed so read/test commands do not
# break on a partially installed workstation.
_trust_tier_allows() {
  local agent="$1" category="$2"
  local min_tier="${CATEGORY_MIN_TIER[$category]:-low}"

  if [[ ! -f "$TRUST_TIERS" ]]; then
    [[ "$min_tier" == "low" ]] && return 0
    return 1
  fi
  if ! command -v yq >/dev/null 2>&1; then
    [[ "$min_tier" == "low" ]] && return 0
    return 1
  fi

  # Read agent tier
  local tier
  tier=$(yq ".agents.${agent}.tier // \"\"" "$TRUST_TIERS" 2>/dev/null)
  [[ -z "$tier" || "$tier" == "null" ]] && return 1

  # Check per-agent override first
  local override
  override=$(yq ".agents.${agent}.overrides[\"${category}\"] // \"\"" "$TRUST_TIERS" 2>/dev/null)
  if [[ "$override" == "allow" ]]; then
    return 0
  elif [[ "$override" == "block" ]]; then
    return 1
  fi

  # Apply tier matrix
  local agent_rank min_rank
  agent_rank=$(_tier_rank "$tier")
  min_rank=$(_tier_rank "$min_tier")

  [[ "$agent_rank" -ge "$min_rank" ]]
}

# ---------- decision logic ----------

reason=""
decision="allow"
PANIC_LOCKED=0

# Helper: regex match (returns 0 if matches)
matches_any_regex() {
  local input="$1"
  shift
  local pat
  for pat in "$@"; do
    if [[ "$input" =~ $pat ]]; then
      return 0
    fi
  done
  return 1
}

# Helper: glob match against a list of patterns (returns 0 if any matches)
matches_any_glob() {
  local path="$1"
  shift
  local pat
  for pat in "$@"; do
    # shellcheck disable=SC2053 # we want glob semantics, not regex
    [[ "$path" == $pat || "$path" == */$pat || "$path" == $pat/* ]] && return 0
  done
  return 1
}

# Helper: the parent Plane issue (if any) carries `approved-by-operator`
plane_issue_approved() {
  local issue_id="${WALTER_AGENT_PLANE_ISSUE:-}"
  [[ -z "$issue_id" ]] && return 1
  [[ -z "${PLANE_API_TOKEN:-}" || -z "${PLANE_API_URL:-}" || -z "${PLANE_WORKSPACE:-}" || -z "${PLANE_PROJECT:-}" ]] && return 1
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local resp
  resp=$(curl -fsS -m 5 -H "X-Api-Key: $PLANE_API_TOKEN" \
    "${PLANE_API_URL}/workspaces/${PLANE_WORKSPACE}/projects/${PLANE_PROJECT}/issues/${issue_id}/" 2>/dev/null) || return 1

  echo "$resp" | jq -e '.label_names // [] | any(. == "approved-by-operator")' >/dev/null 2>&1
}

# Helper: matches a standing-approval rule
matches_standing_approval() {
  local agent="$1" tool="$2" target="$3"
  [[ -f "$STANDING_APPROVALS" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1

  # Whitelist agent name before passing to yq to prevent expression injection.
  # An attacker who controls WALTER_AGENT_NAME could inject yq syntax that
  # makes select() always true, bypassing the gate.
  # See: docs/operational/security-audit-2026-05-11.md P0-02
  case "$agent" in
    triage|researcher|coder|reviewer|janitor|liaison|test-agent|unknown) ;;
    *) return 1 ;;
  esac

  # Fetch matching rules: where rules.<key>.agent == $agent
  local rules
  rules=$(yq ".auto_approved // {} | to_entries[] | select(.value.agent == \"$agent\") | .key" "$STANDING_APPROVALS" 2>/dev/null)
  [[ -z "$rules" ]] && return 1

  # For each rule, check tool/target constraint heuristically.
  # NOTE: this is the blunt allow-list. Fine-grained constraint validation
  # happens in the per-rule checker invoked by the agent runner. We just
  # confirm a rule EXISTS for this (agent, tool, target) combo.
  local rule
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    case "$rule" in
      lint-fixes)
        [[ "$tool" == "Edit" || "$tool" == "Write" ]] || continue
        [[ "$target" =~ \.(ts|tsx|js|jsx|py|rs|go)$ ]] && return 0
        ;;
      dep-bumps)
        [[ "$tool" == "Edit" ]] || continue
        [[ "$target" =~ (package\.json|package-lock\.json|Cargo\.toml|requirements\.txt|pyproject\.toml|go\.mod)$ ]] && return 0
        ;;
      wiki-content)
        [[ "$tool" == "Edit" || "$tool" == "Write" ]] || continue
        [[ "$target" =~ ^wiki/ ]] && return 0
        ;;
    esac
  done <<< "$rules"
  return 1
}

# Helper: produce a block decision
block() {
  reason="$1"
  decision="block"
}

# Helper: check trust tier for the current operation.
# If the operation is categorizable and the agent's tier disallows it,
# sets decision=block. If the decision is already block and the tier
# allows the category, flips to allow (tier override).
# Fails closed for protected tiered categories when yq or trust-tiers.yml is
# missing, while low-risk categories remain usable.
apply_trust_tier() {
  local tool="$1" payload="$2" agent="${WALTER_AGENT_NAME:-unknown}"
  local category
  category=$(_classify_command "$tool" "$payload")
  [[ -z "$category" ]] && return 0

  if [[ "$decision" == "allow" ]]; then
    # Check if this tier-restricted category requires a higher tier.
    if ! _trust_tier_allows "$agent" "$category"; then
      local agent_tier
      if [[ -f "$TRUST_TIERS" ]] && command -v yq >/dev/null 2>&1; then
        agent_tier=$(yq ".agents.${agent}.tier // \"unknown\"" "$TRUST_TIERS" 2>/dev/null || echo "unknown")
      else
        agent_tier="unavailable"
      fi
      block "trust tier '${agent_tier}' does not permit category '$category' (agent: $agent)"
    fi
  elif [[ "$decision" == "block" && "$PANIC_LOCKED" -eq 0 ]]; then
    # The command was blocked by pattern, but trust tier may override.
    if _trust_tier_allows "$agent" "$category"; then
      decision="allow"
      reason="trust tier override: category '$category' permitted for agent '$agent'"
    fi
  fi
}

# Helper: check if gate.lock exists (written by alert_emit panic in alerts.sh).
# If it does, sets decision=block + reason. Returns 0 if lock active, 1 otherwise.
check_panic_lock() {
  local lock_file="${GATE_LOCK:-${WALTER_CONFIG}/gate.lock}"
  if [[ -f "$lock_file" ]]; then
    local lock_content
    lock_content="$(cat "$lock_file" 2>/dev/null || echo 'unknown')"
    # Escape gate.lock content for safe embedding in JSON reason string.
    # Use python3 json.dumps to handle newlines, tabs, control chars, quotes.
    local lock_content_escaped
    if command -v python3 >/dev/null 2>&1; then
      lock_content_escaped="$(printf '%s' "$lock_content" | \
        python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip()))")"
    else
      # Bash fallback: cover the most dangerous chars for JSON strings
      local s="${lock_content//\\/\\\\}"
      s="${s//\"/\\\"}"
      s="${s//$'\n'/\\n}"
      s="${s//$'\r'/\\r}"
      s="${s//$'\t'/\\t}"
      lock_content_escaped="\"${s}\""
    fi
    block "council in panic lock (not overridable) — run: walter-os agents unlock --reason '...'. Lock: ${lock_content_escaped}"
    PANIC_LOCKED=1
    return 0
  fi
  return 1
}

# ---------- analyze command / path ----------

analyze() {
  local tool="$1"
  local payload="$2"

  case "$tool" in
    Bash)
      if matches_any_regex "$payload" "${BLOCK_BASH_PATTERNS[@]}"; then
        block "Bash command matches blocked pattern: ${payload:0:120}"
      fi
      ;;
    Edit|Write|MultiEdit|NotebookEdit)
      if matches_any_glob "$payload" "${BLOCK_PATH_PATTERNS[@]}"; then
        block "Edit/Write to protected path: $payload"
      fi
      ;;
    *)
      # Other tools (Read, Grep, Glob, etc.) — fast-path allow.
      :
      ;;
  esac
}

# ---------- consensus eligibility ----------
# Categories that are eligible for consensus auto-approval when consensus mode is ON.
# These are low-risk categories where the Council can vote without operator.
declare -a CONSENSUS_ELIGIBLE_CATEGORIES=(
  lint-fix
  minor-patch-dep-bump
  doc-update
  wiki-edit
  refactor-small
  formatting
  comment-change
  tests-only-pr
)

# Categories that are ALWAYS ineligible for consensus — always requires human.
# This includes all "blocked-for-all" categories plus high-blast-radius ops.
declare -a CONSENSUS_INELIGIBLE_CATEGORIES=(
  push-to-main-staging-release
  gh-pr-merge
  force-push-any-branch
  modify-hooks
  modify-agent-definitions
  destructive-shell
  sql-destructive
  http-delete-managed-services
  money-spending
  public-communication
  auth-crypto-phi-files
  env-file-writes
  production-db-migration
  prod-db-migration
  major-dep-bump
)

# consensus_eligible <category> → 0 if eligible for council vote, 1 if not
# Returns 0 (eligible) or 1 (ineligible).
# Ineligible = always requires human operator regardless of consensus mode.
consensus_eligible() {
  local category="$1"
  [[ -z "$category" ]] && return 1

  # Check explicitly ineligible list first
  for inelig in "${CONSENSUS_INELIGIBLE_CATEGORIES[@]}"; do
    [[ "$category" == "$inelig" ]] && return 1
  done

  # Check eligible list
  for elig in "${CONSENSUS_ELIGIBLE_CATEGORIES[@]}"; do
    [[ "$category" == "$elig" ]] && return 0
  done

  # Unknown category: not explicitly eligible → ineligible (conservative)
  return 1
}

# consensus_mode_is_on → 0 if consensus mode is ON, 1 otherwise.
# Reads mode.json from WALTER_CONFIG.
consensus_mode_is_on() {
  local mode_file="${WALTER_CONFIG}/mode.json"
  [[ -f "$mode_file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local val
  val=$(jq -r '.consensus // false' "$mode_file" 2>/dev/null || echo "false")
  [[ "$val" == "true" ]]
}

# ---------- mode selection ----------

if [[ $# -gt 0 ]]; then
  # CLI mode
  case "$1" in
    check)
      shift
      cli_command="${1:-}"
      shift || true
      cli_tool="Bash"
      cli_category=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --tool)     cli_tool="$2"; shift 2 ;;
          --category) cli_category="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      [[ -z "$cli_command" ]] && { echo "Usage: $0 check <command> [--tool <Tool>] [--category <cat>]" >&2; exit 2; }

      # Panic lock check — must run before any pattern matching.
      check_panic_lock || true

      if [[ "$decision" == "allow" ]]; then
        analyze "$cli_tool" "$cli_command"
      fi

      # Trust tier check: applied after analyze() but before standing approvals.
      # PANIC_LOCKED check is inside apply_trust_tier (via decision check).
      if [[ "$PANIC_LOCKED" -eq 0 ]]; then
        apply_trust_tier "$cli_tool" "$cli_command"
      fi

      if [[ "$decision" == "block" && "$PANIC_LOCKED" -eq 0 ]]; then
        # Standing-approval check (CLI-mode hint: WALTER_AGENT_NAME env)
        # Guard: skip entirely when PANIC_LOCKED — panic lock is terminal, no override allowed.
        agent="${WALTER_AGENT_NAME:-unknown}"
        if matches_standing_approval "$agent" "$cli_tool" "$cli_command"; then
          decision="allow"
          reason="standing approval matched"
        elif plane_issue_approved; then
          decision="allow"
          reason="approved-by-operator label present on Plane issue ${WALTER_AGENT_PLANE_ISSUE:-?}"
        fi
      fi

      # Consensus mode check: if still blocked and consensus mode is ON,
      # check if this category is consensus-eligible → exit 8 (awaiting-consensus).
      # Exit 8 means: "don't execute, trigger council vote instead of operator escalation."
      # PANIC_LOCKED: panic lock always wins — never exit 8 when panic locked.
      if [[ "$decision" == "block" && "$PANIC_LOCKED" -eq 0 ]]; then
        if consensus_mode_is_on; then
          # Use explicit --category if given, else try to classify the command
          effective_category="$cli_category"
          [[ -z "$effective_category" ]] && effective_category=$(_classify_command "$cli_tool" "$cli_command")
          if [[ -n "$effective_category" ]] && consensus_eligible "$effective_category"; then
            echo "approval-gate: awaiting-consensus — category '$effective_category' eligible for council vote" >&2
            exit 8
          fi
        fi
      fi

      if [[ "$decision" == "allow" ]]; then
        [[ -n "$reason" ]] && echo "approval-gate: allow — $reason"
        exit 0
      else
        echo "approval-gate: BLOCK — $reason" >&2
        exit 7
      fi
      ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Usage: $0 check <command> [--tool <Tool>] | $0 -h" >&2
      exit 2
      ;;
  esac
fi

# Hook mode (PreToolUse via stdin JSON)
# Use read builtin instead of cat to avoid depending on external command availability
# when jq is intentionally hidden for testing (P0-03 test uses empty PATH).
input=""
while IFS= read -r _line 2>/dev/null; do
  input="${input}${_line}"$'\n'
done
input="${input%$'\n'}"
if [[ -z "$input" ]]; then
  echo '{"decision":"allow"}'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Fail CLOSED — without jq we cannot parse the hook event or enforce policy.
  # Allowing all ops when jq is missing would let an attacker bypass the gate
  # by shadowing jq on PATH. See: docs/operational/security-audit-2026-05-11.md P0-03
  echo "approval-gate: jq missing — failing closed for safety. Install jq to proceed." >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"approval-gate: jq missing — failing closed for safety"}}\n'
  exit 0
fi

tool=$(echo "$input" | jq -r '.tool_name // ""')

# Extract the relevant payload per tool
case "$tool" in
  Bash)
    payload=$(echo "$input" | jq -r '.tool_input.command // ""')
    ;;
  Edit|MultiEdit)
    payload=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    ;;
  Write|NotebookEdit)
    payload=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    ;;
  *)
    payload=""
    ;;
esac

# Panic lock check — must run before any pattern matching.
check_panic_lock || true

if [[ "$decision" == "allow" ]]; then
  analyze "$tool" "$payload"
fi

# Trust tier check: applied after analyze(), before standing approvals.
if [[ "$PANIC_LOCKED" -eq 0 ]]; then
  apply_trust_tier "$tool" "$payload"
fi

if [[ "$decision" == "block" && "$PANIC_LOCKED" -eq 0 ]]; then
  # Guard: skip when PANIC_LOCKED — panic lock is terminal, no override allowed.
  agent="${WALTER_AGENT_NAME:-unknown}"
  if matches_standing_approval "$agent" "$tool" "$payload"; then
    decision="allow"
    reason="standing approval matched"
  elif plane_issue_approved; then
    decision="allow"
    reason="approved-by-operator label present"
  fi
fi

if [[ "$decision" == "allow" ]]; then
  echo '{"decision":"allow"}'
else
  jq -nc --arg r "$reason" '{"decision":"block","reason":$r}'
fi
