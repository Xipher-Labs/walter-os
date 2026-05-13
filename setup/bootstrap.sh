#!/usr/bin/env bash
# bootstrap.sh — install Walter-OS dev tooling on a fresh Mac.
#
# Idempotent. Safe to re-run. Won't downgrade existing tools.
#
# What this does (in order):
#   1. Verify macOS + arch (Apple Silicon expected)
#   2. Install Homebrew if missing
#   3. brew bundle setup/Brewfile (CLI tools + casks + fonts)
#   4. Install mise runtime versions (node, python, rust, ...)
#   5. Install global CLI tools (pnpm, bun, uv via mise; pre-commit, etc.)
#   6. Install Solana toolchain (via official installer, not brew)
#   7. Install Anchor (via avm)
#   8. Print next-steps for ./install.sh
#
# What this does NOT do:
#   - Run install.sh (separate step, intentionally)
#   - Touch ~/.zshrc beyond what brew/mise do (you control your shell)
#   - Install secrets / credentials (manual via secrets.env after install)
#   - Provision Walter-VM (separate, requires HCLOUD_TOKEN)
#
# Usage:
#   ./setup/bootstrap.sh             # full bootstrap
#   ./setup/bootstrap.sh --minimal   # just CLIs + mise (no GUI apps)
#   ./setup/bootstrap.sh --dry-run   # print what would happen
#   ./setup/bootstrap.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BREWFILE="$SCRIPT_DIR/Brewfile"

DRY=0
MINIMAL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY=1 ;;
    --minimal)  MINIMAL=1 ;;
    -h|--help)
      grep '^#' "$0" | head -28 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }
dry()  { printf "${c_d}[dry]${c_0} %s\n" "$*"; }

run() {
  if [[ $DRY -eq 1 ]]; then
    dry "$*"
  else
    "$@"
  fi
}

TMP_FILES=()
cleanup_tmp_files() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
}
make_tmp_file() {
  local tmp
  tmp="$(mktemp "$@")"
  TMP_FILES+=("$tmp")
  printf '%s\n' "$tmp"
}
trap cleanup_tmp_files EXIT

# ---------- 1. Preflight ----------

step "Preflight"

if [[ "$(uname)" != "Darwin" ]]; then
  err "macOS only. For Linux: use the Brewfile as a list and install via apt/dnf manually."
  exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  warn "Detected $ARCH — Walter-OS is tested on Apple Silicon. Intel may work but isn't validated."
fi

ok "macOS / $ARCH"

# ---------- 2. Homebrew ----------

step "Homebrew"

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not installed. Installing..."
  if [[ $DRY -eq 1 ]]; then
    dry "would download the Homebrew installer to a temp file and run it with /bin/bash"
  else
    brew_installer="$(make_tmp_file -t homebrew-install.XXXXXX)"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      -o "$brew_installer"
    /bin/bash "$brew_installer"
    # On Apple Silicon, brew lives at /opt/homebrew. Add to PATH if not there.
    if [[ -d /opt/homebrew/bin && ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi
  ok "Homebrew installed"
else
  ok "Homebrew: $(brew --version | head -1)"
fi

# ---------- 3. brew bundle ----------

step "Install packages from Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
  err "Brewfile missing at $BREWFILE"
  exit 2
fi

# `brew bundle` returns non-zero if ANY entry fails. We tolerate cask failures
# (typically sudo / TTY issues — user finishes those manually) and continue
# with mise + Solana setup which doesn't need sudo.

if [[ $MINIMAL -eq 1 ]]; then
  warn "Minimal mode: installing CLIs only, skipping casks/fonts."
  TMPFILE="$(make_tmp_file)"
  grep -E '^(brew |tap )' "$BREWFILE" > "$TMPFILE"
  if [[ $DRY -eq 1 ]]; then
    dry "brew bundle --file='$TMPFILE'"
  else
    brew bundle --file="$TMPFILE" || warn "Some brew entries failed (continuing — see output above)"
  fi
  rm -f "$TMPFILE"
else
  if [[ $DRY -eq 1 ]]; then
    dry "brew bundle --file='$BREWFILE'"
  else
    brew bundle --file="$BREWFILE" || warn "Some brew entries failed (continuing — typically sudo casks need a real TTY; finish them manually)"
  fi
fi

if [[ $DRY -eq 1 ]]; then
  warn "Brew bundle skipped in dry-run mode."
else
  ok "Brew bundle phase done (failures tolerated)"
fi

# ---------- 4. mise runtime versions ----------

step "Runtime versions via mise"

if command -v mise >/dev/null 2>&1; then
  if [[ ! -f "$HOME/.config/mise/config.toml" ]]; then
    run mkdir -p "$HOME/.config/mise"
    run cp "$SCRIPT_DIR/mise.toml.example" "$HOME/.config/mise/config.toml"
    ok "Wrote $HOME/.config/mise/config.toml from example"
  else
    ok "$HOME/.config/mise/config.toml already exists (not overwriting)"
  fi
  run mise install

  warn "Add this to ~/.zshrc to activate mise in shell:"
  warn "  eval \"\$(mise activate zsh)\""
else
  err "mise not found after Brewfile run — investigate"
fi

# ---------- 5. Global JS / Python tools ----------

step "Global JS + Python tools"

# pnpm and bun come via mise. Make sure they're available.
if command -v pnpm >/dev/null 2>&1; then
  ok "pnpm: $(pnpm --version)"
else
  warn "pnpm not on PATH — run 'mise install' in a fresh shell after activating mise"
fi

# uvx (Python) for ElevenLabs MCP and others
if command -v uvx >/dev/null 2>&1; then
  ok "uvx: available"
else
  warn "uvx not on PATH yet — comes from 'uv', should be installed via mise"
fi

# ---------- 6. Solana toolchain ----------

step "Solana toolchain"

if [[ $MINIMAL -eq 1 ]]; then
  warn "Minimal mode: skipping Solana toolchain"
else
  if ! command -v solana >/dev/null 2>&1; then
    warn "Installing Solana CLI (latest stable)..."
    if [[ $DRY -eq 1 ]]; then
      dry "would download the Solana installer to a temp file and run it with sh"
    else
      solana_installer="$(make_tmp_file -t solana-install.XXXXXX)"
      curl -sSfL https://release.anza.xyz/stable/install -o "$solana_installer"
      sh "$solana_installer"
      warn "Add to PATH: export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\""
    fi
  else
    ok "solana: $(solana --version)"
  fi

  if ! command -v anchor >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
    warn "Installing Anchor via cargo install..."
    run cargo install --git https://github.com/coral-xyz/anchor avm --force
    run avm install "${ANCHOR_VERSION:-0.31.1}"
    run avm use "${ANCHOR_VERSION:-0.31.1}"
  fi
fi

# ---------- 7. Maestro (mobile testing) ----------

step "Maestro CLI (mobile testing)"

if command -v maestro >/dev/null 2>&1; then
  ok "maestro: $(maestro --version 2>/dev/null | head -1)"
else
  warn "Maestro not yet installed (Brewfile should have installed it; check 'brew bundle' output)"
fi

# ---------- 8. Final summary ----------

step "Summary"

# Re-check casks that need sudo and weren't installed (so we can hint user)
sudo_casks_pending=()
if [[ ! -d "/Applications/Tailscale.app" ]]; then sudo_casks_pending+=("tailscale-app"); fi
if [[ ! -d "/Applications/1Password.app" ]]; then sudo_casks_pending+=("1password"); fi
if [[ ! -d "/Applications/Bitwarden.app" ]]; then sudo_casks_pending+=("bitwarden"); fi

if [[ ${#sudo_casks_pending[@]} -gt 0 ]]; then
  warn "Some casks need a real terminal (sudo prompts): ${sudo_casks_pending[*]}"
  warn "Run from your interactive terminal:"
  warn "  brew install --cask ${sudo_casks_pending[*]}"
fi

cat <<EOF

Bootstrap ${DRY:+(dry-run) }complete.

Next steps:

  1. Restart shell so mise + brew PATH are picked up.
  2. Run Walter-OS install (config layer):
       cd $REPO_ROOT && ./install.sh --dry-run   # preview
       cd $REPO_ROOT && ./install.sh             # apply
  3. Edit secrets:
       \$EDITOR ~/.config/walter-os/secrets.env
  4. Add to ~/.zshrc:
       eval "\$(mise activate zsh)"
       eval "\$(starship init zsh)"
       [[ -f \$HOME/.config/walter-os/env ]] && source \$HOME/.config/walter-os/env
  5. Install Claude Code superpowers plugin (in Claude Code):
       /plugin marketplace add obra/superpowers-marketplace
       /plugin install superpowers@superpowers-marketplace
  6. Verify:
       walter-os doctor

What's NOT done by this script (intentional):
  - Provision Walter-VM (Hetzner CPX41 — separate, needs HCLOUD_TOKEN)
  - Configure Tailscale (run \`sudo tailscale up\` after install)
  - Configure Vaultwarden client (\`bw login\` against your VM URL)
  - Apply for OAuth credentials (Google, Notion, Plane API tokens, etc.)
  - Set up the Obsidian Local REST API plugin (Obsidian → Settings)

EOF
