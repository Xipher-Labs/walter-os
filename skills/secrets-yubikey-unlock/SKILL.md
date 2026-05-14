---
name: secrets-yubikey-unlock
description: Legacy-named Walter-OS guide for storing Infisical Machine Identity credentials in an OS credential store. Covers macOS Keychain, Linux Secret Service, pass+GPG, and optional hardware security keys. Use when the user asks how to auth Infisical from CLI, configure secrets bootstrap, set up keychain/keyring-backed secrets, or remove plaintext tokens from shell dotfiles.
---

# Secrets Bootstrap With OS Credential Stores

This skill keeps its original path for compatibility, but the policy is no
longer YubiKey-first. Walter-OS requires an OS credential store plus an
Infisical Machine Identity. Hardware security keys are optional hardening.

## Goal

- No plaintext Walter-OS API secrets in `.zshrc`, `.zprofile`, `.env`, or
  personal dotfiles.
- Store only the Infisical Machine Identity in a local credential store.
- Fetch live secrets from Infisical into the current shell when needed.
- Let operators choose their local unlock factor: Touch ID, login password,
  FIDO/security key, smartcard, Secret Service, or pass+GPG.

## Supported Stores

| Platform | Store | Bootstrap |
|---|---|---|
| macOS | Keychain via `security` | `walter-os secrets-identity-init --store macos-keychain` |
| Linux | Secret Service via `secret-tool` | `walter-os secrets-identity-init --store secret-service` |
| Linux fallback | `pass` + GPG | `walter-os secrets-identity-init --store pass` |

Default:

```bash
walter-os secrets-identity-init --store auto
```

`auto` chooses macOS Keychain on Darwin. On Linux it chooses Secret Service
when `secret-tool` exists, then `pass` when `pass` and `gpg` exist.

## Setup

### 1. Create an Infisical Machine Identity

In the Infisical web UI:

```text
Project -> Access Control -> Machine Identities -> Create Identity
Auth method: Universal Auth
Permissions: read-only on the required environment
```

Create one identity per device so a lost device can be revoked without
rotating every other workstation.

### 2. Store the Identity Locally

```bash
walter-os secrets-identity-init \
  --domain "https://secrets.example.com"
```

The command prompts for `client_id` and `client_secret`, verifies them against
Infisical without passing the secret in process arguments, and stores the JSON
blob plus the resolved Infisical domain in the selected credential store.
The domain must be a non-redirecting `https://` URL.

Domain fallback order:

1. `--domain`
2. `INFISICAL_DOMAIN`
3. `WALTER_INFISICAL_DOMAIN`
4. `https://secrets.$WALTER_DOMAIN`

### 3. Load Secrets Into the Current Shell

```bash
walter_secrets_load
walter_secrets_status
```

`walter_secrets_load` is a shell function because a CLI child process cannot
export variables into its parent shell. It reads the local identity, exchanges it
for an Infisical session, and evaluates the exported dotenv payload in the
current shell.

## Optional Hardware-Key Hardening

Walter-OS does not enforce hardware keys in the bootstrap script. Configure that
at the credential-store layer when wanted:

- macOS: Touch ID, login password, smartcard/PIV, or security-key policy.
- Linux Secret Service: desktop keyring unlock policy.
- `pass`: GPG key policy, including hardware-backed GPG keys if desired.

This keeps onboarding open for operators without security keys while still
allowing stricter local policies.

## Safety Notes

- Do not sync the credential-store item through Git or Syncthing.
- Prefer one Machine Identity per device.
- Revoke the device identity in Infisical when a device is lost.
- Do not reintroduce `~/.config/walter-os/secrets.env` as a secret source of
  truth. It is legacy development-only state and should be removed after the
  runtime path works.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Infisical domain is not configured` | Pass `--domain`, set `INFISICAL_DOMAIN`, set `WALTER_INFISICAL_DOMAIN`, or set `WALTER_DOMAIN`. |
| `No supported Linux credential store found` | Install `libsecret-tools gnome-keyring`, or install and initialize `pass` + `gpg`. |
| `Login failed` | Recreate the Machine Identity or check that it has read permissions for the target environment. |
| Credential prompt repeats too often | Check `WALTER_SECRETS_LOADED_AT` and whether each terminal starts a fresh shell session. |

## References

- `docs/specs/secrets-runtime-architecture.md`
- `docs/operational/operator-setup-runbook.md`
- `scripts/secrets-identity-init.sh`
