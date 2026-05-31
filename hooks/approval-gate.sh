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
#
# Composition with hooks/network-gate.sh (#122 OSS Trust A-2 — AC-6):
#   approval-gate handles WHAT (destructive ops + standing approvals).
#   network-gate  handles WHERE (allowed outbound hosts).
# Both run in the PreToolUse Bash chain (spec D-8: all hooks must allow).
# Either blocking → command blocked. No control-flow coupling between the
# two — they compose by both being in the chain, not by one calling the
# other.

set -uo pipefail

REPO_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PROTECTED_PATHS_LIB="${REPO_ROOT}/scripts/walter/lib/protected-paths.sh"
WALTER_CONFIG="${WALTER_CONFIG:-$HOME/.config/walter-os}"

# Standing-approvals config path is HARDCODED (audit P1-06). The env var
# `WALTER_STANDING_APPROVALS` is no longer honored as a config-pointer
# override — letting attackers point this at an attacker-controlled YAML
# (via compromised MCP env injection or a malicious operator dotfile)
# would auto-approve every blocked operation.
#
# The opt-in override path `WALTER_STANDING_APPROVALS_OVERRIDE` is
# consulted ONLY when `WALTER_AGENT_ALLOW_OVERRIDE=1` is set in the
# same shell. It exists for testing the gate against synthetic
# approvals files; using it logs a WARN to stderr every invocation.
STANDING_APPROVALS="$WALTER_CONFIG/agent-approvals.yml"
if [[ "${WALTER_AGENT_ALLOW_OVERRIDE:-0}" == "1" \
      && -n "${WALTER_STANDING_APPROVALS_OVERRIDE:-}" ]]; then
  echo "approval-gate: WARN — using override standing-approvals path: $WALTER_STANDING_APPROVALS_OVERRIDE" >&2
  STANDING_APPROVALS="$WALTER_STANDING_APPROVALS_OVERRIDE"
elif [[ -n "${WALTER_STANDING_APPROVALS:-}" ]]; then
  # Operator set the old override env var without the allow flag.
  # Ignore it but tell them so they know it's not silently taking effect.
  echo "approval-gate: WARN — WALTER_STANDING_APPROVALS env var is ignored (audit P1-06). Use WALTER_STANDING_APPROVALS_OVERRIDE with WALTER_AGENT_ALLOW_OVERRIDE=1 if you really need to override." >&2
fi

TRUST_TIERS="${WALTER_TRUST_TIERS:-$WALTER_CONFIG/trust-tiers.yml}"

# ---------- block patterns (keep in lockstep with §7.1 of the spec) ----------

if [[ ! -f "$PROTECTED_PATHS_LIB" ]]; then
  echo "approval-gate: BLOCK — missing Walter-OS protected path policy" >&2
  exit 7
fi

# shellcheck source=/dev/null
source "$PROTECTED_PATHS_LIB"

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
declare -a BLOCK_PATH_PATTERNS=("${WALTER_PROTECTED_PATH_PATTERNS[@]}")

# ---------- trust tier matrix ----------
# Maps operation categories to minimum tier required.
# Categories not listed here default to allow-all (any tier can do them).
# "blocked-all" categories are hardcoded above (BLOCK_BASH_PATTERNS, BLOCK_PATH_PATTERNS)
# and cannot be overridden by trust tiers.
#
# medium-required: low tier is blocked unless the agent has an explicit override.
# high-required: low and medium tier are blocked unless override.

# Bash 3.2 (macOS default) misparses `[token-with-dashes]=value` inside
# `declare -A` under `set -u` — it treats the dashed token as
# `${token-with-dashes}` (default-substitution parameter expansion),
# then errors on the inner unset variable. Bash 4+ (Linux, brew bash)
# handles it correctly. Wrap the array literal in `set +u` so this
# script loads cleanly on every bash we support.
set +u
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
  [capability-token-mint]="high"
)
set -u

# Tier ordering: low=1, medium=2, high=3
_tier_rank() {
  case "$1" in
    low)    echo 1 ;;
    medium) echo 2 ;;
    high)   echo 3 ;;
    *)      echo 0 ;;
  esac
}

_shellish_normalize_payload() {
  local value="$1" backslash_newline
  backslash_newline=$'\\\n'
  value="${value//$backslash_newline/ }"
  value="${value//$'\n'/ }"
  value="${value//\$\{IFS\}/ }"
  value="${value//\$IFS/ }"
  value="${value//,/ }"
  value="${value//[/ }"
  value="${value//]/ }"
  value="${value//\\/}"
  value="${value//\"/}"
  value="${value//\'/}"
  printf '%s' "$value"
}

_is_capability_token_mint_payload() {
  local payload="$1"
  local normalized
  local walter_mint='(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?walter-os[[:space:]]+cap[[:space:]]+[$]?mint([[:space:]]|$)'
  local cap_script_mint='(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?cap\.sh[[:space:]]+[$]?mint([[:space:]]|$)'
  local shell_expansion='([$][A-Za-z_][A-Za-z0-9_]*|[$][0-9]+|[$][@*#?$!-]|[$][{]([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-])[}]|[$][(]|`)'
  local walter_dynamic_subcommand="(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?walter-os[[:space:]]+[^[:space:];|&]*${shell_expansion}"
  local walter_cap_dynamic_subcommand="(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?walter-os[[:space:]]+cap[[:space:]]+[^[:space:];|&]*${shell_expansion}"
  local walter_dynamic_command_word="(^|[[:space:];|&()])([^[:space:];|&()]*/)?[^[:space:];|&]*${shell_expansion}[^[:space:];|&]*[[:space:]]+cap[[:space:]]+[$]?mint([[:space:]]|$)"
  local walter_split_command_substitution_word='(^|[[:space:];|&()])([^[:space:];|&()]*/)?[^[:space:];|&]*[$][(][^;|&)]*[)][^[:space:];|&]*[[:space:]]+cap[[:space:]]+[$]?mint([[:space:]]|$)'
  local command_indirect_cap_mint="(^|[[:space:];|&()])${shell_expansion}[[:space:]]+cap[[:space:]]+([^[:space:];|&]*${shell_expansion}|[$]?mint)([[:space:]]|$)"
  # shellcheck disable=SC2016 # Literal $() and backticks are part of the regex.
  local command_substitution_walter_mint='(^|[[:space:];|&()])([$][(][^;|&)]*walter-os[^;|&)]*[)]|`[^;|&`]*walter-os[^;|&`]*`)[[:space:]]+cap[[:space:]]+[$]?mint([[:space:]]|$)'
  local cap_script_dynamic="(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?cap[.]sh[[:space:]]+[^[:space:];|&]*${shell_expansion}"
  local walter_ambiguous="(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?walter-os[[:space:]]+cap[[:space:]]+${shell_expansion}"
  local cap_script_ambiguous="(^|[[:space:];|&()])([^[:space:];|&()]*/)?[$]?cap\\.sh[[:space:]]+${shell_expansion}"
  local cap_function='(^|[[:space:];|&()])[$]?(cmd_cap_mint|walter_cap_sign_claims)([[:space:]]|$)'
  local cap_source='(^|[[:space:];|&()])(source|[.])[[:space:]]+[^;|&]*capability-token[.]sh([[:space:];|&()]|$)'

  normalized="$(_shellish_normalize_payload "$payload")"

  [[ "$normalized" =~ $walter_mint ]] || \
    [[ "$normalized" =~ $cap_script_mint ]] || \
    [[ "$normalized" =~ $walter_dynamic_subcommand ]] || \
    [[ "$normalized" =~ $walter_cap_dynamic_subcommand ]] || \
    [[ "$normalized" =~ $walter_dynamic_command_word ]] || \
    [[ "$normalized" =~ $walter_split_command_substitution_word ]] || \
    [[ "$normalized" =~ $command_indirect_cap_mint ]] || \
    [[ "$normalized" =~ $command_substitution_walter_mint ]] || \
    [[ "$normalized" =~ $cap_script_dynamic ]] || \
    [[ "$normalized" =~ $walter_ambiguous ]] || \
    [[ "$normalized" =~ $cap_script_ambiguous ]] || \
    [[ "$normalized" =~ $cap_function ]] || \
    [[ "$normalized" =~ $cap_source ]]
}

_is_capability_private_key_payload() {
  local payload="$1"
  local normalized
  local config_state_dir="${WALTER_CONFIG:-$HOME/.config/walter-os}/state"
  local literal_config_root="\$WALTER_CONFIG/"
  local literal_braced_config_root="\${WALTER_CONFIG}/"
  local literal_config_state="\$WALTER_CONFIG/state"
  local literal_braced_config_state="\${WALTER_CONFIG}/state"
  local literal_home_root="\$HOME/.config/walter-os/"
  local literal_braced_home_root="\${HOME}/.config/walter-os/"
  local literal_home_state="\$HOME/.config/walter-os/state"
  local literal_braced_home_state="\${HOME}/.config/walter-os/state"
  local session_artifact_re='session-[^[:space:];|&]*[.](key|json|pub)'
  local session_metadata_re='session-[^[:space:];|&]*[.](json|pub)'
  local caps_artifact_re='caps-[^[:space:];|&/]+(/[[:graph:]]*)?'
  local cap_token_artifact_re='cap-[^[:space:];|&/]*[.]paseto'
  local relative_session_secret_re='(^|[[:space:];|&])([.]/)?session-[^/[:space:];|&]*[.](key|json)([[:space:];|&]|$)'
  local relative_caps_token_re='(^|[[:space:];|&])([.]/)?caps-[^/[:space:];|&]+/cap-[^/[:space:];|&]*[.]paseto([[:space:];|&]|$)'

  normalized="$(_shellish_normalize_payload "$payload")"

  [[ "$normalized" == *"capability_private_key_path"* ]] && return 0
  [[ "$normalized" =~ $relative_session_secret_re ]] && return 0
  [[ "$normalized" =~ $relative_caps_token_re ]] && return 0

  if [[ "$normalized" == *"$config_state_dir"* ]] || \
     [[ "$normalized" == *".config/walter-os/state"* ]] || \
     [[ "$normalized" == *"$literal_config_state"* ]] || \
     [[ "$normalized" == *"$literal_braced_config_state"* ]] || \
     [[ "$normalized" == *"$literal_home_state"* ]] || \
     [[ "$normalized" == *"$literal_braced_home_state"* ]]; then
    return 0
  fi

  if [[ "$normalized" =~ (tar|zip|cp|rsync|ditto) ]] && \
     { [[ "$normalized" == *"$config_state_dir"* ]] || \
       [[ "$normalized" == *".config/walter-os/state"* ]] || \
       [[ "$normalized" == *"$literal_config_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_config_state"* ]] || \
       [[ "$normalized" == *"$literal_home_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_home_state"* ]]; }; then
    return 0
  fi

  if { [[ "$normalized" == *"$config_state_dir"* ]] || \
       [[ "$normalized" == *".config/walter-os/state"* ]] || \
       [[ "$normalized" == *"$literal_config_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_config_state"* ]] || \
       [[ "$normalized" == *"$literal_home_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_home_state"* ]]; } && \
     [[ "$normalized" =~ $cap_token_artifact_re ]]; then
    return 0
  fi

  if [[ "$normalized" == *".config/walter-os/"* ]] && \
     [[ "$normalized" =~ $session_artifact_re ]]; then
    return 0
  fi

  if [[ "$normalized" == *"$config_state_dir/"* ]] && \
     [[ "$normalized" =~ $session_artifact_re ]]; then
    return 0
  fi

  if { [[ "$normalized" == *"$config_state_dir"* ]] || \
       [[ "$normalized" == *".config/walter-os"* ]] || \
       [[ "$normalized" == *"\$WALTER_CONFIG"* ]] || \
       [[ "$normalized" == *"\${WALTER_CONFIG}"* ]] || \
       [[ "$normalized" == *"\$HOME/.config/walter-os"* ]] || \
       [[ "$normalized" == *"\${HOME}/.config/walter-os"* ]]; } && \
     [[ "$normalized" == *"/state/"* ]] && \
     [[ "$normalized" =~ $caps_artifact_re ]]; then
    return 0
  fi

  if { [[ "$normalized" == *"$literal_config_root"* ]] || \
       [[ "$normalized" == *"$literal_braced_config_root"* ]] || \
       [[ "$normalized" == *"$literal_config_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_config_state"* ]] || \
       [[ "$normalized" == *"$literal_home_root"* ]] || \
       [[ "$normalized" == *"$literal_braced_home_root"* ]] || \
       [[ "$normalized" == *"$literal_home_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_home_state"* ]]; } && \
     [[ "$normalized" =~ $caps_artifact_re ]]; then
    return 0
  fi

  if { [[ "$normalized" == *".config/walter-os"* ]] || \
       [[ "$normalized" == *"\$WALTER_CONFIG"* ]] || \
       [[ "$normalized" == *"\${WALTER_CONFIG}"* ]] || \
       [[ "$normalized" == *"\$HOME/.config/walter-os"* ]] || \
       [[ "$normalized" == *"\${HOME}/.config/walter-os"* ]]; } && \
     [[ "$normalized" == *"/state/"* ]] && \
     { [[ "$normalized" =~ [*][.]json ]] || \
       [[ "$normalized" =~ [.](key) ]] || \
       [[ "$normalized" =~ $session_metadata_re ]]; }; then
    return 0
  fi

  if { [[ "$normalized" == *"$literal_config_root"* ]] || \
       [[ "$normalized" == *"$literal_braced_config_root"* ]] || \
       [[ "$normalized" == *"$literal_config_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_config_state"* ]] || \
       [[ "$normalized" == *"$literal_home_root"* ]] || \
       [[ "$normalized" == *"$literal_braced_home_root"* ]] || \
       [[ "$normalized" == *"$literal_home_state"* ]] || \
       [[ "$normalized" == *"$literal_braced_home_state"* ]]; } && \
     [[ "$normalized" =~ $session_artifact_re ]]; then
    return 0
  fi

  return 1
}

# classify_command <tool> <payload> → category name or empty string
# Returns the category slug for a command, or empty if not categorizable.
_classify_command() {
  local tool="$1" payload="$2"
  case "$tool" in
    Bash)
      # Capability operations must preempt lower-risk categories below. A
      # compound command such as `gh pr comment ... "$(walter-os cap mint ...)"`
      # is still a capability-token mint and must not be tier-overridden as a
      # comment operation.
      if _is_capability_token_mint_payload "$payload" || _is_capability_private_key_payload "$payload"; then
        echo "capability-token-mint"; return
      fi
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
    if [[ "$category" == "capability-token-mint" ]]; then
      return 0
    fi
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
      elif _is_capability_token_mint_payload "$payload"; then
        block "capability-token-mint: Bash command mints capability token: ${payload:0:120}"
      elif _is_capability_private_key_payload "$payload"; then
        block "Bash command accesses capability private key material: ${payload:0:120}"
      fi
      ;;
    Read|Grep|Glob|LS)
      if _is_capability_private_key_payload "$payload"; then
        block "${tool} accesses capability private key material: ${payload:0:120}"
      fi
      ;;
    Edit|Write|MultiEdit|NotebookEdit)
      if _is_capability_private_key_payload "$payload"; then
        block "${tool} modifies capability private key material: ${payload:0:120}"
      elif matches_any_glob "$payload" "${BLOCK_PATH_PATTERNS[@]}"; then
        block "Edit/Write to protected path: $payload"
      fi
      ;;
    *)
      # Other tools — fast-path allow.
      :
      ;;
  esac
}

is_capability_terminal_block() {
  local tool="$1"
  local payload="$2"

  case "$tool" in
    Bash)
      _is_capability_token_mint_payload "$payload" || _is_capability_private_key_payload "$payload"
      ;;
    Read|Grep|Glob|LS|Edit|Write|MultiEdit|NotebookEdit)
      _is_capability_private_key_payload "$payload"
      ;;
    *)
      return 1
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

      if [[ "$decision" == "block" && "$PANIC_LOCKED" -eq 0 ]] && \
         ! is_capability_terminal_block "$cli_tool" "$cli_command"; then
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

if ! command -v yq >/dev/null 2>&1; then
  # Fail CLOSED — yq is required to read standing-approvals + trust-tier
  # config. Without it, those paths used to silently fall through to the
  # block path (safe in isolation), but a missing yq combined with future
  # config-format changes makes the security-path fragile. Make this a
  # hard dependency, same as jq.
  # See: docs/operational/security-audit-2026-05-11.md P1-05
  echo "approval-gate: yq missing — failing closed for safety. Install yq to proceed." >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"approval-gate: yq missing — failing closed for safety"}}\n'
  exit 0
fi

tool=$(echo "$input" | jq -r '.tool_name // ""')

# Extract the relevant payload per tool
case "$tool" in
  Bash)
    payload=$(echo "$input" | jq -r '.tool_input.command // ""')
    ;;
  Read)
    payload=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    ;;
  Grep)
    payload=$(echo "$input" | jq -r '
      .tool_input.path as $path |
      .tool_input.glob as $glob |
      [$path, $glob] | map(select(. != null)) | join(" ") as $joined |
      if ($path != null and $path != "" and $glob != null and $glob != "") then
        $joined + " " + ($path | sub("/+$"; "")) + "/" + $glob
      else
        $joined
      end
    ')
    ;;
  Glob)
    payload=$(echo "$input" | jq -r '
      .tool_input.path as $path |
      .tool_input.pattern as $pattern |
      [$path, $pattern] | map(select(. != null)) | join(" ") as $joined |
      if ($path != null and $path != "" and $pattern != null and $pattern != "") then
        $joined + " " + ($path | sub("/+$"; "")) + "/" + $pattern
      else
        $joined
      end
    ')
    ;;
  LS)
    payload=$(echo "$input" | jq -r '.tool_input.path // ""')
    ;;
  Edit|MultiEdit)
    payload=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    ;;
  Write)
    payload=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    ;;
  NotebookEdit)
    payload=$(echo "$input" | jq -r '.tool_input.notebook_path // .tool_input.file_path // ""')
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

if [[ "$decision" == "block" && "$PANIC_LOCKED" -eq 0 ]] && \
   ! is_capability_terminal_block "$tool" "$payload"; then
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
