#!/usr/bin/env bash
# sync-repos.sh — pull configured repos with safety guards.
#
# Reads ~/.config/walter-os/repos.txt (one path per line).
# Format per line:  <path>[:<branch>]   (default branch: main)
# Lines starting with # are comments. Tilde expansion supported.
#
# Safety:
# - SKIPS repos with dirty working tree.
# - SKIPS repos on a different branch than the configured/default one.
# - Uses --ff-only: never merges, never rebases, never destroys work.
# - Never auto-resolves conflicts.
# - Logs result per repo, exit 0 even on individual skips/failures.

set -uo pipefail

WALTER_CONFIG="${HOME}/.config/walter-os"
REPOS_FILE="${WALTER_OS_REPOS_FILE:-${WALTER_CONFIG}/repos.txt}"

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_d=$'\033[2m'; c_0=$'\033[0m'

if [[ ! -f "$REPOS_FILE" ]]; then
  cat <<EOF
sync-repos: no repos file at $REPOS_FILE.

Create one with paths to your repos, one per line:

  ~/work/[company]-rpc:dev
  ~/Projects-Personal/[Project A]
  ~/Projects-Personal/[Project B]:dev
  # comments work too

Then re-run: walter-os sync-repos
EOF
  exit 0
fi

# Counters
n_ok=0 n_pull=0 n_skip=0 n_fail=0

print_line() {
  local status="$1" repo="$2" detail="$3"
  case "$status" in
    OK)   printf "${c_g}[OK]  ${c_0} %-50s %s\n"   "$repo" "$detail" ;;
    PULL) printf "${c_g}[PULL]${c_0} %-50s %s\n"   "$repo" "$detail" ;;
    SKIP) printf "${c_y}[SKIP]${c_0} %-50s %s\n"   "$repo" "$detail" ;;
    FAIL) printf "${c_r}[FAIL]${c_0} %-50s %s\n"   "$repo" "$detail" ;;
  esac
}

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  # Trim
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  # Parse <path>[:<branch>]
  if [[ "$line" == *:* ]]; then
    repo_path="${line%:*}"
    branch="${line##*:}"
  else
    repo_path="$line"
    branch="main"
  fi

  # Tilde expand
  repo_path="${repo_path/#~/$HOME}"

  if [[ ! -d "$repo_path/.git" ]]; then
    print_line SKIP "$repo_path" "not a git repo"
    ((n_skip++))
    continue
  fi

  pushd "$repo_path" >/dev/null || continue

  # Working tree clean?
  if [[ -n "$(git status --porcelain)" ]]; then
    print_line SKIP "$repo_path" "working tree dirty"
    ((n_skip++))
    popd >/dev/null || true
    continue
  fi

  # On the right branch?
  current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ "$current" != "$branch" ]]; then
    print_line SKIP "$repo_path" "on '$current', expected '$branch'"
    ((n_skip++))
    popd >/dev/null || true
    continue
  fi

  # Has remote tracking?
  if ! git rev-parse "@{u}" >/dev/null 2>&1; then
    print_line SKIP "$repo_path" "branch '$branch' has no upstream"
    ((n_skip++))
    popd >/dev/null || true
    continue
  fi

  # Pull (ff-only)
  pull_log="$(mktemp)"
  if git pull --ff-only --quiet origin "$branch" 2>"$pull_log"; then
    # Determine if anything changed
    LOCAL="$(git rev-parse @)"
    REMOTE_PREV="$(git rev-parse "@{1}" 2>/dev/null || echo "$LOCAL")"
    if [[ "$LOCAL" == "$REMOTE_PREV" ]]; then
      print_line OK "$repo_path" "up to date (${branch})"
      ((n_ok++))
    else
      n_commits="$(git log --oneline "${REMOTE_PREV}..${LOCAL}" | wc -l | tr -d ' ')"
      print_line PULL "$repo_path" "+${n_commits} commit(s) (${branch})"
      ((n_pull++))
    fi
  else
    print_line FAIL "$repo_path" "$(head -1 "$pull_log")"
    ((n_fail++))
  fi
  rm -f "$pull_log"

  popd >/dev/null || true
done < "$REPOS_FILE"

echo
echo "${c_d}Summary:${c_0} ok=${n_ok} pulled=${n_pull} skipped=${n_skip} failed=${n_fail}"
