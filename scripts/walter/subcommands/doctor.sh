#!/usr/bin/env bash
# walter doctor — diagnose install state of Walter-OS on this Mac
#
# Usage:
#   walter doctor                  full check (local + remote)
#   walter doctor --client-only    local tools only, skip SSH/remote checks
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

# ---------- arg parse ----------
CLIENT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --client-only) CLIENT_ONLY=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "doctor: unknown option: $arg" >&2; exit 2 ;;
  esac
done

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

log_step "Walter-OS doctor"

check "WALTER_OS_HOME exists ($WALTER_OS_HOME)" "[[ -d '$WALTER_OS_HOME' ]]"
check "AGENTS.md present"             "[[ -f '$WALTER_OS_HOME/AGENTS.md' ]]"
check "~/.claude/CLAUDE.md symlink"   "[[ -L $HOME/.claude/CLAUDE.md ]]"
check "~/.codex/AGENTS.md symlink"    "[[ -L $HOME/.codex/AGENTS.md ]]"
check "~/.config/walter-os/secrets.env mode 600" "[[ \$(stat -f %A '$HOME/.config/walter-os/secrets.env' 2>/dev/null) == '600' ]]"

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
checkw "Anthropic API key set"        "[[ -n \$(grep ANTHROPIC_API_KEY $HOME/.config/walter-os/secrets.env 2>/dev/null | cut -d= -f2 | tr -d \"'\\\"\") ]]"
checkw "OpenAI API key set"           "[[ -n \$(grep OPENAI_API_KEY $HOME/.config/walter-os/secrets.env 2>/dev/null | cut -d= -f2 | tr -d \"'\\\"\") ]]"

echo
echo "Result: $ok ok / $warn warn / $fail fail"
[[ $fail -gt 0 ]] && exit 1 || exit 0
