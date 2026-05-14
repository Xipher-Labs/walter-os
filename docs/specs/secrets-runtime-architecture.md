# SPEC: secrets runtime architecture

**Status:** Approved, updated for issue #33 on 2026-05-13.
**Related:** `skills/secrets-yubikey-unlock/SKILL.md` (legacy name),
`skills/infisical-agent/SKILL.md`.

Walter-OS loads operator secrets from Infisical at runtime. The only local
bootstrap credential is an Infisical Machine Identity stored in the operating
system's credential store.

## 1. Locked decisions

| Question | Decision |
|---|---|
| Source of truth | Infisical is the source of truth for Walter-OS secrets. |
| Bootstrap credential storage | Store the Machine Identity in an OS credential store, never in plaintext dotenv. |
| Hardware keys | YubiKey, FIDO/security keys, smartcards, Touch ID, and login password are optional OS/keyring hardening factors. Walter-OS does not require a hardware key by default. |
| Supported client OS for P1 | macOS and Linux. Windows Credential Manager is future work. |
| macOS backend | Keychain via `security`. |
| Linux backend | Secret Service via `secret-tool`; explicit fallback to `pass` + GPG. |
| Session duration | 12 hours. After 12h since last unlock, the next `walter_secrets_load` prompts via the configured credential store. |
| Per-device identity | Yes. Each device should get its own Infisical Machine Identity for revocation granularity. |
| Bitwarden role | Retired for Walter-OS API secrets. Bitwarden may still be used for personal website passwords. |

## 2. Threat model

| Threat | Legacy state | Target state |
|---|---|---|
| Workstation disk image leak | Plaintext `secrets.env` leaks every key. | Bootstrap identity is encrypted by the OS credential store; live secrets are fetched at runtime. |
| Backup leak | Dotfiles may include secrets. | No Walter-OS bootstrap secrets are written to tracked files or dotenv files. |
| Same-user malware | Can read plaintext files immediately. | Must trigger or bypass the OS credential-store prompt; shell env still remains in scope once loaded. |
| Lost device | All copied secrets remain valid until each provider is rotated. | Revoke that device's Infisical Machine Identity. |
| Cross-device setup | Copying secret files creates uncontrolled replicas. | Repeat identity bootstrap per device. |

This does not provide per-process zero trust. Once secrets are exported into the
current shell, child processes can read that environment.

## 3. Target architecture

```text
Operator device
  |
  | one-time: walter-os secrets-identity-init
  v
OS credential store
  macOS: Keychain
  Linux: Secret Service, or pass + GPG
  value: {"client_id":"...","client_secret":"...","domain":"https://..."}
  |
  | runtime: walter_secrets_load
  v
Infisical universal-auth session
  |
  | infisical export --format=dotenv
  v
Current shell environment only
  |
  v
Claude Code, Codex CLI, MCPs, scripts, and walter-host operators
```

Key invariants:

- The bootstrap identity lives only in the configured OS credential store.
- The resolved Infisical domain is stored with the identity so fresh shells can
  load secrets even when setup used the `--domain` flag.
- `~/.config/walter-os/secrets.env` is legacy and must not be recreated as a
  bootstrap credential store.
- Hardware-backed auth is configured outside Walter-OS, at the OS/keyring layer.
- The canonical setup command is `walter-os secrets-identity-init`.
- `walter-os secrets-keychain-init` is a deprecated compatibility alias.
- Bootstrap verification sends the Infisical Universal Auth request body on
  stdin. The Machine Identity secret must not be passed as a `curl`, `jq`, or
  `infisical login` process argument. Verification succeeds only on a real 2xx
  Universal Auth response; redirects are rejected.

## 4. Bootstrap command contract

`walter-os secrets-identity-init` accepts:

```bash
walter-os secrets-identity-init \
  --store auto \
  --domain https://secrets.example.com
```

Options:

| Option | Behavior |
|---|---|
| `--store auto` | macOS -> `macos-keychain`; Linux -> usable `secret-service`, then `pass`. |
| `--store macos-keychain` | Force macOS Keychain via `security`. |
| `--store secret-service` | Force Linux Secret Service via `secret-tool`. |
| `--store pass` | Force `pass` + GPG. |
| `--domain <url>` | Infisical base URL. Must be non-redirecting `https://`. |
| `--yes` | Replace an existing local identity entry without prompting. |

When replacing an existing identity, the old credential-store entry remains in
place until the new Machine Identity has been verified and the replacement write
succeeds. A failed rotation must not break the currently working identity.

Domain fallback order:

1. `--domain`
2. `INFISICAL_DOMAIN`
3. `WALTER_INFISICAL_DOMAIN`
4. `https://secrets.$WALTER_DOMAIN`

If no domain can be resolved, the command fails before prompting for credentials.

## 5. Backend behavior

### macOS Keychain

- Requires `/usr/bin/security`.
- Stores service `walter-os.infisical-identity`, account `$USER`.
- Passes the JSON identity through Keychain prompt stdin mode, not as a
  `security -w <secret>` process argument.
- Uses `-T ""` so no app is pre-authorized without a Keychain decision.
- Touch ID, login password, smartcard, and security-key behavior are controlled
  by macOS policy, not by Walter-OS.

### Linux Secret Service

- Requires `secret-tool` from `libsecret-tools`.
- Stores attributes `service=walter-os.infisical-identity` and `account=$USER`.
- The active keyring provider may be GNOME Keyring, KWallet, or another
  Secret Service implementation.
- `auto` probes Secret Service before selecting it. Headless or locked
  sessions fall back to `pass` when `pass` + `gpg` are available.

### pass + GPG

- Requires `pass` and `gpg`.
- Stores entry `walter-os/infisical-identity` by default.
- `WALTER_SECRETS_PASS_ENTRY` may override the path.
- Hardware-backed GPG keys are optional and configured by the operator.

## 6. Runtime shell contract

`walter_secrets_load` remains a shell function because it must export variables
into the current shell. Its expected behavior:

1. Fast-path if `WALTER_SECRETS_LOADED_AT` is present and younger than 12 hours.
2. Read the Machine Identity from the OS credential store.
3. Exchange it with Infisical using universal-auth.
4. Export Infisical secrets into the current shell only.
5. Set `WALTER_SECRETS_LOADED_AT`.

Wrappers such as `claude`, `codex`, `gh`, and deployment helpers may call
`walter_secrets_load` lazily before operations that need secrets.

## 7. Migration plan

1. Create one Infisical Machine Identity per device with read-only permissions
   for the required environment.
2. Run `walter-os secrets-identity-init`.
3. Open a fresh shell and run `walter_secrets_load`.
4. Verify required CLI secrets are present.
5. Remove legacy plaintext `~/.config/walter-os/secrets.env` after the runtime
   path has worked for the operator.

## 8. Non-goals

- Windows Credential Manager support.
- Enforcing security-key presence in Walter-OS scripts.
- Replacing the operator's OS credential store.
- Creating a plaintext fallback for bootstrap credentials.
- Per-process secret confinement after secrets are exported into a shell.

## 9. Acceptance criteria

- A fresh macOS operator can bootstrap with Keychain and no YubiKey.
- A fresh Linux operator can bootstrap with Secret Service or explicit `pass`.
- The bootstrap script and docs agree that hardware keys are optional hardening.
- Missing credential-store backends fail closed with install hints.
- Missing Infisical domain fails before credential prompts.
- Existing identity replacement requires confirmation unless `--yes` is passed.
- Public docs point to `walter-os secrets-identity-init` as the canonical command.

---

## 10. Per-service LiteLLM virtual keys

Services that need LLM access (e.g., OpenClaw) do NOT use the operator's
primary `LITELLM_MASTER_KEY`. Each service receives a scoped virtual key.

| Service | Key name | Scope |
|---|---|---|
| OpenClaw (assistant profile) | `LITELLM_OPENCLAW_KEY` | Allowed models: `sonnet`, `haiku`, `cheap` |
| Other future services | `LITELLM_<SERVICE>_KEY` | Scoped per service |

Virtual keys are created in the LiteLLM admin UI under `Settings -> Virtual Keys`.
Revocation of a service key does not affect other services or the master key.

The pattern for OpenClaw:

```bash
# In LiteLLM admin UI, or via API:
# POST /key/generate
# { "max_budget": 5, "models": ["sonnet", "haiku", "cheap"], "duration": "30d" }
# Copy the returned key to Infisical as LITELLM_OPENCLAW_KEY
```

---

## 11. Secret rotation playbook

When a secret is compromised or expired:

1. **Identify scope**: which services use this secret? Check compose files and `.env.example`.
2. **Generate new value**: `openssl rand -hex 32` for tokens; provider portal for API keys.
3. **Update Infisical**: web UI -> walter-os/dev -> update value. Do not commit to git.
4. **Reload shell**: `walter_secrets_load --force` on each active shell session.
5. **Restart affected services**: `docker compose restart <service>`.
6. **Verify**: check service healthcheck and test one LLM request through the gateway.
7. **Revoke old**: deactivate the old key in the upstream provider's dashboard.

For `LITELLM_MASTER_KEY`: restart LiteLLM and all services that use virtual keys.
Virtual keys are server-side records in LiteLLM's DB and survive master key
rotation if you use the LiteLLM regenerate API endpoint first.

---

## 12. Gitleaks integration (secret leak prevention)

Walter-OS ships a `gitleaks` pre-commit hook to prevent secrets from entering
the repository. This is a defense-in-depth layer complementing Infisical.

**Hook location**: `.githooks/pre-commit` (checked into the repo)
**Installer**: `scripts/setup-githooks.sh` (idempotent, called by `install.sh`)
**Config**: `.gitleaks.toml` (allow-listing tests/fixtures/ for test fixtures)

Setup:

```bash
# Manual:
bash scripts/setup-githooks.sh

# Automatic:
./install.sh
```

The hook runs `gitleaks protect --staged --config .gitleaks.toml` on every
`git commit`. If a secret is detected, the commit is blocked with a clear error
message showing which file and rule triggered.

Allowlisted paths:

- `tests/fixtures/` - fake keys for bats test cases.
- Files matching `*.example` - template placeholder values.

See `tests/hooks/gitleaks.bats` and `tests/hooks/install-pre-commit.bats` for
regression coverage.

---

## 13. CCR_APIKEY (Claude Code Router)

The claude-code-router (CCR) requires an API key for its internal routing
gateway. This is NOT an Anthropic or OpenAI API key; it is a shared secret
between the CCR gateway and LiteLLM.

- **Variable**: `CCR_APIKEY`
- **Scope**: `setup/walter-host/services/llm-proxies/compose.yml`
- **Required form**: `:?` (fail-loud; container will not start without it)
- **Generate**: `openssl rand -hex 32`
- **Store in**: Infisical `walter-os/dev` -> key `CCR_APIKEY`

Do not use `ccr-internal` or any hardcoded value. The `:?` form in Compose
ensures the container exits immediately with a clear error if the variable is
unset, rather than silently using a weak default.
