#!/usr/bin/env bash
# sync.sh — pull latest Walter-OS, regenerate configs, reinstall.
#
# Safe: requires clean working tree, fast-forward only, never destroys
# uncommitted work.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_0=$'\033[0m'

ok()  { printf "${c_g}✓${c_0} %s\n" "$*"; }
warn(){ printf "${c_y}!${c_0} %s\n" "$*"; }
err() { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }

# 1. Working tree clean?
if [[ -n "$(git status --porcelain)" ]]; then
  err "Working tree dirty. Commit or stash first."
  git status --short
  exit 2
fi

# 2. On a sane branch (main or dev)?
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "$BRANCH" in
  main|dev) ;;
  *)
    warn "On branch '${BRANCH}'. Sync only pulls main/dev."
    exit 1
    ;;
esac

# 3. Fetch and check if behind
git fetch --quiet

LOCAL="$(git rev-parse @)"
REMOTE="$(git rev-parse @{u} 2>/dev/null || echo "$LOCAL")"
BASE="$(git merge-base @ @{u} 2>/dev/null || echo "$LOCAL")"

if [[ "$LOCAL" == "$REMOTE" ]]; then
  ok "Already up to date with origin/${BRANCH}"
elif [[ "$LOCAL" == "$BASE" ]]; then
  ok "Behind origin/${BRANCH} — fast-forwarding..."
  git pull --ff-only --quiet
  ok "Pulled $(git log --oneline "${LOCAL}..@" | wc -l | tr -d ' ') commit(s)"
elif [[ "$REMOTE" == "$BASE" ]]; then
  warn "Local is ahead of origin/${BRANCH}. Push when ready."
else
  err "Diverged from origin/${BRANCH}. Resolve manually."
  exit 3
fi

# 4. Reinstall in upgrade mode
ok "Running install.sh --upgrade..."
"${REPO_ROOT}/install.sh" --upgrade

ok "Sync complete."
