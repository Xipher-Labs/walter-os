#!/usr/bin/env bash
# scripts/setup-githooks.sh — idempotent git hook setup for Walter-OS.
#
# What this script does:
#   1. Configures core.hooksPath = .githooks for this repo (so git uses the
#      committed hook scripts in .githooks/ rather than .git/hooks/).
#   2. Ensures .githooks/pre-commit is executable.
#   3. Verifies gitleaks is installed (pre-commit hook depends on it).
#
# Why .githooks/ instead of .git/hooks/:
#   - .githooks/ is tracked by git — every contributor gets the hooks
#     automatically after running this installer once.
#   - .git/hooks/ is not tracked — hooks must be manually re-wired on
#     each fresh clone.
#
# Called by install.sh automatically. Can also be run standalone:
#   bash scripts/setup-githooks.sh
#   bash scripts/setup-githooks.sh --dry-run
#
# Related:
#   .githooks/pre-commit          — gitleaks hook (checked into repo)
#   scripts/install-pre-commit.sh — alternative installer for .git/hooks/
#   tests/hooks/gitleaks.bats     — gitleaks behavior tests
#   docs/specs/secrets-runtime-architecture.md  — §12 gitleaks integration

set -euo pipefail

# ---------- args ----------

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# ---------- pretty ----------

if [[ -t 1 ]]; then
  c_reset=$'\033[0m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_d=$'\033[2m'
else
  c_reset=""; c_g=""; c_y=""; c_r=""; c_d=""
fi

ok()   { printf "%s\n" "${c_g}ok${c_reset}  $*"; }
warn() { printf "%s\n" "${c_y}warn${c_reset} $*" >&2; }
err()  { printf "%s\n" "${c_r}err${c_reset}  $*" >&2; }
dry()  { printf "%s\n" "${c_d}[dry-run]${c_reset} $*"; }

# ---------- repo discovery ----------

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || true
}

# ---------- main ----------

main() {
  local root
  root="$(repo_root)"
  if [[ -z "${root:-}" ]]; then
    err "Not inside a git repository. Run from the walter-os repo root."
    exit 1
  fi

  local githooks_dir="$root/.githooks"
  local pre_commit_hook="$githooks_dir/pre-commit"

  # Step 1: verify .githooks/pre-commit exists in the repo
  if [[ ! -f "$pre_commit_hook" ]]; then
    err ".githooks/pre-commit not found at $pre_commit_hook"
    err "Expected the hook to be checked in to the repository."
    exit 1
  fi

  # Step 2: configure core.hooksPath (idempotent)
  local current_hooks_path
  current_hooks_path="$(git -C "$root" config --local core.hooksPath 2>/dev/null || echo '')"

  if [[ "$current_hooks_path" == ".githooks" ]]; then
    ok "core.hooksPath already set to .githooks"
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "git config core.hooksPath .githooks (currently: '${current_hooks_path:-<unset>}')"
    else
      git -C "$root" config core.hooksPath ".githooks"
      ok "Set core.hooksPath = .githooks"
    fi
  fi

  # Step 3: ensure the hook is executable
  if [[ -x "$pre_commit_hook" ]]; then
    ok ".githooks/pre-commit is executable"
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "chmod +x $pre_commit_hook"
    else
      chmod +x "$pre_commit_hook"
      ok "Made .githooks/pre-commit executable"
    fi
  fi

  # Step 4: verify gitleaks is available (warn, don't block)
  if command -v gitleaks >/dev/null 2>&1; then
    ok "gitleaks found: $(gitleaks version 2>/dev/null | head -1 || echo '<version unknown>')"
  else
    warn "gitleaks not found on PATH — pre-commit hook will print an error on commit."
    warn "  Install: brew install gitleaks  (macOS)"
    warn "           apt install gitleaks   (Debian/Ubuntu)"
    warn "  The pre-commit hook will BLOCK commits (exit 1) until gitleaks is installed."
    warn "  Bypass temporarily with: git commit --no-verify  (not recommended for shared branches)."
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    ok "dry-run complete (no changes made)"
  else
    ok "Git hooks configured. Pre-commit: gitleaks secret scan active."
  fi
}

main "$@"
