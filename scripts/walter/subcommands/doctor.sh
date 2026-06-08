#!/usr/bin/env bash
# walter doctor — diagnose install state of Walter-OS on this Mac
#
# Usage:
#   walter doctor                  full check (local + remote)
#   walter doctor --client-only    local tools only, skip SSH/remote checks
#   walter doctor --enforcement    report hook/wrapper enforcement mode
#   walter doctor --hooks          alias for --enforcement
#   walter doctor --hook-enforcement
#                                  alias for --enforcement
set -euo pipefail

# Validate WALTER_OS_HOME before any use: must be an absolute path containing
# only safe characters. Reject single quotes, semicolons, $, backticks, etc.
# This prevents injection via check() even if eval is used inside.
# See: docs/operational/security-audit-2026-05-11.md P0-04
WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
if [[ ! "$WALTER_OS_HOME" =~ ^[A-Za-z0-9/_.-]+$ ]]; then
  echo "doctor: invalid WALTER_OS_HOME value (contains unsafe characters)" >&2
  exit 2
fi
while [[ "$WALTER_OS_HOME" != "/" && "$WALTER_OS_HOME" == */ ]]; do
  WALTER_OS_HOME="${WALTER_OS_HOME%/}"
done
WALTER_CONFIG="${WALTER_CONFIG:-$HOME/.config/walter-os}"

# ---------- arg parse ----------
CLIENT_ONLY=0
ENFORCEMENT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --client-only) CLIENT_ONLY=1 ;;
    --enforcement|--hooks|--hook-enforcement) ENFORCEMENT_ONLY=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "doctor: unknown option: $arg" >&2; exit 2 ;;
  esac
done

# shellcheck source=/dev/null
source "$WALTER_OS_HOME/scripts/walter/lib/log.sh"

ok=0; warn=0; fail=0

# check() and checkw() run test commands via bash -c in a subshell.
# The cmd strings are hardcoded in this file (not attacker-controlled),
# but we use bash -c instead of eval to isolate each check and avoid
# polluting the main shell's environment.
check() {
  local label="$1" cmd="$2"
  if bash -c "$cmd" >/dev/null 2>&1; then
    log_ok "$label"
    ok=$((ok + 1))
  else
    log_err "$label"
    fail=$((fail + 1))
  fi
}
checkw() {
  local label="$1" cmd="$2"
  if bash -c "$cmd" >/dev/null 2>&1; then
    log_ok "$label"
    ok=$((ok + 1))
  else
    log_warn "$label"
    warn=$((warn + 1))
  fi
}
check_secret_runtime() {
  local secrets_file="$WALTER_CONFIG/secrets.env"
  local env_file="$WALTER_CONFIG/env"
  local has_infisical=0

  if [[ -n "${INFISICAL_CLIENT_ID:-}" ]] \
      || ([[ -f "$env_file" ]] && grep -qE '^(export[[:space:]]+)?INFISICAL_CLIENT_ID=.+' "$env_file" 2>/dev/null); then
    has_infisical=1
  fi

  if [[ "$has_infisical" -eq 1 && ! -f "$secrets_file" ]]; then
    log_ok "Infisical runtime configured (no legacy secrets.env)"
    ok=$((ok + 1))
  elif [[ "$has_infisical" -eq 1 && -f "$secrets_file" ]]; then
    log_warn "Infisical runtime configured; legacy plaintext secrets.env still exists"
    warn=$((warn + 1))
    check_legacy_secrets_file_mode "$secrets_file"
  elif [[ -f "$secrets_file" ]]; then
    log_warn "legacy plaintext secrets.env detected; migrate to Infisical machine identity"
    warn=$((warn + 1))
    check_legacy_secrets_file_mode "$secrets_file"
  else
    log_err "secrets runtime missing (configure Infisical identity or legacy secrets.env)"
    fail=$((fail + 1))
  fi
}
check_legacy_secrets_file_mode() {
  local secrets_file="$1"
  local mode

  mode="$(stat -c '%a' "$secrets_file" 2>/dev/null || stat -f '%Lp' "$secrets_file" 2>/dev/null || true)"
  if [[ "$mode" == "600" ]]; then
    log_ok "legacy secrets.env mode 600"
    ok=$((ok + 1))
  else
    log_warn "legacy secrets.env mode should be 600"
    warn=$((warn + 1))
  fi
}
check_legacy_secret_key() {
  local label="$1" key="$2"
  local secrets_file="$WALTER_CONFIG/secrets.env"

  if [[ ! -f "$secrets_file" ]]; then
    log_info "$label skipped (no legacy secrets.env; use Infisical runtime)"
    return
  fi

  if grep -E "^(export[[:space:]]+)?${key}=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "'\"" | grep -q .; then
    log_ok "$label"
    ok=$((ok + 1))
  else
    log_warn "$label"
    warn=$((warn + 1))
  fi
}

doctor_claude_hook_present() {
  local settings="$1" hook_path="$2" matcher="$3"

  jq -e --arg hook "$hook_path" --arg matcher "$matcher" '
    def matcher_applies($expected):
      . == "*" or ((split("|") | index($expected)) != null);

    [(.hooks.PreToolUse // [])[]?
      | select((.matcher // "*") | matcher_applies($matcher))
      | (.hooks // [])[]?
      | select(._walter_os == true)
      | (.command // "")
      | select(contains($hook))]
    | length > 0
  ' "$settings" >/dev/null 2>&1
}

doctor_check_claude_hooks() {
  local settings="${CLAUDE_HOME:-$HOME/.claude}/settings.json"
  local hook
  local matcher
  local hook_path
  local missing=0
  local present=0
  local -a required_hooks=(
    "$WALTER_OS_HOME/hooks/bash-denylist.sh|Bash"
    "$WALTER_OS_HOME/hooks/approval-gate.sh|Bash"
    "$WALTER_OS_HOME/hooks/capability-check.sh|Bash"
    "$WALTER_OS_HOME/hooks/network-gate.sh|Bash"
    "$WALTER_OS_HOME/hooks/branch-flow-guard.sh|Bash"
    "$WALTER_OS_HOME/hooks/pre-commit-tests.sh|Bash"
    "$WALTER_OS_HOME/hooks/approval-gate.sh|Read"
    "$WALTER_OS_HOME/hooks/approval-gate.sh|Write"
    "$WALTER_OS_HOME/hooks/capability-check.sh|Write"
    "$WALTER_OS_HOME/hooks/wiki-validator-hook.sh|Write"
  )

  if [[ ! -f "$settings" ]]; then
    log_warn "Claude Code hooks missing ($settings not found)"
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_warn "Claude Code hooks unknown (jq missing; cannot inspect settings.json)"
    return 1
  fi

  if ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    if jq -e . "$settings" >/dev/null 2>&1; then
      log_warn "Claude Code hooks unknown ($settings top-level JSON is not an object)"
    else
      log_warn "Claude Code hooks unknown ($settings is not valid JSON)"
    fi
    return 1
  fi

  for hook in "${required_hooks[@]}"; do
    hook_path="${hook%|*}"
    matcher="${hook##*|}"
    if doctor_claude_hook_present "$settings" "$hook_path" "$matcher"; then
      present=$((present + 1))
    else
      log_warn "Claude Code hook missing: ${hook_path#"$WALTER_OS_HOME"/} for $matcher"
      missing=$((missing + 1))
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    log_ok "Claude Code PreToolUse hooks active"
    return 0
  fi

  if [[ "$present" -gt 0 ]]; then
    log_warn "Claude Code PreToolUse hooks partially active ($present/${#required_hooks[@]})"
    return 3
  fi

  return 1
}

doctor_check_wrapper_path() {
  local wrapper_dir="${WALTER_WRAPPER_DIR:-}"
  local first_path tool resolved path_entry
  local installed=0
  local wrapped=0
  local wrapper_in_path=0
  local -a high_risk_tools=(gh curl hcloud cloudflared docker vercel railway stripe)
  local -a path_entries=()

  if [[ -z "$wrapper_dir" ]]; then
    log_info "high-risk tool wrappers not configured (set WALTER_WRAPPER_DIR to enable this check)"
    return 1
  fi

  if [[ ! -d "$wrapper_dir" ]]; then
    log_warn "wrapper PATH not configured ($wrapper_dir missing)"
    return 1
  fi

  while [[ "$wrapper_dir" != "/" && "$wrapper_dir" == */ ]]; do
    wrapper_dir="${wrapper_dir%/}"
  done

  first_path="${PATH%%:*}"
  while [[ "$first_path" != "/" && "$first_path" == */ ]]; do
    first_path="${first_path%/}"
  done
  if [[ "$first_path" != "$wrapper_dir" ]]; then
    IFS=':' read -r -a path_entries <<<"$PATH"
    for path_entry in "${path_entries[@]}"; do
      while [[ "$path_entry" != "/" && "$path_entry" == */ ]]; do
        path_entry="${path_entry%/}"
      done
      if [[ "$path_entry" == "$wrapper_dir" ]]; then
        wrapper_in_path=1
        break
      fi
    done
    if [[ "$wrapper_in_path" -eq 1 ]]; then
      log_warn "wrapper PATH not first ($wrapper_dir must be first in PATH)"
    else
      log_warn "wrapper PATH not active ($wrapper_dir is not in PATH)"
    fi
    return 1
  fi

  for tool in "${high_risk_tools[@]}"; do
    resolved="$(type -P "$tool" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || continue
    installed=$((installed + 1))
    case "$resolved" in
      "$wrapper_dir"/*) wrapped=$((wrapped + 1)) ;;
      *) log_warn "direct binary bypass visible: $tool -> $resolved" ;;
    esac
  done

  if [[ "$installed" -gt 0 && "$installed" -eq "$wrapped" ]]; then
    log_ok "high-risk tool wrappers first in PATH"
    return 0
  fi

  if [[ "$installed" -eq 0 ]]; then
    log_warn "wrapper PATH active, but no high-risk tools were found to verify"
  fi

  return 1
}

run_enforcement_doctor() {
  local hooks_ok=0
  local hooks_any=0
  local wrappers_ok=0
  local mode="policy-only"
  local hook_status=0

  log_step "Walter-OS enforcement doctor"
  echo "Scope: host hooks + PATH wrappers. Sandboxing, token scope, and network"
  echo "controls are stronger isolation layers outside this command's scope."
  echo

  if doctor_check_claude_hooks; then
    hook_status=0
  else
    hook_status=$?
  fi
  case "$hook_status" in
    0)
      hooks_ok=1
      hooks_any=1
      ;;
    3)
      hooks_any=1
      ;;
  esac

  if doctor_check_wrapper_path; then
    wrappers_ok=1
  fi

  echo
  if [[ "$hooks_ok" -eq 1 && "$wrappers_ok" -eq 1 ]]; then
    mode="enforced"
    log_ok "Enforcement mode: $mode"
    echo "Tool calls are expected to pass through Walter hooks and wrappers."
    return 0
  fi

  if [[ "$hooks_any" -eq 1 || "$wrappers_ok" -eq 1 ]]; then
    mode="partial"
    log_warn "Enforcement mode: $mode"
    if [[ "$hooks_any" -eq 1 ]]; then
      echo "Claude Code hooks are active, but direct binary bypasses may remain."
      echo "Remediation: install/enable Walter wrappers or run high-risk work in a sandbox."
    else
      echo "High-risk wrappers are active, but supported host hooks were not detected."
      echo "Remediation: run ./install.sh --upgrade, then re-run walter doctor --enforcement."
    fi
    return 0
  fi

  log_err "Enforcement mode: $mode"
  echo "Agent instructions may still ask tools to behave safely, but Walter-OS"
  echo "could not verify that tool execution is intercepted before it runs."
  echo "Remediation: run ./install.sh --upgrade, then re-run walter doctor --enforcement."
  return 1
}

if [[ "$ENFORCEMENT_ONLY" -eq 1 ]]; then
  run_enforcement_doctor
  exit $?
fi

log_step "Walter-OS doctor"

check "WALTER_OS_HOME exists ($WALTER_OS_HOME)" "[[ -d '$WALTER_OS_HOME' ]]"
check "AGENTS.md present"             "[[ -f '$WALTER_OS_HOME/AGENTS.md' ]]"
check "\$HOME/.claude/CLAUDE.md symlink"   "[[ -L $HOME/.claude/CLAUDE.md ]]"
check "\$HOME/.codex/AGENTS.md symlink"    "[[ -L $HOME/.codex/AGENTS.md ]]"
check_secret_runtime

check "brew installed"                "command -v brew"
check "infisical CLI"                 "command -v infisical"
check "infisical session valid"       "infisical user get token 2>&1 | grep -q '^eyJ'"
check "gh CLI"                        "command -v gh"
check "gh authenticated"              "gh auth status 2>&1 | grep -qi 'logged in'"
check "cloudflared"                   "command -v cloudflared"
check "hcloud CLI"                    "command -v hcloud"
check "rclone"                        "command -v rclone"
check "jq"                            "command -v jq"
check "docker daemon (mac orbstack)"  "docker info"

if [[ $CLIENT_ONLY -ne 1 ]]; then
  checkw "ssh walter-vm reachable"    "ssh -o ConnectTimeout=5 walter-vm 'true'"
fi
check_legacy_secret_key "Anthropic API key set" "ANTHROPIC_API_KEY"
check_legacy_secret_key "OpenAI API key set" "OPENAI_API_KEY"

echo
echo "Result: $ok ok / $warn warn / $fail fail"
[[ $fail -gt 0 ]] && exit 1 || exit 0
