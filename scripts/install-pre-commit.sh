#!/usr/bin/env bash
# install-pre-commit.sh — install the gitleaks pre-commit hook for this repo.
#
# Why a local hook (and not just CI):
#   CI catches secrets AFTER they reach GitHub. The pre-commit hook catches
#   them BEFORE — zero round-trip, no leaked-then-rewritten history to clean
#   up. CI remains the safety net; this is the primary defense on the
#   operator's machine.
#
# What this script does:
#   1. Verifies `gitleaks` is on PATH. If missing, prints platform hints and
#      exits non-zero — never auto-installs a security tool.
#   2. Writes / upgrades `.git/hooks/pre-commit` to invoke
#      `gitleaks protect --staged --config .gitleaks.toml --redact`.
#      The invocation is prefixed with a marker comment so re-running the
#      installer is idempotent.
#   3. Preserves any existing pre-commit content by prepending the gitleaks
#      block above whatever was already there.
#   4. `chmod +x` the hook.
#
# Usage:
#   scripts/install-pre-commit.sh             # install
#   scripts/install-pre-commit.sh --dry-run   # print actions, change nothing

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
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ---------- pretty ----------

if [[ -t 1 ]]; then
  c_reset=$'\033[0m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_d=$'\033[2m'
else
  c_reset=""; c_g=""; c_y=""; c_r=""; c_d=""
fi

ok()   { printf "%s\n" "${c_g}✓${c_reset} $*"; }
warn() { printf "%s\n" "${c_y}!${c_reset} $*" >&2; }
err()  { printf "%s\n" "${c_r}✗${c_reset} $*" >&2; }
dry()  { printf "%s\n" "${c_d}[dry-run]${c_reset} $*"; }

# ---------- preflight ----------

require_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    return 0
  fi

  err "gitleaks not found on PATH."
  cat >&2 <<'EOF'

The walter-os pre-commit hook depends on gitleaks. Install it explicitly:

  macOS:   brew install gitleaks
  Debian:  apt install gitleaks            # may need a recent ppa/release
  Fallback (any OS with Go ≥ 1.22):
           go install github.com/gitleaks/gitleaks/v8@latest

Security tools are never auto-installed. Run one of the commands above,
re-run this script, and the hook will be wired up.
EOF
  return 1
}

# ---------- repo discovery ----------

# Resolve the repo root from cwd, not from $0 — the script may be invoked from
# anywhere via install.sh or directly.
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# ---------- hook content ----------

MARKER="# walter-os: gitleaks pre-commit"
HOOK_BLOCK_BEGIN="# >>> walter-os pre-commit (gitleaks) >>>"
HOOK_BLOCK_END="# <<< walter-os pre-commit (gitleaks) <<<"

# The block written into .git/hooks/pre-commit. Kept self-contained so the
# operator can read and reason about it without consulting this installer.
hook_block() {
  cat <<EOF
$HOOK_BLOCK_BEGIN
$MARKER
# Scans staged changes for secrets before the commit lands. CI re-scans on
# push as a safety net. Bypass for an emergency commit with --no-verify
# (and explain why in the commit body).
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --config .gitleaks.toml --redact || exit 1
else
  echo "gitleaks not installed; skipping secret scan. Install: brew install gitleaks" >&2
fi
$HOOK_BLOCK_END
EOF
}

# ---------- main ----------

main() {
  require_gitleaks

  local root
  root="$(repo_root)" || true
  if [[ -z "${root:-}" ]]; then
    err "Not inside a git repository (no .git found)."
    return 1
  fi

  local hooks_dir="$root/.git/hooks"
  local hook_file="$hooks_dir/pre-commit"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "ensure $hooks_dir exists"
    dry "write gitleaks block to $hook_file (idempotent)"
    dry "chmod +x $hook_file"
    ok "dry-run complete (no changes)"
    return 0
  fi

  mkdir -p "$hooks_dir"

  if [[ -f "$hook_file" ]] && grep -q "$MARKER" "$hook_file"; then
    # Already installed. Replace the block in place so re-running picks up
    # any updates to the block content (idempotent upgrade).
    local tmp
    tmp="$(mktemp)"
    awk -v begin="$HOOK_BLOCK_BEGIN" -v end="$HOOK_BLOCK_END" '
      $0 == begin { skipping = 1; next }
      $0 == end   { skipping = 0; next }
      skipping    { next }
      { print }
    ' "$hook_file" >"$tmp"
    {
      # If the file had a shebang, keep it at the top and put the gitleaks
      # block right after it; otherwise emit a shebang.
      if head -n 1 "$tmp" | grep -q '^#!'; then
        head -n 1 "$tmp"
        hook_block
        tail -n +2 "$tmp"
      else
        echo "#!/usr/bin/env bash"
        hook_block
        cat "$tmp"
      fi
    } >"$hook_file.new"
    mv "$hook_file.new" "$hook_file"
    rm -f "$tmp"
  elif [[ -f "$hook_file" ]]; then
    # Existing hook with unrelated content — prepend the gitleaks block,
    # preserving everything else.
    local tmp
    tmp="$(mktemp)"
    if head -n 1 "$hook_file" | grep -q '^#!'; then
      head -n 1 "$hook_file" >"$tmp"
      hook_block >>"$tmp"
      tail -n +2 "$hook_file" >>"$tmp"
    else
      echo "#!/usr/bin/env bash" >"$tmp"
      hook_block >>"$tmp"
      cat "$hook_file" >>"$tmp"
    fi
    mv "$tmp" "$hook_file"
  else
    # Fresh hook.
    {
      echo "#!/usr/bin/env bash"
      hook_block
    } >"$hook_file"
  fi

  chmod +x "$hook_file"
  ok "pre-commit hook installed at $hook_file (gitleaks protect --staged)"
}

main "$@"
