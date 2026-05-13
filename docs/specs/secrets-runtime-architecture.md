# SPEC: in-memory secrets runtime

**Status:** Approved (2026-05-05). Decisions locked, implementation in progress.
**Triggered by:** Operator pushback on `~/.config/walter-os/secrets.env` being plain dotenv on disk.
**Related:** `skills/secrets-yubikey-unlock/SKILL.md` (designed but not wired), `skills/infisical-agent/SKILL.md`.

## Operator decisions (locked 2026-05-05)

| Question | Decision |
|---|---|
| Yubikey requirement | **HARD-required.** No Touch ID fallback. No password fallback. Yubikey must be present (or its FIDO2 credential cached within session window). |
| Session duration | **12 hours.** After 12h since last unlock, next `walter_secrets_load` triggers Yubikey prompt. |
| Failure semantics | **Auto-reauth on read failure**, ansible-vault style. If a secret read fails (401, expired session, missing key), the runtime triggers a fresh unlock and retries the operation transparently. Never silently fail; never block forever. |
| Bitwarden role | **Retired** for walter-os. Operator uses Bitwarden for personal site passwords, not walter-os secrets. **Infisical = single source of truth** for all walter-os secrets. |
| Per-device Machine Identity | **Yes.** Each device has its own walter-os Infisical Machine Identity for revocation granularity. |
| Multi-context wiki (related question) | One global `walter-os/wiki/`, private Forgejo mirror — see `karpathy-llm-wiki-compliance.md`. |

---

## 0. Honest state of things (2026-05-05)

I (the agent) repeatedly described "Bitwarden `walter-os/secrets`" and `~/.config/walter-os/secrets.env` as if both were operational and secure. **They're not.** Reality:

| Thing | Claim | Reality |
|---|---|---|
| Bitwarden `walter-os/secrets` item | "Source of truth, cross-device" | **Doesn't exist.** `walter-os secrets-bootstrap` was written but never run. Only the script + template. |
| `~/.config/walter-os/secrets.env` | "Local cache, mode 600, gitignored" | Exists, mode 600, but **plain text on disk.** Anyone with read access to the host home directory reads every API key. Doesn't survive snapshot/backup-leak threat. |
| `walter-os secrets-pull` | "Fetches Bitwarden → secrets.env" | Implemented but useless until the BW item exists. |
| `secrets-yubikey-unlock` skill | "Touch ID / Yubikey unlocks Infisical CLI" | **Documented only.** No `secrets_load()` zsh function, no Keychain-backed wrapper, no walter-os subcommand. |
| Multi-account ANTHROPIC_ENTERPRISE_KEY | "In secrets.env, picked up by claude wrapper" | Wrapper reads it; it's empty in operator's secrets.env. Wrapper fails-loud, which is correct, but no workflow to populate it. |

**What we DID accomplish on 2026-05-05:**

- Pushed all 53 secrets currently in `~/.config/walter-os/secrets.env` (Plane DB pass, LiteLLM master, AI provider keys, CF admin, etc.) into Infisical `walter-os/dev`. Single source of truth as of today: **Infisical**.

---

## 1. Threat model the new system must defeat

| Threat | Status today | Goal |
|---|---|---|
| Disk imaging of operator workstation (stolen, repaired, decommissioned) | ❌ secrets.env readable | ✅ no secrets on disk except OS-encrypted keychain storage (FileVault layer + Keychain encryption + Yubikey gate) |
| Malicious Mac process running as operator | ❌ reads secrets.env directly | ⚠️ partially mitigated — Keychain ACL requires Touch ID/Yubikey; ephemeral env vars in shell still readable from process tree |
| Backup leak (Time Machine, restic, iCloud) | ❌ secrets.env in `~/.config` may not be excluded | ✅ Keychain doesn't go to backups by default; backup integrations explicitly exclude operator dotfiles with secrets |
| Walter-VM compromise | ⚠️ Infisical compromised → operator AI keys leaked | ⚠️ unchanged at this layer; mitigate via #3 (HA) and audit logs |
| Single-machine total loss | Recoverable from Infisical (we just pushed) | ✅ Infisical is the source of truth |

---

## 2. Target architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                   OPERATOR'S MACHINE                              │
│                                                                   │
│  Yubikey 5C (always plugged OR cached)                           │
│     │                                                             │
│     │ FIDO2 / OpenPGP smartcard                                  │
│     ▼                                                             │
│  macOS Keychain  (login.keychain-db, FileVault-protected)        │
│     │   service: walter-os.infisical-identity                    │
│     │   value:   {"client_id":"...","client_secret":"..."}       │
│     │   ACL:     access requires Touch ID OR Yubikey-PIV         │
│     ▼                                                             │
│  walter_secrets_load()  ← shell function                         │
│     │   1. fetch JWT from Keychain (triggers Touch ID)           │
│     │   2. exchange JWT → Infisical session token                │
│     │   3. infisical export --format=dotenv → eval in CURRENT     │
│     │      shell. NEVER WRITES TO DISK.                          │
│     │   4. session valid 15 min, auto-refreshed                  │
│     ▼                                                             │
│  Shell env vars (in-memory only)                                 │
│     │   ANTHROPIC_API_KEY=...                                    │
│     │   GITHUB_TOKEN=...                                         │
│     │   ...                                                      │
│     ▼                                                             │
│  CLIs / MCPs / scripts read env vars                             │
└──────────────────────────────────────────────────────────────────┘
                               │
                               │ HTTPS + JWT auth
                               ▼
                ┌──────────────────────────────────┐
                │  Infisical (Walter-VM, HA, see   │
                │  walter-vm-ha.md spec)           │
                │   walter-os/dev (operator vault) │
                │   walter-os/prod (services)      │
                └──────────────────────────────────┘
```

### Key invariants

1. **No plaintext secrets on disk** outside macOS Keychain (which is FileVault + Keychain-key encrypted, ACL'd).
2. **Bootstrap creds in Keychain only.** Yubikey/Touch ID required to unlock.
3. **Live secrets in shell env only.** They die when the shell dies.
4. **No `~/.config/walter-os/secrets.env`** in the new world. File is deleted on cutover.
5. **Single source of truth: Infisical.** Bitwarden retired (or kept as "vault for human-readable creds" — passwords for sites, not API keys).
6. **15-minute Infisical session** with auto-refresh (Infisical CLI default).

---

## 3. Bootstrap problem & solution

> "To fetch from Infisical through the API, you need credentials that cannot live in Infisical itself. Where do they go?"

**Answer: macOS Keychain, gated by Yubikey/Touch ID.**

Keychain entries can have ACLs that require:
- Specific applications (e.g., only `infisical` binary)
- User authentication (Touch ID by default)
- Custom prompts

When you load a Yubikey (USB PIV smartcard), macOS treats it as an additional auth factor. The Keychain entry can be configured to require **either** Touch ID **or** Yubikey-PIV, so:

- Yubikey plugged in → fingerprint not needed (Yubikey IS the proof)
- Yubikey not present → fall back to Touch ID
- Both unavailable → fall back to operator login password (default macOS behavior)

```bash
# Create the Keychain item with restrictive ACL:
security add-generic-password \
  -s "walter-os.infisical-identity" \
  -a "$USER" \
  -w '{"client_id":"...","client_secret":"..."}' \
  -T ""  # no apps allowed by default; prompts every read

# Apply ACL: require Touch ID OR Yubikey-PIV via security cli
# (the exact ACL flags depend on macOS version; see secrets-yubikey-unlock skill)
```

The shell function `walter_secrets_load`:

```zsh
# Logic spec — full implementation in
# config-personal/templates/zsh.d/85-secrets-runtime.zsh
walter_secrets_load() {
  local force="${1:-}"
  local last_unlock_marker="$HOME/.config/walter-os/.last-unlock"
  local SESSION_HOURS=12

  # Check session age. If < 12h AND --force not passed AND we already
  # have a session-marker var in the shell, fast-path: no-op.
  if [[ "$force" != "--force" && -n "${WALTER_SECRETS_LOADED_AT:-}" ]]; then
    local now last age
    now=$(date +%s); last="$WALTER_SECRETS_LOADED_AT"
    age=$(( now - last ))
    (( age < SESSION_HOURS * 3600 )) && return 0
  fi

  # 1. Verify Yubikey present (hard-required, NO fallback).
  if ! ykman info 2>/dev/null | grep -q 'Serial number'; then
    echo "✗ walter_secrets_load: Yubikey not detected." >&2
    echo "  Walter-OS policy: Yubikey is hard-required. Plug it in." >&2
    return 2
  fi

  # 2. Read the machine-identity JWT from Keychain (Yubikey-PIV gates this).
  local jwt
  jwt=$(security find-generic-password \
    -s "walter-os.infisical-identity" -a "$USER" -w 2>/dev/null) || {
    echo "✗ Could not read Keychain entry. Run: walter-os secrets-keychain-init" >&2
    return 3
  }

  # 3. Exchange machine-identity for short-lived Infisical session.
  local client_id client_secret
  client_id=$(echo "$jwt" | jq -r .client_id)
  client_secret=$(echo "$jwt" | jq -r .client_secret)

  infisical login --method=universal-auth \
    --client-id="$client_id" --client-secret="$client_secret" \
    --domain="https://secrets.${WALTER_DOMAIN}" --plain >/dev/null || return 4

  # 4. Export secrets into CURRENT shell. eval only — never written to disk.
  local export_output
  export_output=$(infisical export \
    --domain=https://secrets.${WALTER_DOMAIN} \
    --projectId=8b4d37fa-8a03-4176-9787-69cf4f171324 \
    --env=dev --format=dotenv 2>/dev/null) || return 5
  eval "$export_output"
  unset export_output

  # 5. Record session marker (in env, NOT on disk for the secrets themselves).
  export WALTER_SECRETS_LOADED_AT=$(date +%s)
  date +%s > "$last_unlock_marker"  # convenience for cross-shell visibility

  echo "✓ Secrets loaded — session valid until $(date -r $(($(date +%s) + SESSION_HOURS * 3600)) +'%H:%M')"
}

# Auto-reauth wrapper (the ansible-vault pattern).
# Use this when invoking a command that REQUIRES secrets and might fail
# because a secret was empty / session expired. Detects auth-failure
# patterns in stderr and retries once after walter_secrets_load --force.
walter_run_with_secrets() {
  local out err rc
  err=$(mktemp)
  "$@" 2> >(tee "$err" >&2); rc=$?

  if (( rc != 0 )) && grep -qE '401|Unauthorized|missing key|expired|empty token' "$err"; then
    echo "→ secrets-aware retry: re-authenticating..." >&2
    walter_secrets_load --force || { rm -f "$err"; return $rc; }
    "$@"; rc=$?
  fi
  rm -f "$err"
  return $rc
}
```

**Auto-reauth flow** (ansible-vault parity):

1. Tool fails with auth-related error (`401`, `Unauthorized`, `missing key`, etc.).
2. `walter_run_with_secrets` greps stderr for that pattern.
3. Triggers `walter_secrets_load --force` (which re-prompts Yubikey if past 12h).
4. Retries the original command exactly once.
5. If still fails → bubble up actual error (don't loop).

Wrappers `claude()`/`codex()`/`gh()` call `walter_secrets_load` (no force) at session start; the lazy-fast-path makes this <50 ms when session is valid. They use `walter_run_with_secrets` to wrap the tool invocation so transient secret expiry is handled silently.

```zsh
claude() {
  walter_secrets_load || return $?  # lazy: only reauths if expired
  # ... existing wrapper logic for work/personal profile routing ...
  walter_run_with_secrets command claude "$@"
}
```

---

## 4. Migration plan (incremental, non-destructive)

### Phase A — Foundation (1-2h)

1. ✅ All current `secrets.env` contents pushed to Infisical (done 2026-05-05).
2. Create Infisical Machine Identity: walter-os web UI → Settings → Machine Identities → "operator-mac-A". Universal-auth method. Read-only on `walter-os/dev`.
3. Save `client_id` + `client_secret` JSON blob into macOS Keychain via `security` CLI.
4. Apply Keychain ACL requiring Touch ID OR Yubikey-PIV.
5. Test: `walter_secrets_load` triggers prompt, fetches secrets, exports them.

### Phase B — Shell integration (1h)

1. Add `walter_secrets_load` function to `config-personal/templates/zsh.d/85-secrets-runtime.zsh`.
2. Replace blanket `source ~/.config/walter-os/secrets.env` (in 80-secrets.zsh) with explicit calls + lazy aliases.
3. Add `walter-os secrets-status` subcommand: shows whether session is active, expiry, count of loaded vars.
4. Add `walter-os secrets-clear` subcommand: nukes session token, forces re-auth.

### Phase C — Cutover (operator-decision)

1. Operator runs `walter_secrets_load` in fresh shell. Verifies all expected vars present.
2. Operator opens new shell to use any tool — confirms it still works.
3. Run `shred -u ~/.config/walter-os/secrets.env` (or `srm -z`).
4. Replace `walter-os secrets-pull` with deprecation notice pointing to runtime fetch.
5. Walter-OS install.sh stops creating the secrets.env template (new file: `~/.config/walter-os/runtime.env` for non-secret runtime config like paths).

### Phase D — Second device (operator's other Mac, future)

1. Same Machine Identity OR new one (per-device). Decision: per-device for blast-radius (revoke one device without revoking all).
2. Write the JSON to that Mac's Keychain via the same `security` cmd.
3. `walter_secrets_load` works identically.

---

## 5. What stays in `~/.config/walter-os/`

After cutover:
- `env` — non-secret operator config: paths (WALTER_OS_HOME, WALTER_*_PATH), service URLs (PLANE_API_URL, INFISICAL_DOMAIN). Sourced eagerly. No secrets.
- `acks.json` — finding acknowledgements (audit gate state).
- `audit-*.md` — daily audit reports.
- `baselines/` — config drift baselines (sha256 of settings.json etc.).
- `hook-checksums.json` — hook integrity baselines.
- ❌ `secrets.env` — **deleted** at cutover.

---

## 6. Why this is better than current state

| Current | Future |
|---|---|
| 53 plaintext secrets in `secrets.env` | 0 plaintext secrets at rest |
| Backup leak = full key compromise | Backup leak = needs Yubikey + Mac to use Keychain blob (with ACL) + Mac's user password |
| Lost Mac = burner-grade leak | Lost Mac = encrypted Keychain blob, Yubikey ACL still required, plus FileVault |
| Same-machine malware = trivial read | Same-machine malware = must trigger Touch ID/Yubikey prompt to extract; 15-min session limit |
| Cross-device sync = manual `secrets-pull` | Cross-device = each device has its own Machine Identity, can be revoked individually |
| No revocation granularity | Per-device revocation (revoke `operator-mac-A`, others keep working) |

---

## 7. Open questions for operator

1. **Yubikey requirement: hard or soft?** If soft (Touch ID acceptable fallback), shell still works without Yubikey plugged in. If hard, every secret-fetch requires the physical key.
2. **Per-device Machine Identity vs shared?** Per-device is more secure (independent revocation) but more setup work (one Identity per Mac).
3. **What about non-Mac (future local LLM node / Linux)?** Keychain doesn't exist; equivalent on Linux is `pass` + GPG smartcard, or `keyring` + libsecret. Out of scope for v1; revisit when local LLM node lands.
4. **Bitwarden — keep or retire?** Keep for human-readable creds (website passwords)? Or fully delete, leaving Infisical as the only walter-os secret store?

---

## 8. Non-goals (explicitly OUT of scope)

- Replacing macOS Keychain with a different store. It's the right tool.
- Hardware Security Module (HSM) — overkill for personal use.
- Encrypted overlay filesystems for `~/.config/walter-os/`. Solved better at Keychain layer.
- "Zero-trust" per-process secret scoping. Out of scope; would require Linux + AppArmor or similar.

---

## 9. Acceptance criteria

- [ ] `~/.config/walter-os/secrets.env` deleted; nothing breaks.
- [ ] Fresh `zsh` invocation: `walter_secrets_load` triggers Touch ID/Yubikey prompt exactly once.
- [ ] All operator CLIs (`claude`, `codex`, `gh`, `vercel`, `hcloud`, `infisical`) work after one load.
- [ ] `ps auxe | grep ANTHROPIC_API_KEY` does NOT show secrets in another user's process listing (env vars are per-process, not world-readable on macOS).
- [ ] Removing the Yubikey + locking the screen → next `walter_secrets_load` requires fresh unlock.
- [ ] Audit log on Infisical shows individual machine-identity reads (per-device traceability).

Implementation = follow-up PR. This spec is the contract.

---

## 10. Per-service LiteLLM virtual keys

Services that need LLM access (e.g., OpenClaw) do NOT use the operator's
primary `LITELLM_MASTER_KEY`. Each service receives a scoped virtual key.

| Service | Key name | Scope |
|---|---|---|
| OpenClaw (assistant profile) | `LITELLM_OPENCLAW_KEY` | Allowed models: `sonnet`, `haiku`, `cheap` |
| Other future services | `LITELLM_<SERVICE>_KEY` | Scoped per service |

Virtual keys are created in the LiteLLM admin UI under `Settings → Virtual Keys`.
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

1. **Identify scope**: which services use this secret? (check compose files and `.env.example`)
2. **Generate new value**: `openssl rand -hex 32` for tokens; provider portal for API keys.
3. **Update Infisical**: web UI → walter-os/dev → update value. Do NOT commit to git.
4. **Reload shell**: `walter_secrets_load --force` on each active shell session.
5. **Restart affected services**: `docker compose restart <service>` — containers pick up
   new env vars on next start.
6. **Verify**: check service healthcheck + test one LLM request through the gateway.
7. **Revoke old**: deactivate the old key in the upstream provider's dashboard.

For `LITELLM_MASTER_KEY`: restart litellm + all services that use virtual keys
(virtual keys are server-side records in LiteLLM's DB — they survive master key
rotation if you use the LiteLLM `regenerate` API endpoint first).

---

## 12. Gitleaks integration (secret leak prevention)

Walter-OS ships a `gitleaks` pre-commit hook to prevent secrets from entering
the repository. This is a defense-in-depth layer complementing Infisical —
even if a developer accidentally pastes a key into source code, the commit is
rejected before it reaches the remote.

**Hook location**: `.githooks/pre-commit` (checked into the repo)
**Installer**: `scripts/setup-githooks.sh` (idempotent, called by `install.sh`)
**Config**: `.gitleaks.toml` (allow-listing tests/fixtures/ for test fixtures)

Setup:

```bash
# Manual:
bash scripts/setup-githooks.sh

# Automatic (runs as part of install.sh):
./install.sh
```

The hook runs `gitleaks protect --staged --config .gitleaks.toml` on every
`git commit`. If a secret is detected, the commit is blocked with a clear error
message showing which file and rule triggered.

Allowlisted paths (legitimate fake-secret test fixtures):
- `tests/fixtures/` — fake keys for bats test cases
- Files matching `*.example` — template placeholder values

See `tests/hooks/gitleaks.bats` and `tests/hooks/install-pre-commit.bats` for
regression coverage.

---

## 13. CCR_APIKEY (Claude Code Router)

The claude-code-router (CCR) requires an API key for its internal routing
gateway. This is NOT an Anthropic or OpenAI API key — it is a shared secret
between the CCR gateway and LiteLLM.

- **Variable**: `CCR_APIKEY`
- **Scope**: `setup/walter-host/services/llm-proxies/compose.yml`
- **Required form**: `:?` (fail-loud — container will not start without it)
- **Generate**: `openssl rand -hex 32`
- **Store in**: Infisical `walter-os/dev` → key `CCR_APIKEY`

Do NOT use `ccr-internal` or any hardcoded value. The `:?` form in Compose
ensures the container exits immediately with a clear error if the variable is
unset, rather than silently using a weak default.
