# Walter-OS — operator onboarding checklist

> **Purpose**: track what's deployed-but-empty vs configured-and-working
> across the stack. Updated 2026-05-05 after a full audit.
>
> Anything marked 📋 is **operator-only** — agent can prep but can't
> finish without you. Anything marked 🤖 is agent-fixable; if you see
> one, ask the agent to do it.

---

## Walter-VM service health (snapshot 2026-05-05)

| Service | Container | Healthy | Configured | Notes |
|---|---|---|---|---|
| Forgejo | ✅ | ✅ | 📋 first-repo-pending | Up; no repos yet — operator creates via web UI |
| Plane | ✅ | ✅ | 📋 no projects | API works; create first project via UI |
| Infisical | ✅ | ✅ | ✅ | 53 secrets stored; Machine Identity for runtime flow pending operator |
| LiteLLM | ✅ | ✅ | ✅ | 5 models routed (cheap/haiku/sonnet/opus/gpt) |
| Synapse + Element | ✅ | ✅ | 📋 user `<your-username>` exists, no rooms | Operator creates first room via Element UI |
| RocketChat | ✅ | ✅ | 📋 no team set up | Operator-driven first-run wizard |
| Penpot | ✅ | ✅ | 📋 no workspaces | Operator-driven |
| Drawio | ✅ | ✅ | ✅ | Stateless; just works |
| Grafana | ✅ | ✅ | ⚠️ alerts ✅, dashboards empty | 5 alerts provisioned. Community dashboards (cAdvisor, node-exporter, docker) can be imported — see below |
| Uptime-Kuma | ✅ | ✅ | ✅ | 14 monitors live |
| Headscale | ✅ | ✅ | 📋 0 nodes paired | Operator runs `tailscale up --auth-key=... --login-server=...` per device |
| Headscale UI | ✅ | ✅ | ✅ | hs.${WALTER_DOMAIN} |
| Wireguard | ✅ | ✅ | 📋 0 peers | Operator adds peers via wg-easy UI |
| Syncthing | ✅ | ✅ | ✅ | 9 folders registered, 1 device paired (<your-device>) |
| Homepage | ✅ | ✅ | ✅ | Dashboard live |
| n8n | ✅ | ✅ | 📋 0 workflows | Operator builds workflows or imports JSON exports |
| OpenClaw | ✅ | ✅ | ✅ | **Fixed 2026-05-05**: model `litellm/sonnet`, baseUrl `http://litellm:4000` |
| LLM proxies (CCR) | ✅ | ✅ | 📋 `Providers: []` | See "CCR question mark" section |
| Cloudflared | ✅ | ✅ | ✅ | 18 tunnel routes, 17 with CF Access |

**TL;DR**: every container is up. Most "configured" gaps are
operator-only first-runs (create repo, create project, add device).

---

## CCR question mark

`claude-code-router` (musistudio/claude-code-router) sits at
`http://claude-code-router:3456` on `litellm_net` with
`Providers: []`. Two possible designs:

**Design A — Mac-local CCR**: operator runs CCR on the laptop, where
it has access to the local `claude` binary (which holds Pro OAuth
in macOS Keychain). CCR proxies API requests to that local `claude`,
effectively renting the operator's Pro session for non-Anthropic tools
(e.g. LiteLLM as a fallback). The walter-vm CCR is unused.

**Design B — VM CCR with API keys**: operator pastes Anthropic API
keys into the CCR config; CCR becomes a redundant LiteLLM. Provides
no value over LiteLLM directly.

**Recommendation**: stop deploying CCR on walter-vm. Move to a
separately-tracked Mac-side install. **Action 📋**: operator decides
to either (i) remove the walter-vm CCR container, or (ii) populate
Providers with API keys (Design B). Tracked at
[issue/decision: TBD].

---

## Operator action items (in order)

### 1. Secrets runtime (5 min)

```bash
# Mac, one-time
walter-os secrets-keychain-init
# → enter Infisical Machine Identity creds, Yubikey touched once
walter_secrets_load
walter_secrets_status   # session valid 12h
```

After this works for a week:
```bash
srm -z ~/.config/walter-os/secrets.env
```

### 2. ANTHROPIC_ENTERPRISE_KEY for work/ context (3 min)

In Infisical web UI → walter-os → dev:
```
ANTHROPIC_ENTERPRISE_KEY = sk-ant-... (from [Company]'s enterprise account)
```

Then:
```bash
walter_secrets_load --force
cd ~/work && claude   # uses enterprise key
```

### 3. Codex enterprise login (3 min)

```bash
walter-os profile-bootstrap init all
cd ~/work && codex
# → prompts for enterprise login → cached in ~/.codex-work/auth.json
```

### 4. Tailscale via Headscale (5 min)

```bash
# Generate fresh preauth key on the VM:
ssh walter-vm 'sudo docker exec headscale headscale preauthkeys create --user 1 --reusable'

# On Mac:
sudo /Applications/Tailscale.app/Contents/MacOS/Tailscale up \
  --auth-key=<key-from-above> \
  --login-server=https://headscale.${WALTER_DOMAIN} \
  --accept-routes \
  --reset
```

### 5. First wiki ingest (~10 min, optional but recommended)

```bash
# Create the private wiki repo first in Forgejo
# https://git.${WALTER_DOMAIN} → New Repository → name "walter-wiki", private
git remote add wiki-private git@git.${WALTER_DOMAIN}:operator/walter-wiki.git

# Then in Claude Code:
/ingest https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
# → agent proposes pages, you approve, agent writes + commits
```

### 6. Restic → B2 (~30 min, deferred until you actually want offsite backup)

See `setup/walter-host/services/restic/README.md` and `RCLONE-SETUP.md`. The
script is written; the gating step is interactive `rclone config`
on the VM (paste-token OAuth flow for Google Drive OR alternatively
B2 keys). Operator-driven.

After setup, daily backup runs at 03:00 via cron. Recovery test:
quarterly drill (per `quarterly-upgrade-cadence` skill).

### 7. (Optional) Import Grafana community dashboards (~5 min)

Useful dashboards for our stack:

| Source | ID | Why |
|---|---|---|
| [cAdvisor — exporter](https://grafana.com/grafana/dashboards/14282) | 14282 | All container stats (CPU/mem/network) |
| [Node Exporter Full](https://grafana.com/grafana/dashboards/1860) | 1860 | Host-level (CPU/disk/RAM/io) |
| [Docker Engine](https://grafana.com/grafana/dashboards/179) | 179 | Docker-specific |
| [Loki Logs/Metrics](https://grafana.com/grafana/dashboards/13639) | 13639 | Log volume + query stats |

Import via grafana.${WALTER_DOMAIN} → + → Import → paste ID → select
Prometheus / Loki datasource → Save.

### 8. (Optional) RocketChat / n8n / Penpot first-run

Each has a web-driven onboarding wizard. Open the URL, follow the
flow, set admin password, done. Deferred until you actually need
each one.

---

## What the agent CANNOT fix (and why)

- **Headscale node enrollment**: requires `tailscale up` on the
  client device. Agent doesn't have shell access to your Mac's
  Tailscale daemon.
- **Plane / Forgejo / RocketChat / n8n / Penpot first-runs**: each
  has a wizard that requires the operator's password decision.
  Bootstrapping these via API would mean the agent picks the
  password, which is wrong.
- **Restic offsite passphrase**: by design, the passphrase loss = total
  backup loss. The operator must own the passphrase generation +
  storage decision.
- **Wiki content**: per Karpathy's design — the LLM never autonomously
  populates the wiki. Operator triggers each `/ingest`.
- **CCR design choice**: the operator decides Design A vs B (see above).

---

## Health check (run anytime)

```bash
walter-os doctor              # local Mac state (24/25 ok expected)
walter-os status              # audit + spend status
walter-os audit               # daily supply-chain scan on demand
ssh walter-vm 'sudo docker ps --filter health=unhealthy --format "{{.Names}}"'
                              # should return empty
walter-os wiki status         # wiki state
walter_secrets_status         # secrets session state (in shell)
```

If any of these flag something unexpected, ask the agent to triage
("walter-vm has X unhealthy containers, please investigate").

---

## Tracking

This document is the source-of-truth for "what's left". Update on
every config change. Pair with `docs/specs/` for the architecture
contracts.
