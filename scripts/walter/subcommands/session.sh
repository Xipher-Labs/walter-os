#!/usr/bin/env bash
# scripts/walter/subcommands/session.sh
# Manage time-bounded Walter-OS session state.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"

SESSION_LIB="${WALTER_OS_HOME}/scripts/walter/lib/session-state.sh"
if [[ ! -f "$SESSION_LIB" ]]; then
  echo "walter-os session: missing session-state library: $SESSION_LIB" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$SESSION_LIB"

session_usage() {
  cat <<'EOF'
Usage: walter-os session <subcommand> [repo-path]

Subcommands:
  status [repo-path]    Print current session state JSON, or no-session.
  restart [repo-path]   Clear session state; next prompt starts a fresh session.

repo-path defaults to the current working directory.
EOF
}

session_repo() {
  printf '%s\n' "${1:-$PWD}"
}

session_status() {
  local repo file
  repo="$(session_repo "${1:-}")"
  file="$(walter_session_state_file "$repo")"
  if [[ ! -f "$file" ]]; then
    jq -nc --arg repo "$repo" --arg state_file "$file" \
      '{status:"no-session", repo_path:$repo, state_file:$state_file}'
    return 0
  fi
  walter_session_get "$repo"
}

session_restart() {
  local repo result status
  repo="$(session_repo "${1:-}")"
  set +e
  result="$(walter_session_end "$repo")"
  status=$?
  set -e
  printf '%s\n' "$result"
  return "$status"
}

sub="${1:-help}"
shift || true

case "$sub" in
  status)
    session_status "${1:-}"
    ;;
  restart)
    session_restart "${1:-}"
    ;;
  -h|--help|help)
    session_usage
    ;;
  *)
    echo "walter-os session: unknown subcommand: $sub" >&2
    session_usage >&2
    exit 2
    ;;
esac
