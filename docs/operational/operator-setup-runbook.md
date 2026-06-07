# Operator setup runbook

> Companion to `onboarding-checklist.md`. The checklist tells you
> *what* is left; this runbook tells you *exactly how*. Each section
> has prerequisites, commands, success check, and troubleshooting.
>
> Order: do **steps 1, 2, 3** first (they unlock the rest). The other
> five are independent.

---

## Prerequisites (one-time, before step 1)

| Tool | Install | Why |
|---|---|---|
| `infisical` | `brew install infisical/get-cli/infisical` | Fetch secrets at runtime |
| macOS Keychain | built in | Stores the Infisical Machine Identity on macOS |
| `secret-tool` (Linux) | `sudo apt-get install -y libsecret-tools gnome-keyring` | Stores the Infisical Machine Identity via Secret Service |
| `pass` + `gpg` (Linux fallback) | `sudo apt-get install -y pass gnupg` | Optional encrypted fallback if Secret Service is unavailable |
| YubiKey / security key (optional) | physical + OS setup | Optional credential-store hardening, not required by Walter-OS |
| `bw` (optional) | `brew install bitwarden-cli` | Only if you keep using BW for personal site passwords |
| Anthropic Console access | [console.anthropic.com](https://console.anthropic.com) ([Company] enterprise) | For step 2 |
| B2 account (defer until step 6) | [Backblaze](https://www.backblaze.com) | Offsite backup target |

Verify:
```bash
which infisical claude codex
# Linux only: one of these should exist before secrets bootstrap:
which secret-tool || which pass
```

If anything's missing, fix it before continuing.

## Step 0 — AI capability profile (2 min)

**Goal**: tell Walter-OS which AI tools this operator or device can actually
use. This keeps workflows from assuming Claude, Codex, Copilot, Gemini, and a
local LLM are all present.

```bash
walter providers configure --category llm
walter ai configure --profile mixed
walter ai status
```

Use `claude-only`, `codex-only`, `gemini-only`, or `local-only` instead of
`mixed` when that matches the actual account/tool availability. Details:
[`ai-capability-profiles.md`](ai-capability-profiles.md).

---

## Step 1 — Secrets runtime (5 min) 🔐

**Goal**: replace `~/.config/walter-os/secrets.env` plain dotenv with
runtime fetch from Infisical, gated by the local OS credential store,
in-memory only, 12h session.

### 1a. Create Infisical Machine Identity (web UI, ~2 min)

1. Open `https://secrets.${WALTER_DOMAIN}` (Google login via CF Access).
2. Switch project: **walter-os**.
3. Sidebar → **Access Control** → **Identities** → **Create Identity**.
4. Name: `operator-mac-A` (use `mac-B` for second device, etc.).
5. **Auth Method**: Universal Auth.
6. **Permissions**: add policy → environment `dev` → **Read** only.
   (No write — runtime never needs to set secrets, just read them.)
7. Save. Copy the `client_id` and `client_secret` shown ONCE — you
   won't see the secret again.

> 💡 If you fat-finger the secret, just delete the identity and make
> a new one. Cheap to redo.

### 1b. Bootstrap local credential store (~30 sec)

```bash
walter-os secrets-identity-init
# Prompts:
#   client_id: <paste>
#   client_secret (hidden): <paste>
# It writes the encrypted bootstrap identity to macOS Keychain,
# Linux Secret Service, or pass+GPG.
```

### 1c. Test (~30 sec)

Open a fresh shell:
```bash
walter_secrets_load           # → first call: credential-store prompt
walter_secrets_status         # → "Session active. Expires in 11h 59m..."
echo $ANTHROPIC_API_KEY | head -c 20  # → starts with sk-ant-
```

### 1d. Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not read local identity entry` | You haven't run 1b yet. Or the entry got deleted — re-run. |
| `Infisical login failed` | client_id/secret wrong, OR the Machine Identity was deleted. Re-create in 1a. |
| Credential prompt on EVERY call (not 12h) | The shell session marker (`WALTER_SECRETS_LOADED_AT` env var) didn't persist. New tab = new shell = re-fetch. That's by design. To survive across tabs: tmux/zellij or a long-running shell. |
| Want to force re-auth before 12h | `walter_secrets_clear` then next `walter_secrets_load` will prompt. |

### 1e. Finalize (after a week of working flawlessly)

```bash
srm -z ~/.config/walter-os/secrets.env
# Confirm the legacy file is gone:
ls -la ~/.config/walter-os/secrets.env  # → No such file
```

---

## Step 2 — ANTHROPIC_ENTERPRISE_KEY (3 min) 🏢

**Goal**: route Claude Code to [Company]'s enterprise quota when working
in `~/work/*` (compliance), personal Pro everywhere else.

### 2a. Get the key (~1 min)

1. [console.anthropic.com](https://console.anthropic.com) — log in with **[Company]'s enterprise
   workspace** (NOT your personal account).
2. Sidebar → **API Keys** → **Create Key**.
3. Name: `walter-os-mac-A`. Workspace: [Company]'s. Permissions:
   default. **Save** — you only see the value once.
4. Copy the key (starts with `sk-ant-...`).

### 2b. Push to Infisical (~1 min)

Easiest: web UI.

1. `https://secrets.${WALTER_DOMAIN}` → walter-os → env=`dev` →
   **+ Add Secret**.
2. Key: `ANTHROPIC_ENTERPRISE_KEY`. Value: paste.
3. Save.

Or via CLI:
```bash
walter_secrets_load   # ensure session is active
infisical secrets set ANTHROPIC_ENTERPRISE_KEY=sk-ant-... \
  --domain=https://secrets.${WALTER_DOMAIN} \
  --projectId=8b4d37fa-8a03-4176-9787-69cf4f171324 \
  --env=dev
```

### 2c. Test (~1 min)

```bash
walter_secrets_load --force   # pull the new value
echo $ANTHROPIC_ENTERPRISE_KEY | head -c 20   # → sk-ant-...

cd ~/work
claude --version    # ← should NOT print "ANTHROPIC_ENTERPRISE_KEY not set"
                    #   if it does, the wrapper isn't loaded — exec zsh

cd ~  # personal context
claude --version    # → uses macOS Keychain (Pro sub), no env override
```

### 2d. Troubleshooting

| Symptom | Fix |
|---|---|
| `claude: ANTHROPIC_ENTERPRISE_KEY not set` despite step 2b | `walter_secrets_load --force` — your session was loaded BEFORE you pushed the key. Force re-fetch. |
| Anthropic API returns 401 from `~/work/*` | The key was revoked or not actually saved. Re-do 2a-2b. |
| `which claude` shows binary, not function | Shell hasn't been reloaded since `15-walter-os.zsh` landed. `exec zsh`. |
| Calls in `~/work` are billing personal Pro | Wrapper not active. Run `walter_active_profile` from `~/work` — should print `work`. If `personal`, fix `WALTER_WORK_PATH` env. |

---

## Step 3 — Codex enterprise login (3 min) 🤖

**Goal**: same idea as step 2 but for Codex CLI. Codex stores OAuth
in `~/.codex/auth.json` so it CAN be redirected per-cwd via
`CODEX_HOME`.

### 3a. Verify profile dirs exist

```bash
walter-os profile-bootstrap status
# Expected:
#   claude       auth=Keychain (global)   skills=59
#   claude-work  auth=Keychain (global)   skills=59  (note: Keychain is global; that's fine for Codex)
#   codex        auth=yes (file)          skills=61  (your personal login)
#   codex-work   auth=no                  skills=61  (← what we're about to set up)
```

If `codex-work` directory doesn't exist:
```bash
walter-os profile-bootstrap init all
```

### 3b. First-run from `~/work/*` (~2 min)

```bash
cd ~/work
codex
# OpenAI's first-run flow opens. LOGIN with the enterprise account.
# Quit with Ctrl-D once you see the prompt.

# Verify:
ls ~/.codex-work/auth.json   # → should exist now
walter-os profile-bootstrap status
# Expected: codex-work  auth=yes (file)
```

### 3c. Test

```bash
cd ~/work && codex --version   # uses ~/.codex-work
cd ~ && codex --version          # uses ~/.codex (personal)
```

### 3d. Troubleshooting

| Symptom | Fix |
|---|---|
| First-run flow keeps opening even after login | The login token didn't write to `~/.codex-work`. Check `CODEX_HOME` is set: `cd ~/work && env \| grep CODEX_HOME` should print `~/.codex-work`. If empty, wrappers aren't loaded — `exec zsh`. |
| Login succeeds but auth says wrong account | You logged into the personal account by mistake. `rm ~/.codex-work/auth.json && cd ~/work && codex` to retry. |

---

## Step 4 — Tailscale via Headscale (5 min) 🔗

**Goal**: this Mac joins the Walter mesh so it can reach walter-vm
services via private hostnames (no CF Access middleman).

Headscale is optional mesh networking, not the primary break-glass path. If
registration returns HTTP 500 or Headscale logs `capability version must be
set`, stop and use the Hetzner Cloud Firewall SSH allow-list recovery path
instead of downgrading clients during an outage. Then read
[`../../setup/walter-host/services/headscale/RUNBOOK.md`](../../setup/walter-host/services/headscale/RUNBOOK.md)
before retrying Headscale.

### 4a. Generate a fresh preauth key on the VM

```bash
ssh walter-vm 'sudo docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 24h'
# Copy the key string. It's reusable for 24h, then expires.
```

If you want a non-reusable key (one-shot, more secure):
```bash
ssh walter-vm 'sudo docker exec headscale headscale preauthkeys create --user 1 --expiration 1h'
```

### 4b. Run `tailscale up` on the Mac

```bash
sudo /Applications/Tailscale.app/Contents/MacOS/Tailscale up \
  --auth-key=<the-key-from-4a> \
  --login-server=https://headscale.${WALTER_DOMAIN} \
  --accept-routes \
  --reset
```

The `--reset` is important if you've connected to other tailnets
before (it clears prior state).

### 4c. Verify

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
# Expected: shows the Mac + walter-vm as nodes in the mesh.
# Each node shows its 100.64.0.0/10 IP.
```

```bash
ssh walter-vm 'sudo docker exec headscale headscale nodes list'
# Expected: 2+ nodes (walter-vm itself + this Mac).
```

### 4d. Test private connectivity

```bash
# Now you can ssh to walter-vm via its tailnet IP (no CF Access):
ssh walter@100.64.0.X

# Or by hostname if MagicDNS is enabled (per headscale config.yaml):
ssh walter@walter-vm.walter.local
```

### 4e. Troubleshooting

| Symptom | Fix |
|---|---|
| `tailscale up` errors "auth key invalid" | Key expired or already used (if non-reusable). Generate a new one. |
| `tailscale up` returns HTTP 500 and Headscale logs `capability version must be set` | Tailscale client capability-version drift. Use the Hetzner Cloud Firewall SSH allow-list for break-glass, then follow the Headscale runbook before changing server or client versions. |
| Headscale logs: "Listening without TLS but ServerURL does not start with http://" | Ignore. Cosmetic warning. |
| `tailscale status` shows "logged out" | Did `--reset` succeed? Try `tailscale logout && tailscale up ...` again. |
| Mac is in the mesh but can't reach 100.64.0.X | DERP issue. Check `tailscale netcheck`. Walter-vm is using Tailscale's public DERP servers (configured in `headscale config.yaml` lines 14-17). |

---

## Step 5 — First wiki `/ingest` (10 min, optional) 📚

**Goal**: bootstrap the Karpathy-style LLM wiki with one source so
the compounding loop starts.

### 5a. Create the private wiki Forgejo repo (~2 min)

1. `https://git.${WALTER_DOMAIN}` (CF Access auth).
2. **+** → **New Repository**.
3. Name: `walter-wiki`. Owner: your operator user. **Private**: ✅.
4. Don't initialize with README (we'll push from local).
5. Create.

### 5b. Wire the local wiki dir to the private remote (~1 min)

```bash
cd ~/Projects/walter-os
git remote add wiki-private git@git.${WALTER_DOMAIN}:operator/walter-wiki.git
# (substitute your actual Forgejo username for `operator`)

# First push of the structure (SCHEMA.md is already in main):
walter-os wiki status   # confirm wiki/ exists locally
```

### 5c. First ingest (~5 min)

In Claude Code, in any directory under walter-os:

```
/ingest https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
```

The agent (using `wiki-ingest` skill) will:

1. WebFetch the gist.
2. Draft `wiki/sources/2026-05-DD-karpathy-llm-wiki-gist.md`.
3. Identify entities to stub: `people/andrej-karpathy.md`,
   `concepts/llm-wiki-pattern.md`, `topics/agentic-llm-coding.md`,
   `decisions/2026-05-05-walter-os-wiki-compliance.md`.
4. Show you all proposed pages + the diff for each.
5. After your approval, write to disk + run
   `walter-os wiki commit "ingest: karpathy-llm-wiki-gist"`.

### 5d. Verify

```bash
walter-os wiki status         # → "sources: 1 page, concepts: 1 page, ..."
walter-os wiki lint           # → expect 0 critical, maybe orphans (new pages!)
walter-os wiki lint --apply   # rebuild index.md from disk
```

### 5e. Troubleshooting

| Symptom | Fix |
|---|---|
| `/ingest` not recognized | Walter-OS commands need to be installed in `~/.claude/commands/`. Run `./install.sh --upgrade`. |
| Agent doesn't propose any pages, just gives a summary | The `wiki-ingest` skill didn't trigger. Re-prompt: "Apply the wiki-ingest skill. Source: <url>." |
| `git push wiki-private` fails authentication | SSH key not added to Forgejo. `https://git.${WALTER_DOMAIN}` → Settings → SSH Keys → add your `~/.ssh/id_ed25519.pub`. |

---

## Step 6 — Restic → B2 offsite backup (30 min) 💾

**Goal**: nightly encrypted backup of `/mnt/walter-vm-data/` (Plane
DBs, Forgejo data, Syncthing folders, ALL the operator data) to
Backblaze B2.

### 6a. B2 account + bucket (~5 min)

1. [Backblaze](https://www.backblaze.com) → Sign up (or log in if you have one).
2. **B2 Cloud Storage** → **Buckets** → **Create Bucket**.
3. Name: `walter-vm-backups` (must be globally unique — append `-yourname` if taken).
4. **Files**: Private. **Encryption**: SSE-B2 (default).
5. Create.

### 6b. Application keys (~2 min)

1. **App Keys** → **Add a New Application Key**.
2. Key name: `walter-vm-restic`.
3. Allowed bucket: `walter-vm-backups` (single bucket).
4. Permissions: read + write.
5. Create. Copy `keyID` + `applicationKey` (shown ONCE).

### 6c. Generate restic passphrase (~1 min)

> ⚠️ **Loss of this passphrase = total backup loss**. No recovery.

```bash
openssl rand -base64 32   # copy the output
```

Push to Infisical immediately:

```bash
infisical secrets set RESTIC_PASSWORD='<the-passphrase>' \
  B2_ACCOUNT_ID='<keyID>' \
  B2_APPLICATION_KEY='<applicationKey>' \
  B2_BUCKET_NAME='walter-vm-backups' \
  --domain=https://secrets.${WALTER_DOMAIN} \
  --projectId=8b4d37fa-8a03-4176-9787-69cf4f171324 \
  --env=dev
```

### 6d. Configure rclone on the VM (~5 min, INTERACTIVE)

```bash
ssh walter-vm
sudo -u walter rclone config
```

In the rclone interactive flow:
- `n` → new remote
- name: `b2-walter`
- Storage type: `b2` (Backblaze B2)
- Account ID: paste the keyID
- Application Key: paste the applicationKey
- Endpoint: blank (default)
- Test → quit

### 6e. Initialize restic repo (~2 min)

```bash
ssh walter-vm
# Pull secrets to env on VM (hand-off through Infisical or env file):
export RESTIC_PASSWORD='...' B2_ACCOUNT_ID='...' B2_APPLICATION_KEY='...'

# Initialize the encrypted repo
restic -r b2:walter-vm-backups:/restic-walter-vm init
# → "created restic repository abc123 at b2:..."
```

### 6f. Enable nightly backup (~5 min)

The `restic-backup.sh` script is already in
`/opt/walter-vm/services/restic/`. Wire it to cron:

```bash
ssh walter-vm
sudo crontab -e
# Add:
0 3 * * * /opt/walter-vm/services/restic/restic-backup.sh > /var/log/restic-backup.log 2>&1
```

### 6g. Test restore (~10 min — the part most people skip)

```bash
ssh walter-vm
restic -r b2:walter-vm-backups:/restic-walter-vm snapshots
# → list of snapshots

# Restore one file to /tmp:
restic -r b2:walter-vm-backups:/restic-walter-vm restore latest \
  --target /tmp/restic-test --include /mnt/walter-vm-data/sync/personal
# → file should be at /tmp/restic-test/mnt/walter-vm-data/sync/personal/...
```

If this works, your backup chain is real. If it doesn't, you don't have backups yet.

### 6h. Document the recovery procedure

Write a `docs/operational/dr-restore.md` with the operator-eyes-only
restore steps. Quarterly drill: pick a random snapshot, restore to a
sandbox VM, confirm data integrity. The `quarterly-upgrade-cadence`
skill has this on the checklist.

### 6i. Troubleshooting

| Symptom | Fix |
|---|---|
| `rclone config` fails to connect to B2 | Wrong keyID/applicationKey, OR your B2 account lacks billing setup (B2 requires a card on file even for free tier). |
| `restic init` errors "wrong password" | The passphrase you exported is different from what restic expects (mismatch between your shell and the saved value). Re-export from Infisical. |
| Cron not running | `sudo systemctl status cron` (Debian); check `/var/log/cron.log`. |

---

## Step 7 — Grafana community dashboards (5 min, optional) 📊

**Goal**: actually see the metrics Prometheus is collecting. Today
you have alerts but no graphs.

### 7a. Open Grafana

`https://grafana.${WALTER_DOMAIN}` → Google login via CF Access → enter
admin password (set during Grafana first-run; in Infisical as
`GRAFANA_ADMIN_PASS` if you saved it there).

### 7b. Import dashboards by ID (~1 min each)

Sidebar → **Dashboards** → **+ New** → **Import**.

Paste each ID below, click **Load**, select the right datasource on
the next screen, click **Import**.

| ID | Name | Datasource |
|---|---|---|
| `1860` | Node Exporter Full | Prometheus |
| `14282` | Cadvisor exporter | Prometheus |
| `179` | Docker Engine | Prometheus |
| `13639` | Logs / App via Loki | Loki |

### 7c. Verify

After import, the dashboards should populate immediately (Prometheus
has been collecting since deploy). If a panel says "No data":
- The metric name in the dashboard JSON might not match your Prom
  exporter's name. Check the panel's query, edit if needed.
- Or the datasource isn't selected correctly — edit dashboard
  variables.

### 7d. (Optional) Save your customized dashboards

Once you tweak a dashboard, **Share** → **Export** → **Save to file**
and commit it to `setup/walter-host/services/observability/grafana/provisioning/dashboards/`
so the next operator (or `--upgrade`) gets them automatically.

---

## Step 8 — RocketChat / n8n / Penpot first-runs (when you need them) 🎛️

These are pure operator first-run wizards. Skip until you actually
plan to use the service.

### 8a. RocketChat

```
https://chat.${WALTER_DOMAIN} → CF Access auth → first-run admin form:
  - Workspace name: anything
  - Admin email: your admin email (${WALTER_ADMIN_EMAIL})
  - Password: strong; save in Bitwarden as 'rocketchat-admin'
```

### 8b. n8n

```
https://n8n.${WALTER_DOMAIN} → CF Access auth → set owner email + password
  (save in Bitwarden as 'n8n-admin')
```

After login, import workflows from JSON exports:
- Sidebar → **Workflows** → **Import from File** → pick the JSON.
- Operator-built or community ones ([n8n workflows](https://n8n.io/workflows)).

### 8c. Penpot

```
https://penpot.${WALTER_DOMAIN} → CF Access auth → register the FIRST
account (operator). After that, registration is operator-controlled.
```

For first design files, use **Templates** in the dashboard.

---

## What to do AFTER all 8 steps

Sanity check across the stack:

```bash
walter-os doctor              # local Mac (24/25 ok expected)
walter-os status              # audit + spend
walter-os audit               # daily supply-chain scan
walter_secrets_status         # session active 12h
walter-os wiki status         # page counts
walter-os profile-bootstrap status   # profile auth state
ssh walter-vm 'sudo docker ps --filter health=unhealthy --format "{{.Names}}"'
                              # should be empty
```

If any of those flag a regression, ask the agent to triage.

---

## Maintenance cadence (after this sets up)

| Cadence | Action |
|---|---|
| Every shell start (12h) | Credential-store prompt for `walter_secrets_load` (transparent) |
| Every session start | Daily supply-chain audit (gated by hook) |
| Every PR | Branch-flow guard, pre-commit tests, CI shellcheck/bats |
| Weekly | Run `walter-os wiki lint` to catch orphans |
| Monthly | Review Grafana alerts, review B2 spend, check Infisical access logs |
| Quarterly | DR drill (restore a snapshot), review optional hardware-key enrollment, refresh Machine Identity, rotate any keys nearing expiry |
| When you onboard a new device | Repeat steps 1, 3, 4 for that device. Per-device Machine Identity. |

---

## Reference

- `docs/operational/onboarding-checklist.md` — what's pending, at-a-glance
- `docs/specs/secrets-runtime-architecture.md` — the why behind step 1
- `docs/specs/karpathy-llm-wiki-compliance.md` — the why behind step 5
- `skills/secrets-yubikey-unlock/SKILL.md` — legacy-named guide for OS credential-store secrets bootstrap
- `wiki/SCHEMA.md` — what wiki pages look like

Questions / issues: ask the agent ("the runbook step X is failing
with Y"). It has full context on the architecture and can triage
faster than re-deriving from these docs alone.
