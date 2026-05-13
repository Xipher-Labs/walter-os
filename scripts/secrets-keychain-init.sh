#!/usr/bin/env bash
# secrets-keychain-init.sh — one-time bootstrap of macOS Keychain entry
# for Infisical Machine Identity. Yubikey HARD-required.
#
# After this runs once per device, `walter_secrets_load` (zsh function)
# can fetch operator secrets at runtime without ever touching disk.
#
# Prereqs (operator does these manually first):
#   1. ykman info → confirms Yubikey detected
#   2. Open Infisical web UI → walter-os project → Settings → Machine
#      Identities → Create. Method: universal-auth. Permissions:
#      read-only on environments needed (typically `dev`).
#      Copy client_id + client_secret.
#
# Usage:
#   walter-os secrets-keychain-init
#     → prompts for client_id (paste)
#     → prompts for client_secret (paste, hidden)
#     → writes single Keychain entry "walter-os.infisical-identity"
#     → ACL: only allow read by `infisical`/`security` after Touch ID
#       (Yubikey-PIV registered as Touch ID equivalent on macOS, see
#        skills/secrets-yubikey-unlock for setup steps)
#
# Idempotent: replaces existing entry if already present (with confirm).

set -euo pipefail

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
info() { printf "${c_d}·${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

KEYCHAIN_SERVICE="walter-os.infisical-identity"
KEYCHAIN_ACCOUNT="$USER"

step "Preflight"
[[ "$(uname)" == "Darwin" ]] || { err "macOS only — Keychain doesn't exist on Linux"; exit 1; }

if ! command -v ykman >/dev/null 2>&1; then
  err "ykman not installed. Install: brew install ykman"
  exit 2
fi

# Yubikey hard-required per operator decision (2026-05-05).
# No Touch ID fallback at this layer — the Keychain ACL itself enforces it.
if ! ykman info 2>/dev/null | grep -q 'Serial number'; then
  err "Yubikey not detected. Walter-OS policy: Yubikey hard-required."
  err "  Plug the Yubikey in and re-run."
  exit 3
fi
ok "Yubikey detected: $(ykman info | grep 'Serial number')"

if ! command -v infisical >/dev/null 2>&1; then
  err "Infisical CLI not installed. Install: brew install infisical/get-cli/infisical"
  exit 4
fi
ok "Infisical CLI: $(infisical --version 2>&1 | head -1)"

step "Existing Keychain entry?"
if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
  warn "An entry already exists at service=$KEYCHAIN_SERVICE account=$KEYCHAIN_ACCOUNT."
  printf "Replace it? [y/N] "
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { info "Aborted."; exit 0; }
  security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" 2>/dev/null
  ok "Deleted prior entry."
else
  info "No prior entry."
fi

step "Collect Machine Identity creds"
echo "From Infisical → walter-os → Settings → Machine Identities → <your identity>:"
printf "  client_id: "
read -r CLIENT_ID
printf "  client_secret (hidden): "
read -rs CLIENT_SECRET
echo

[[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]] && { err "Both required"; exit 5; }

# Quick verify creds work BEFORE storing them.
step "Verify creds against Infisical"
if ! infisical login --method=universal-auth \
  --client-id="$CLIENT_ID" --client-secret="$CLIENT_SECRET" \
  --domain="https://secrets.${WALTER_DOMAIN}" --plain >/dev/null 2>&1; then
  err "Login failed. Check that the Machine Identity exists and the secret is correct."
  exit 6
fi
ok "Creds verified."

step "Write to Keychain (Yubikey/Touch ID gates future reads)"
JWT_BLOB=$(jq -n --arg id "$CLIENT_ID" --arg sec "$CLIENT_SECRET" \
  '{client_id: $id, client_secret: $sec}')

# -T "" → no application is in the access list except `security` itself.
#         macOS will prompt for auth on every read attempt.
# -U     → upsert (create if missing).
security add-generic-password \
  -s "$KEYCHAIN_SERVICE" \
  -a "$KEYCHAIN_ACCOUNT" \
  -w "$JWT_BLOB" \
  -T "" \
  -U \
  -j "Walter-OS Infisical Machine Identity (Yubikey-gated, 12h session)"

ok "Stored in Keychain."

cat <<NEXT

${c_b}Done.${c_0} Verify with:

  ${c_d}# Should trigger Touch ID / Yubikey prompt:${c_0}
  walter_secrets_load
  echo \$ANTHROPIC_API_KEY | head -c 20

If \$ANTHROPIC_API_KEY shows the first 20 chars, you're set.

The shell wrapper handles 12h session + auto-reauth. Just open new shells
normally; secrets are loaded transparently.

To reset:
  walter-os secrets-keychain-init   # re-runs this script

To revoke (if device lost):
  Open Infisical UI → walter-os → Settings → Machine Identities →
  delete the affected identity. The Keychain blob becomes useless.
NEXT
