#!/usr/bin/env bash
# secrets-bootstrap.sh — initialize the Bitwarden 'walter-os/secrets' note.
#
# What it does:
#   1. Ensures `bw` is installed and unlocked.
#   2. If a 'walter-os/secrets' secure note already exists → bail out (refuse
#      to clobber).
#   3. Otherwise, creates the note with a TEMPLATE in dotenv format that the
#      operator then edits via web UI / desktop app to fill in real values.
#   4. Prints the bw item ID so the operator can find it later.
#
# After running this, populate values via Bitwarden web/desktop, then:
#   walter-os secrets-pull       → pulls into ~/.config/walter-os/secrets.env
#
# Usage:
#   walter-os secrets-bootstrap          (creates the template note)
#   walter-os secrets-bootstrap --force  (overwrite if note already exists)

set -euo pipefail

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
info() { printf "${c_d}·${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

step "Checking prerequisites"
if ! command -v bw >/dev/null 2>&1; then
  err "Bitwarden CLI 'bw' not found. Install: brew install bitwarden-cli"
  err "  Then: bw login && bw unlock"
  exit 3
fi
if ! command -v jq >/dev/null 2>&1; then
  err "'jq' is required to parse Bitwarden output. Install: brew install jq"
  exit 3
fi
status="$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unauthenticated)"
case "$status" in
  unlocked)        ok "vault unlocked" ;;
  locked)          err "vault is locked. Run: export BW_SESSION=\$(bw unlock --raw)"; exit 3 ;;
  unauthenticated) err "not logged in. Run: bw login"; exit 3 ;;
  *)               err "unknown bw status: $status"; exit 3 ;;
esac

step "Check for existing 'walter-os/secrets' item"
existing_id="$(bw list items --search 'walter-os/secrets' 2>/dev/null \
  | jq -r '.[] | select(.name == "walter-os/secrets") | .id' \
  | head -1)"

if [[ -n "$existing_id" && "$FORCE" -eq 0 ]]; then
  warn "Item 'walter-os/secrets' already exists (id=${existing_id})"
  warn "  Use --force to overwrite, OR edit it via web/desktop and then run:"
  warn "  walter-os secrets-pull"
  exit 0
fi

step "Build secret-note template"
TEMPLATE="$(cat <<'EOF'
# walter-os/secrets — sourced by ~/.config/walter-os/secrets.env via:
#   walter-os secrets-pull
#
# Edit this note via Bitwarden web/desktop UI (the CLI doesn't paste well).
# Empty string = "MCP that needs it will fail to start; that's the signal".
# Once filled, run `walter-os secrets-pull` on EVERY device to deploy.

# ============================================================
# AI providers
# ============================================================
# Personal subscription (Claude Pro) is read from macOS Keychain by Claude
# Code automatically — leave ANTHROPIC_API_KEY empty unless you specifically
# want API mode for the personal context too.
export ANTHROPIC_API_KEY=""
# Enterprise key ([Company]). Used by the claude() shell wrapper when cwd
# is under ~/work/* — overrides Keychain OAuth so requests go to the
# enterprise account / billing.
export ANTHROPIC_ENTERPRISE_KEY=""
export ANTHROPIC_ADMIN_API_KEY=""
export OPENAI_API_KEY=""
export GEMINI_API_KEY=""
export ELEVENLABS_API_KEY=""

# ============================================================
# Source control
# ============================================================
# GitHub PAT (scopes: repo, workflow, read:org, gist)
export GITHUB_TOKEN=""
# Forgejo (Walter-VM)
export FORGEJO_URL="https://git.${WALTER_DOMAIN}"
export FORGEJO_TOKEN=""

# ============================================================
# Project management (Walter-VM)
# ============================================================
export PLANE_API_URL="https://plane.${WALTER_DOMAIN}/api/v1"
export PLANE_API_TOKEN=""
export INFISICAL_API_URL="https://secrets.${WALTER_DOMAIN}/api"
export INFISICAL_DOMAIN="https://secrets.${WALTER_DOMAIN}"
export INFISICAL_CLIENT_ID=""
export INFISICAL_CLIENT_SECRET=""

# ============================================================
# LLM gateway (Walter-VM)
# ============================================================
export LITELLM_URL="https://llm.${WALTER_DOMAIN}"
export LITELLM_MASTER_KEY=""

# ============================================================
# Cloud / infra (high-risk — money-spending + lateral-movement)
# ============================================================
# Hetzner Cloud (NEVER write-scoped by default; mint a write token only when
# actively provisioning, then revoke). Read-only token here is fine.
export HCLOUD_TOKEN=""
# Cloudflare (DNS, Tunnel, Access). Scopes:
#   Zone.DNS:Edit, Account.Cloudflare Tunnel:Edit, Account.Access:Edit
export CLOUDFLARE_API_TOKEN=""
export CF_ACCOUNT=""
export CF_EMAIL=""
export CF_KEY=""
# Vercel (frontend deploys). Scopes: Full Account
export VERCEL_TOKEN=""
# Backblaze B2 (restic offsite). Read-write for the bucket.
export B2_ACCOUNT_ID=""
export B2_APPLICATION_KEY=""
# Railway (managed Postgres / stateful infra)
export RAILWAY_TOKEN=""

# ============================================================
# Email / messaging
# ============================================================
# Resend (transactional email — ${WALTER_DOMAIN} and any project domains)
export RESEND_API_KEY=""
# Telegram bot (Walter notifier)
export TELEGRAM_BOT_TOKEN=""
export TELEGRAM_CHAT_ID=""
# Slack (DevRel + [Company]; if applicable)
export SLACK_BOT_TOKEN=""
export SLACK_USER_TOKEN=""

# ============================================================
# Solana / web3
# ============================================================
# Helius / QuickNode RPC fallbacks for testing
export HELIUS_API_KEY=""
export QUICKNODE_URL=""

# ============================================================
# Device-specific paths (override defaults from
# templates/zsh.d/15-walter-os.zsh if your layout differs)
# ============================================================
# export WALTER_HACKATON_PATH="$HOME/Projects-Personal/Hackatons"
# export WALTER_WORK_PATH="$HOME/work"
# export WALTER_PROJECTS_PATH="$HOME/Projects-Personal"
# export WALTER_PERSONAL_PATH="$HOME/personal"
EOF
)"

step "Create / update Bitwarden secure note"
# bw expects the item JSON via stdin (`bw encode` first, then create).
NOTE_BODY="$(jq -n --arg notes "$TEMPLATE" '{
  organizationId: null,
  collectionIds: [],
  folderId: null,
  type: 2,
  name: "walter-os/secrets",
  notes: $notes,
  favorite: false,
  fields: [],
  reprompt: 0,
  secureNote: { type: 0 }
}')"

if [[ -n "$existing_id" && "$FORCE" -eq 1 ]]; then
  echo "$NOTE_BODY" | bw encode | bw edit item "$existing_id" >/dev/null
  ok "overwrote existing item (id=${existing_id})"
else
  new_id="$(echo "$NOTE_BODY" | bw encode | bw create item | jq -r '.id')"
  ok "created new item: ${new_id}"
fi

step "Sync vault"
bw sync >/dev/null 2>&1 && ok "synced"

cat <<NEXT

Next steps:
  1. Open Bitwarden web/desktop → find note 'walter-os/secrets'.
  2. Edit notes field, fill in real values for every secret you actually use.
  3. Save.
  4. On EACH device: walter-os secrets-pull
     (this writes ~/.config/walter-os/secrets.env, mode 600)
  5. Source it from your shell:
     [[ -f \$HOME/.config/walter-os/secrets.env ]] && source \$HOME/.config/walter-os/secrets.env
     (already wired in templates/zsh.d/80-secrets.zsh once you re-run install.sh)
NEXT
