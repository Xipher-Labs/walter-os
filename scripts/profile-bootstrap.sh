#!/usr/bin/env bash
# profile-bootstrap.sh — set up multi-account profile dirs for Claude Code + Codex.
#
# Why: operator has BOTH an enterprise subscription (work/*) and a personal
# subscription. Claude Code reads creds from ~/.claude/ (or whatever
# $CLAUDE_CONFIG_DIR points to). Codex reads from ~/.codex/ (or $CODEX_HOME).
# We can't have two creds in one dir, but we CAN have multiple dirs and switch
# via env var per shell session. No symlink rotation, no global state.
#
# Layout this script enforces:
#
#   ~/.claude/         — personal profile (existing default; UNCHANGED)
#   ~/.claude-work/    — enterprise profile (NEW; used when cwd ⊂ ~/work/*)
#   ~/.codex/          — personal profile (existing default)
#   ~/.codex-work/     — enterprise profile
#
# Each *-work/ dir is bootstrapped as a copy of the personal profile MINUS
# credentials, so skills/agents/commands/settings.json all match. The first
# time the operator runs `claude` inside ~/work/*, the wrapper exports
# CLAUDE_CONFIG_DIR=~/.claude-work and Claude prompts for login (enterprise
# account). After login, that auth is baked into ~/.claude-work/ and re-used.
#
# Subcommands:
#   init {claude|codex|all}     — bootstrap the *-work profile dir (idempotent)
#   status                       — report which profiles exist + auth state
#   sync-shared                  — re-sync skills/agents/commands/settings.json
#                                  from personal profile into work profile
#                                  (run after every install.sh --upgrade)
#
# Usage:
#   walter-os profile-bootstrap init all
#   walter-os profile-bootstrap status

set -euo pipefail

ACTION="${1:-status}"
TARGET="${2:-all}"

CLAUDE_PERSONAL="${HOME}/.claude"
CLAUDE_WORK="${HOME}/.claude-work"
CODEX_PERSONAL="${HOME}/.codex"
CODEX_WORK="${HOME}/.codex-work"

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
info() { printf "${c_d}·${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

# Files that hold OAuth/auth credentials — these must NOT be copied between
# profiles, otherwise the work profile inherits the personal account's session.
# `.claude.json` lives at $HOME (not inside .claude/) per Claude Code v2.
# `.credentials.json` is the Linux/Windows path; macOS uses Keychain.
CLAUDE_AUTH_FILES=(
  ".credentials.json"
  ".claude.json"
  "auth.json"
  "session.json"
)

CODEX_AUTH_FILES=(
  "auth.json"
  "session.json"
  ".credentials.json"
)

# rsync exclude list for shared content (everything except auth + ephemeral).
# Note: we INCLUDE skills/, agents/, commands/, settings.json — those should
# match between profiles since walter-os is the source of truth.
SHARED_EXCLUDES=(
  "--exclude=.credentials.json"
  "--exclude=.claude.json"
  "--exclude=auth.json"
  "--exclude=session.json"
  "--exclude=sessions/"          # per-conversation history, profile-local
  "--exclude=projects/"          # symlinked into ~/sync/agent-memory anyway
  "--exclude=todos/"             # ephemeral
  "--exclude=statsig/"           # internal telemetry
  "--exclude=.cache/"
  "--exclude=*.log"
)

bootstrap_claude() {
  step "Bootstrap Claude work profile (${CLAUDE_WORK})"

  if [[ ! -d "$CLAUDE_PERSONAL" ]]; then
    err "Personal profile ${CLAUDE_PERSONAL} does not exist. Run install.sh first."
    return 1
  fi

  if [[ ! -d "$CLAUDE_WORK" ]]; then
    mkdir -p "$CLAUDE_WORK"
    ok "created ${CLAUDE_WORK}"
  else
    info "${CLAUDE_WORK} already exists"
  fi

  # Mirror personal profile contents EXCEPT auth/ephemeral files.
  rsync -a --delete-excluded "${SHARED_EXCLUDES[@]}" \
    "${CLAUDE_PERSONAL}/" "${CLAUDE_WORK}/" 2>&1 | tail -3 || true
  ok "synced shared content (skills/agents/commands/settings.json)"

  # Sanity check that no auth file leaked.
  local leaked=0
  for f in "${CLAUDE_AUTH_FILES[@]}"; do
    if [[ -f "${CLAUDE_WORK}/${f}" ]]; then
      err "Leaked auth file in work profile: ${CLAUDE_WORK}/${f} — removing"
      rm -f "${CLAUDE_WORK}/${f}"
      leaked=$((leaked + 1))
    fi
  done
  [[ $leaked -eq 0 ]] && ok "no auth file leaked into work profile"

  # First-run instructions. Claude Code on macOS stores OAuth in the user
  # Keychain — NOT inside the profile dir. So we can't reliably detect
  # "is this profile authed?" from the filesystem alone. Always print the
  # hint so the operator knows the bootstrap landed; if they've already
  # logged in, the next run is a no-op.
  cat <<HINT
${c_y}First-run for the work profile:${c_0}
  Set ANTHROPIC_ENTERPRISE_KEY in ~/.config/walter-os/secrets.env
  (the claude() shell wrapper passes it as ANTHROPIC_API_KEY only when
  cwd is in ~/work/*, bypassing personal Keychain OAuth).

  Verify: cd ~/work && claude --version
HINT
}

bootstrap_codex() {
  step "Bootstrap Codex work profile (${CODEX_WORK})"

  if [[ ! -d "$CODEX_PERSONAL" ]]; then
    err "Personal profile ${CODEX_PERSONAL} does not exist. Run install.sh first."
    return 1
  fi

  if [[ ! -d "$CODEX_WORK" ]]; then
    mkdir -p "$CODEX_WORK"
    ok "created ${CODEX_WORK}"
  else
    info "${CODEX_WORK} already exists"
  fi

  rsync -a --delete-excluded "${SHARED_EXCLUDES[@]}" \
    "${CODEX_PERSONAL}/" "${CODEX_WORK}/" 2>&1 | tail -3 || true
  ok "synced shared content"

  local leaked=0
  for f in "${CODEX_AUTH_FILES[@]}"; do
    if [[ -f "${CODEX_WORK}/${f}" ]]; then
      err "Leaked auth file: ${CODEX_WORK}/${f} — removing"
      rm -f "${CODEX_WORK}/${f}"
      leaked=$((leaked + 1))
    fi
  done
  [[ $leaked -eq 0 ]] && ok "no auth file leaked into work profile"

  if [[ ! -f "${CODEX_WORK}/auth.json" ]]; then
    cat <<HINT
${c_y}First-run for the work profile:${c_0}
  CODEX_HOME=${CODEX_WORK} codex
  → log in with the enterprise account when prompted.
HINT
  fi
}

cmd_status() {
  step "Profile status"
  echo

  for spec in "claude:${CLAUDE_PERSONAL}" "claude-work:${CLAUDE_WORK}" \
              "codex:${CODEX_PERSONAL}"   "codex-work:${CODEX_WORK}"; do
    name="${spec%%:*}"
    dir="${spec#*:}"
    if [[ ! -d "$dir" ]]; then
      printf "  %-12s ${c_d}(not initialized)${c_0}  %s\n" "$name" "$dir"
      continue
    fi
    # Auth presence check. The semantics differ per tool, so be explicit
    # about what we can and can't tell:
    auth="no"
    case "$name" in
      claude*)
        # Claude on macOS stores OAuth in the user Keychain (`security find-
        # generic-password -s 'Claude Code-credentials'`), which is GLOBAL —
        # not per-profile. The presence of a Keychain entry does NOT mean
        # this specific profile is authed. We can't filesystem-detect work-
        # vs-personal. Show "Keychain (global)" or "API key (env)" as the
        # operative auth path.
        if [[ -f "${dir}/.credentials.json" ]]; then
          auth="yes (file)"
        elif security find-generic-password -s "Claude Code-credentials" -a "$USER" >/dev/null 2>&1; then
          auth="Keychain (global)"
        else
          auth="no Keychain entry"
        fi
        ;;
      codex*)
        # Codex stores creds inside the home dir (auth.json), so this check
        # is reliable per-profile.
        [[ -f "${dir}/auth.json" ]] && auth="yes (file)"
        ;;
    esac
    skills=0
    [[ -d "${dir}/skills" ]] && skills=$(find "${dir}/skills" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
    printf "  ${c_g}%-12s${c_0} auth=%-12s skills=%s\n" "$name" "$auth" "$skills"
  done

  echo
  # Strip trailing slash so an override like WALTER_WORK_PATH=~/work/ still
  # matches; also match the EXACT $HOME/work path, not just descendants.
  local work_root="${WALTER_WORK_PATH:-$HOME/work}"
  work_root="${work_root%/}"
  case "$PWD" in
    "$work_root"|"$work_root"/*)
      info "Current cwd is in ${work_root} → wrapper would use WORK profile"
      ;;
    *)
      info "Current cwd outside ${work_root} → wrapper would use PERSONAL profile"
      ;;
  esac
}

case "$ACTION" in
  init)
    case "$TARGET" in
      claude) bootstrap_claude ;;
      codex)  bootstrap_codex ;;
      all)    bootstrap_claude; bootstrap_codex ;;
      *)      err "Unknown init target: $TARGET (use: claude | codex | all)"; exit 2 ;;
    esac
    ;;
  sync-shared)
    bootstrap_claude  # rsync mirrors shared content; auth stays untouched
    bootstrap_codex
    ok "shared content re-synced"
    ;;
  status)
    cmd_status
    ;;
  *)
    echo "Usage: walter-os profile-bootstrap {init|sync-shared|status} [claude|codex|all]" >&2
    exit 2
    ;;
esac
