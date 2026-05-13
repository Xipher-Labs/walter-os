---
name: secrets-yubikey-unlock
description: How Walter-OS shells fetch secrets without typing them. Infisical session token cached in macOS Keychain, unlocked by either Touch ID OR Yubikey presence (FIDO2 / OpenPGP smartcard). 30-day session refresh. Use this skill whenever the user asks "how do I auth Infisical from CLI?", "configure Yubikey unlock", "set up keychain for secrets", or wants to remove plain-text tokens from `.zshrc`.
---

# Secrets unlock with Yubikey + macOS Keychain

## Goal

- No plaintext secrets in `~/.zshrc`, `~/.zprofile`, or any dotfile.
- One unlock per 30 days (or per Yubikey insertion / Touch ID prompt).
- Tokens never leave Keychain except as ephemeral session env vars.
- Yubikey absence → fallback to password (operator's choice).

## Architecture

```
            ┌────────────────────────────────────────────┐
            │  Yubikey 5C (FIDO2 + OpenPGP smartcard)    │
            │   plugged in OR cached for N seconds        │
            └─────────────────────┬──────────────────────┘
                                  │ unlock signal
                                  ▼
            ┌────────────────────────────────────────────┐
            │  macOS Keychain (login.keychain-db)        │
            │   service: walter-os.infisical              │
            │   account: <user>                          │
            │   value:   <infisical_machine_identity_jwt>│
            │   ACL: requires Touch ID OR Yubikey-PIV    │
            └─────────────────────┬──────────────────────┘
                                  │ fetched once per shell session
                                  ▼
            ┌────────────────────────────────────────────┐
            │  Infisical CLI (`infisical login --token`)  │
            │   exchanges JWT for short-lived session    │
            │   (default 15 min, refreshed automatically) │
            └─────────────────────┬──────────────────────┘
                                  │ env vars injected
                                  ▼
            ┌────────────────────────────────────────────┐
            │  `infisical run -- <command>`              │
            │   (or eval `infisical export ...`)         │
            └────────────────────────────────────────────┘
```

## Setup steps

### 1. Yubikey: enroll for macOS auth

```bash
# Install Yubico tools (already in setup/Brewfile after refactor)
brew install ykman yubico-piv-tool

# Verify Yubikey detected
ykman info

# Enroll Yubikey as a security key for macOS login (Touch ID + Yubikey)
# System Settings → Touch ID & Password → Add Touch ID OR add Yubikey via PAM
```

For PAM-based unlock (Yubikey required to unlock screensaver):

```bash
# This is OPTIONAL — only if you want OS-level Yubikey enforcement.
# It's separate from Keychain-level Yubikey use.
brew install pam-u2f
mkdir -p ~/.config/Yubico
ykman fido credentials set-pin   # set Yubikey FIDO2 PIN
pamu2fcfg -uYour-Username > ~/.config/Yubico/u2f_keys
# Edit /etc/pam.d/screensaver — add: auth required pam_u2f.so
```

### 2. Infisical: create a Machine Identity

A user token expires; a Machine Identity gives you a long-lived
client-id/client-secret pair tied to specific permissions.

```bash
# In the Infisical web UI (secrets.${WALTER_DOMAIN}):
#   Settings → Machine Identities → Create
#   Name: walter-os-mac-<machine-name>
#   Auth method: Universal Auth (client ID + client secret)
#   Permissions: scope to specific workspaces
#
# It returns: client_id (uuid) + client_secret (token)
```

### 3. Store the Machine Identity in Keychain

```bash
# Use `security add-generic-password` with --access-control flag
# requiring user presence (Touch ID OR Yubikey).

CLIENT_ID="<paste-from-infisical>"
CLIENT_SECRET="<paste-from-infisical>"

# Store both as one JSON blob for atomicity
JSON=$(jq -nc \
  --arg id "$CLIENT_ID" \
  --arg secret "$CLIENT_SECRET" \
  '{client_id: $id, client_secret: $secret}')

security add-generic-password \
  -s "walter-os.infisical" \
  -a "$USER" \
  -w "$JSON" \
  -T "" \
  --access-control "AccessibleWhenUnlocked,UserPresence"

# -T ""             → no trusted apps without prompt (asks every time)
# UserPresence      → Touch ID OR Yubikey OR password (any local-presence factor)
# AccessibleWhenUnlocked → only when keychain is unlocked
```

### 4. Helper script: `bin/walter-os-secrets`

This wraps the unlock + Infisical exchange into one command. See
`bin/walter-os` (the Walter-OS CLI) — it adds a `secrets` subcommand.

```bash
walter-os secrets unlock           # prompts Touch ID / Yubikey, caches session
walter-os secrets export <ws> <env>  # prints `export KEY=value` lines for sourcing
walter-os secrets run -- pnpm dev  # wraps a command with secrets injected
```

### 5. Wire into `.zshrc` (modular, lazy)

In `walter-os/shell/zsh.d/80-secrets.zsh`:

```zsh
# Lazy-load Infisical session per shell.
# Touch ID / Yubikey prompt happens ONLY on first use, not on every shell start.

walter_secrets_load() {
  local ws="${1:-walter-os}"
  local env="${2:-dev}"

  # Quick check: is there already a current session?
  if [[ -n "${INFISICAL_SESSION_LOADED:-}" ]]; then
    return 0
  fi

  # Pull machine identity from Keychain (triggers Touch ID / Yubikey prompt)
  local jwt
  jwt=$(security find-generic-password -s "walter-os.infisical" -a "$USER" -w 2>/dev/null) || {
    echo "✗ Could not fetch Infisical credentials from Keychain. Run: walter-os secrets setup" >&2
    return 1
  }

  # Use universal-auth login to exchange identity → session
  local client_id client_secret
  client_id=$(echo "$jwt" | jq -r .client_id)
  client_secret=$(echo "$jwt" | jq -r .client_secret)

  # Login (writes ~/.config/infisical/session)
  infisical login \
    --method=universal-auth \
    --client-id="$client_id" \
    --client-secret="$client_secret" \
    --domain=https://secrets.${WALTER_DOMAIN} >/dev/null

  # Inject the chosen workspace + env's secrets into THIS shell
  eval "$(infisical export --workspace-name="$ws" --env="$env" --format=shell 2>/dev/null)"

  export INFISICAL_SESSION_LOADED=1
}

# Don't auto-load on every shell — wasteful + Touch ID fatigue.
# Operator opts in per-context via aliases:
alias wos-load='walter_secrets_load walter-os dev'
alias [company]-load='walter_secrets_load [company] prod'
alias [project-a]-load='walter_secrets_load [project-a] dev'

# OR auto-load based on cwd:
walter_secrets_autoload() {
  case "$PWD" in
    "$HOME/work/"*)              walter_secrets_load [company] prod ;;
    "$HOME/Projects-Personal/[project-a]"*)  walter_secrets_load [project-a] dev ;;
    "$HOME/Projects-Personal/[project-b]"*) walter_secrets_load [project-b] dev ;;
    "$HOME/Projects-Personal/Hackatons/"*)
      local proj
      proj=$(basename "$PWD")
      walter_secrets_load hackaton "$proj" 2>/dev/null || true
      ;;
  esac
}

# Hook on cd via chpwd
typeset -ag chpwd_functions
chpwd_functions+=( walter_secrets_autoload )
```

### 6. Yubikey-only mode (no password fallback)

If you want strict "Yubikey present OR fail":

```bash
# Edit Keychain ACL to require Yubikey-bound key
# This needs CryptoTokenKit + your Yubikey enrolled as a smartcard
# (separate from FIDO2 credential)

ykman piv keys generate 9c /tmp/pubkey.pem
ykman piv certificates generate --subject "CN=walter-os-secrets" 9c /tmp/pubkey.pem
sc_auth pair  # macOS smartcard pairing — links Yubikey PIV to user account
```

Once paired, Keychain items can require the smart card key — no
Yubikey, no decryption, no password fallback.

## Operating modes — pick one

| Mode | Touch ID | Yubikey | Password | Use case |
|---|---|---|---|---|
| **Convenience** | ✅ | ✅ optional | ✅ macOS login | Daily dev — current default |
| **Strict** | ❌ | ✅ required | ❌ no fallback | [Company] secrets — paranoid mode |
| **Air-gapped** | ❌ | ❌ | ✅ once per 30 days | Long sessions, e.g. when traveling |

For your setup (computer at home most of the time):

- **Default**: Convenience (Touch ID OR Yubikey OR password).
- **[Company] context**: Strict (Yubikey required) — set this just for the
  `60-context-work.zsh` block.
- **Travel mode**: switch to Air-gapped temporarily via
  `walter-os secrets mode air-gapped --duration=14d`.

## 30-day refresh

Infisical machine identity tokens are configurable. Default Walter-OS
setup: 30-day TTL on the universal-auth secret, auto-rotated.

```bash
# Manual rotation
infisical machine-identity refresh-token --identity-id=<id>
# ↳ updates the secret in Infisical AND in your Keychain (script handles both)
```

The `walter-os secrets rotate` subcommand does this in one step.

## Hard rules

- **Never store secrets in the modular `.zsh.d/` files themselves.**
  Only references that pull from Keychain.
- **Never echo a fetched secret to stdout in a script.** Always pass
  via env var or stdin.
- **Yubikey + Touch ID is "OR", not "AND" (by default).** If you want
  AND, configure a 2-factor Keychain ACL (advanced — out of scope here).
- **Backup the Yubikey**. Have a second registered or written
  printed-recovery codes for Infisical.
- **macOS Keychain syncs to iCloud Keychain by default — DO NOT use
  iCloud Keychain for these items.** Keep them in `login.keychain-db`
  only, set `Synchronizable=NO` (the `security` command above does
  this by default).

## Why this approach

- **One credential to manage** (Infisical machine identity), not 20
  service-specific tokens.
- **Hardware-backed** (Touch ID Secure Enclave / Yubikey FIDO2/PIV) —
  stolen disk image still can't unlock.
- **No browser dependency** for daily use (no OAuth pop-ups every
  command).
- **Cross-context aware** — different workspaces auto-load based on
  cwd, no menu navigation.
- **30-day cache aligns with normal token rotation cadence.**

## What this skill does NOT cover

- iCloud Keychain syncing (intentionally avoided).
- 1Password CLI integration — use `op` if you prefer 1Password as
  source-of-truth instead of Infisical (different workflow, separate
  skill).
- VS Code / Cursor secret integration — extensions like "Secret Storage"
  or "Hashicorp Vault" can pull from these env vars at extension start.
- iOS/Android secrets — different platforms, different mechanisms.

## References

- Apple `security` man page (`man security`)
- https://infisical.com/docs/cli/usage
- https://developers.yubico.com/PIV/
- https://github.com/iyear/tdl (used by `telegram-summary` skill)
