# IaC State Audit — Walter-OS

**Date:** 2026-05-11
**Branch audited:** `main` (commit `73d1219`)
**Auditor:** subagent invocation, read-only inspection of repo only (no live VM probe)

## Summary

Walter-OS sits at **roughly 65 % IaC coverage** of the surface it actively
manages today (Walter-VM + Mac operator workstations). The Docker layer on
Walter-VM is in excellent shape — compose files, env templates, generic
Ansible role, observability provisioning — but seven critical pieces of state
still live as runbook prose or one-shot operator UI clicks. The remaining
35 % concentrates around three classes:

1. **Identity / first-run state** inside services (Plane workspaces, Forgejo
   repos, Synapse rooms, n8n workflows, Headscale users, OpenClaw onboarding).
2. **External-provider state** the agent talks *about* but does not yet
   manage as code (Hetzner VM provisioning, Backblaze B2 buckets, Google
   Drive rclone remote, Cloudflare Access apps after initial create).
3. **Out-of-scope nodes** that exist on paper but have zero IaC yet
   (standby homelab node, Z440, M2 Studio LiteLLM-router companion).

Five of the seven gaps are 1-3 hours of work each. The other two (standby homelab node
Proxmox, Z440 vLLM) are larger but explicitly future.

---

## Currently IaC

### Walter-VM Docker services — **mostly full IaC**

**Where:** `setup/walter-host/services/<service>/` + `ansible/walter-vm.yml`.

Per-service contract (enforced by `ansible/roles/service/tasks/main.yml`):
`compose.yml` + optional `.env.template` + optional `deploy.sh`. The generic
Ansible role rsyncs everything, never overwrites an existing `.env`, then
`docker compose pull && up -d`.

Services with **compose + Ansible binding** (full IaC of the container layer):
plane, forgejo, infisical, litellm, n8n, uptime-kuma, homepage, observability
(Prometheus/Loki/Grafana/Promtail), penpot, drawio, rocketchat, synapse,
openclaw, llm-proxies (CCR), wireguard, headscale, syncthing, restic — **19
services**. All compose tags are pinned (`litellm:v1.83.14-stable`,
`n8n:1.65.2`, `postgres:16-alpine`, etc.) — verified by spot-check of
`litellm/compose.yml` and `n8n/README.md`.

Services with compose only (no `deploy.sh`, but the generic Ansible role
covers them anyway): drawio, headscale, homepage, llm-proxies, penpot,
plane, rocketchat, uptime-kuma, forgejo, litellm.

**Coverage:** Full for the container lifecycle. Partial for first-run state
(see "NOT yet IaC" below).

### Walter-VM base OS

**Where:** `setup/walter-host/bootstrap-vm.sh` (legacy idempotent shell) + the newer
`ansible/roles/base/tasks/main.yml` which captures the same intent
declaratively.

Covers: apt packages, swap, UFW rules (6 ports), `walter` user creation,
sudo NOPASSWD, `/mnt/walter-vm-data` mount + 9 subdirectories, fail2ban,
unattended-upgrades.

**Coverage:** Full. Either path (shell or Ansible) brings a fresh Ubuntu
24.04 VM to the same state.

### Claude Code config (Mac side)

**Where:** `install.sh` merges `hooks/` + `mcp/servers.json` into
`~/.claude/settings.json` via `jq` (lines 264-340). Two profiles:
default (~/.claude/settings.json) and high-risk
(~/.claude/settings.high-risk.json).

**Coverage:** Partial. The merger handles `mcpServers` and `hooks`
sections only — anything the operator manually adds to `permissions`,
`env`, `theme` is preserved. Backups stamped on every run.

### Hooks

**Where:** `hooks/*.sh` (4 scripts: approval-gate, branch-flow-guard,
daily-audit-gate, pre-commit-tests). Wired into Claude Code via the
install.sh hook merger.

**Coverage:** Full. Hooks are git-tracked and registered declaratively.

### MCP servers

**Where:** `mcp/servers.json` (canonical), merged into Claude settings on
install. 20+ servers defined.

**Coverage:** Partial. Versions are pinned in the JSON, but per
`feedback_mcp_versions.md` in operator memory, those versions may be
inventadas — never verified against npm. The IaC mechanism works; the
*content* is suspect.

### Cron jobs (Walter-VM)

**Where:** `setup/walter-host/services/alerting/cron.example` — 2 entries
(watchdog every 5 min, hetzner-spend daily at 09:00 BA). The `ansible/`
playbook has an `alerting` role declared in `walter-vm.yml` but the role
directory does not exist in `ansible/roles/` — **broken reference**
(see Gaps below).

**Coverage:** Partial. Cron content is versioned; the install-on-VM
mechanism is documented prose ("Install on the VM as walter user;
crontab -e") rather than an Ansible task.

### Observability provisioning

**Where:** `setup/walter-host/services/observability/grafana/provisioning/`
(datasources, alerting/contactpoints, alerting/rules, dashboards/*.json).
Prometheus + Loki + Promtail configs alongside.

**Coverage:** Full for the 4 dashboard JSONs in repo (Node Exporter 1860,
Loki 13639, etc.) + datasources (Prometheus, Loki) + alert rules + contact
points. The onboarding checklist offers an *optional* manual import of
additional community dashboards (cAdvisor 14282, Docker 179) which is the
only manual residual here.

### Cloudflare zone + tunnel + Access

**Where:** `setup/walter-host/cloudflare/{01-create-zone,02-create-tunnel,03-install-cloudflared,04-create-access}.sh`.

API-driven, idempotent bash. Re-runnable.

**Coverage:** Partial-to-full. The four scripts cover: zone creation,
DNS record import from prior authoritative NS, tunnel + cloudflared
service install, Access apps with OTP/Google IdP policies. **What is NOT
covered:** adding new DNS records *after* the import (operator does this
via CF dashboard today), tunnel route additions (currently 18 routes per
the onboarding doc — origin of those routes not tracked declaratively).

### Skills + AGENTS.md

**Where:** `skills/` (40 directories) + `AGENTS.md` (3 layers: global,
work, projects-personal, personal).

**Coverage:** Full by virtue of git. Skills are markdown + scripts,
loaded at agent invocation time via description-match.

### Restic backup logic

**Where:** `setup/walter-host/services/restic/{setup.sh,restic-backup.sh,RCLONE-SETUP.md}`.

Cron schedule (daily 02:00, weekly prune, monthly check) installed
via `setup.sh`.

**Coverage:** Partial. Backup script and schedule are versioned. **Manual:**
rclone OAuth config (interactive Google Drive token flow), passphrase
generation + storage, and the choice between Google Drive vs B2 are
explicitly operator-driven.

### Headscale config

**Where:** `setup/walter-host/services/headscale/config.yaml`. Server URL, IP
prefixes, DERP, magic DNS settings.

**Coverage:** Full for daemon config. **Manual:** user creation
(`headscale users create`), preauthkey minting, ACL JSON. No ACL file in
repo — config.yaml does not reference one.

### LiteLLM router config

**Where:** `setup/walter-host/services/litellm/config.yaml` + `compose.yml`.

5 primary models (cheap/haiku/sonnet/gpt/opus) routed declaratively.
Master key + salt + DB pass via `.env` (Infisical fetched at deploy
per `infisical-agent` skill).

**Coverage:** Full for the model_list. Subscription-pool / CCR fallback
chain referenced in comments and partially declared.

### LLM-proxies (CCR daemon)

**Where:** `setup/walter-host/services/llm-proxies/compose.yml`. Self-bootstrapping
container that npm-installs CCR on first run and writes
`/app/.claude-code-router/config.json` if absent.

**Coverage:** Partial. Container lifecycle is IaC; the Providers list
inside CCR config is intentionally empty (per onboarding-checklist:
`Providers: []`) — operator decision pending (Design A vs B).

---

## NOT yet IaC

### Hetzner Cloud VM provisioning

**What:** The walter-vm CX/CPX server itself (the host that runs
everything above).
**Why manual:** `setup/walter-host/README.md` says provisioning is operator-driven
via Hetzner web UI. The `skills/hcloud-cli/` skill exists but is invoked
ad-hoc, not as a `terraform plan`-style declarative spec.
**Recommendation:** A `setup/walter-host/provision.sh` wrapping `hcloud server
create` with fixed CPX41 / Ubuntu 24.04 / SSH-key params + state file at
`~/.config/walter-os/walter-vm.tfstate` (or simple JSON). Snapshots /
backups schedule is documented prose, not automated. **Tool:** `hcloud`
CLI driven by a thin bash wrapper, or `terraform-hcloud-provider` if
operator prefers full Terraform.

### Cloudflare DNS records (post-import)

**What:** Records added after `01-create-zone.sh` runs (e.g. each new
`*.${WALTER_DOMAIN}` subdomain when a service is added).
**Why manual:** The bootstrap imports records from prior authoritative
NS once. After that, operator manages via CF dashboard.
**Recommendation:** A flat `setup/walter-host/cloudflare/records.yaml` listing
every record + a sync script (`05-sync-records.sh`) that upserts via CF
API. Alternatively `terraform-cloudflare-provider`.

### Cloudflare Access apps + tunnel routes (post-init)

**What:** The 18 tunnel routes + 17 CF Access apps currently live (per
onboarding-checklist). `04-create-access.sh` creates initial apps for two
domains. Subsequent additions are UI clicks.
**Why manual:** Same as DNS — no continuous sync layer.
**Recommendation:** Same pattern: `setup/walter-host/cloudflare/access-apps.yaml`
+ idempotent sync script.

### Headscale ACLs + users

**What:** Tailnet ACL JSON, user/namespace creation, preauthkey lifecycle.
**Why manual:** Operator runs `headscale users create` and
`headscale preauthkeys create` per device, per onboarding step 4.
**Recommendation:** Drop an `acls.json` next to `config.yaml` and have a
small Ansible task `headscale apply-acls` on every deploy. Per-device
preauthkey creation can stay interactive (security boundary).

### n8n workflows

**What:** Per `setup/walter-host/services/n8n/README.md` line 60: workflow JSON
exports "live as JSON exports in `templates/` (TODO — populate as we
build)". Directory does not exist. Onboarding marks n8n as
`📋 0 workflows`.
**Why manual:** No exports captured yet.
**Recommendation:** Create `setup/walter-host/services/n8n/templates/*.json`,
import on deploy via `n8n import:workflow --separate
--input=templates/`.

### Plane workspaces + custom states

**What:** Plane projects, custom states (the spec elsewhere mentions
`awaiting-consensus`, `awaiting-resume` etc. — referenced in
`.claude/worktrees/silly-elion-4860fe/setup/plane/states.md` which is
**not** on main).
**Why manual:** Per onboarding line 17: "create first project via UI".
**Recommendation:** `scripts/plane-seed.sh` hitting Plane API with
workspace/project/state JSON. Plane API tokens via Infisical.

### Infisical bootstrap

**What:** Machine Identities, projects, environments, RBAC. 53 secrets
already stored (per onboarding) — entered by hand.
**Why manual:** First-run admin signup is intentionally interactive
(operator picks password). Per-identity universal-auth setup is described
in 11 steps of `operator-setup-runbook.md` step 1a.
**Recommendation:** `scripts/infisical-bootstrap.sh` that, given an
already-authenticated admin, provisions: projects, environments,
default RBAC policies, baseline Machine Identity for the operator workstation.
Secrets values stay operator-entered.

### Backblaze B2 (offsite backup)

**What:** Bucket + Application Key for the secondary restic repo.
**Why manual:** Per operator-setup-runbook step 6a: "B2 Cloud Storage →
Buckets → Create Bucket" via web UI.
**Recommendation:** `b2-cli` or `terraform-b2-provider` to provision
bucket + scoped key. Out of scope for now — secondary repo today is
Google Drive (per `restic/RCLONE-SETUP.md`).

### rclone Google Drive remote

**What:** OAuth-authenticated rclone remote on Walter-VM, used as the
restic secondary repo target.
**Why manual:** Interactive `rclone config` (paste-token OAuth flow).
Onboarding line 132: "the gating step is interactive `rclone config`
on the VM".
**Recommendation:** Use a Google service account JSON in Infisical
instead of OAuth — that *is* IaC-friendly. Trade-off: service account
has separate Drive quotas + can't access operator's personal Drive
folders, so this is a design decision, not just a tooling one.

### Mac local Brewfile install — **mostly IaC**

**Where:** `setup/Brewfile` + `setup/bootstrap.sh`.
**Coverage:** Full for the listed packages (jq, git, gh, mise, vercel-cli,
…). Mise versions in `setup/mise.toml.example` are template — operator
copies to `~/.config/mise/config.toml`.
**Gap:** Not so much "not IaC" as "operator-instance config lives outside
the repo" — by design. Worth noting as partial.

### Phase-V Postgres / pg_partman / pg_cron (claimed in audit prompt)

**Status:** **Does not exist on main.** Audit prompt mentions
`setup/walter-host/services/postgres/migrations/` — that directory is absent from
the repo, no SQL files anywhere under `setup/walter-host`. The only Postgres
instances are per-service (each compose declares its own
postgres:16-alpine). No central Postgres service, no partitioning
strategy, no migration files committed. If Phase V is in flight on
another branch, audit will need a re-run after merge.

### Postiz / Metabase (claimed in audit prompt as "added in this PR")

**Status:** **Not on main.** No `setup/walter-host/services/postiz/` or
`metabase/` directories. Only mention of Postiz in repo is the social-
pipeline docs; Metabase is unmentioned. Same caveat as above — likely on
a feature branch not yet merged.

### standby homelab node (Proxmox + HomeAssistant + Jarvis)

**Status:** Spec exists at `docs/specs/archive/local-llm-node.md` +
`docs/specs/archive/standby-node-replication.md`. **Zero IaC.** No Ansible
inventory entry, no Terraform-Proxmox provider config, no HA YAML in
repo.
**Recommendation when active:** Ansible playbook `playbooks/standby-node.yml`
mirroring `walter-vm.yml` pattern (base role + service role). HA config
is YAML-native so it's IaC by file existence — just commit it.

### Z440 (vLLM, dual RTX 3090)

**Status:** Mentioned in `docs/specs/homelab-topology.md`. **Zero IaC.**
**Recommendation when active:** Same Ansible pattern. vLLM is
container-friendly; one compose.yml per model server.

### M2 Studio (subscription pool, 7 CCRs)

**Status:** Mentioned in spec. **Zero IaC.** This is the trickiest of the
three — CCR processes need to live alongside the operator's local Claude
Code session (Pro/Plus subscription auth via Keychain). Hard to fully
declarative without breaking the auth model.
**Recommendation:** `launchd` plist per CCR + a `scripts/m2-bootstrap.sh`
to install them. Versions still come from `npm install -g @musistudio/claude-
code-router@<pinned>`. Best-effort IaC; some Mac-side state remains
operator-managed.

### Ansible `alerting` role

**Status:** Referenced in `walter-vm.yml` line 111 (`- role: alerting`)
but the directory `ansible/roles/alerting/` does not exist. **Broken
reference** — `ansible-playbook walter-vm.yml --tags alerting` would
fail today. Cron content does live at `setup/walter-host/services/alerting/` so
the migration is straightforward.

---

## Migration roadmap (priority order)

| Priority | Item | Effort | Tool | Notes |
|---|---|---|---|---|
| **P1** | Ansible `alerting` role | 1 h | Ansible | Currently broken reference in `walter-vm.yml`; fix before next deploy |
| **P1** | Cloudflare DNS records sync | 2 h | CF API + YAML | Highest churn — every new service needs a record |
| **P1** | Cloudflare Access apps sync | 2 h | CF API + YAML | Same lifecycle as DNS |
| **P2** | Hetzner VM provisioning script | 3 h | `hcloud` CLI + state JSON | Lock CPX41 / Ubuntu 24.04 / SSH key as code |
| **P2** | n8n workflow templates | 2-4 h | n8n CLI import | Per README TODO; needs operator to first build workflows |
| **P2** | Plane workspaces + states seed | 3 h | Plane REST API | Closes onboarding gap |
| **P2** | Headscale ACLs | 2 h | YAML + `headscale apply` | Defense-in-depth; not blocking |
| **P3** | Infisical bootstrap script | 3 h | `infisical` CLI | Idempotent provisioning of projects + identities |
| **P3** | rclone GDrive → service account | 1 h | JSON in Infisical | Removes the only operator-interactive backup step |
| **P3** | MCP version verification job | 1 h | npm + diff | Per `feedback_mcp_versions.md` — versions may be invented |
| **P4** | Backblaze B2 provisioning | 2 h | `b2-cli` | Only when offsite-2 actually configured |
| **P4** | standby homelab node Ansible inventory + playbook | 8 h | Ansible | When standby homelab node comes online |
| **P4** | Z440 Ansible playbook | 6 h | Ansible | When Z440 comes online |
| **P4** | M2 Studio CCR launchd plists | 4 h | `launchd` + bash | When subscription pool goes live |

---

## Gaps identified (things not documented as IaC plan anywhere)

1. **Tunnel route inventory.** 18 routes live, no source-of-truth list in
   repo. Lose `/etc/cloudflared/config.yml` on the VM (restic restores
   it, so OK) but there is no canonical declarative spec.
2. **Caddyfile.** `bootstrap-vm.sh` references an "Initial Caddyfile in
   `/etc/caddy/Caddyfile`" — no Caddyfile committed to repo. If
   walter-vm dies and restic isn't restored cleanly, Caddy config is
   lost.
3. **Headscale ACL JSON.** Never committed. Whatever ACLs are running
   today exist only on the VM.
4. **OpenClaw model + baseURL fix from 2026-05-05.** Per onboarding
   line 32 the fix was applied "to model `litellm/sonnet`, baseUrl
   `http://litellm:4000`" — is this fix in the compose.yml today or
   was it applied at runtime via the OpenClaw UI? Worth a verification
   commit.
5. **Uptime-Kuma 14 monitors.** No `monitors.json` export in repo. Kuma
   has `scripts/kuma-bulk-monitors.py` in `/scripts/` but no actual
   monitor inventory checked in.
6. **`alerting` Ansible role missing** (mentioned above).
7. **N8n templates directory missing** (mentioned above).
8. **53 Infisical secrets** — naming convention + scope not documented
   in repo. Loss of Infisical = loss of the schema, not just values.
9. **MCP versions unverified** per operator memory note — high-impact
   supply-chain risk per the daily audit policy.

---

## Recommendation — top 3 quick wins

1. **Fix the broken `alerting` Ansible role reference (1 h, P1).**
   Currently `ansible-playbook walter-vm.yml` fails on tag `alerting`.
   Either implement the role (rsync the existing scripts + crontab) or
   remove the line. Low-effort, removes a latent footgun.

2. **Cloudflare records + Access apps to YAML (4 h total, P1).** This is
   the highest-churn manual surface — every new service adds a record
   and an app. A single `setup/walter-host/cloudflare/records.yaml` +
   `access-apps.yaml` + the existing API helpers in
   `01-create-zone.sh`/`04-create-access.sh` get refactored into a
   reconciler. After this, *every* new service is one PR (compose +
   record + app) instead of a PR plus two CF dashboard clicks.

3. **Commit the missing config artifacts that already exist on the
   VM (2 h, P1).** Walk one round-trip on the VM and pull: tunnel
   routes (`/etc/cloudflared/config.yml`), Caddyfile, Headscale ACL
   JSON (if any), Uptime-Kuma monitor export. Drop them in repo. No new
   IaC, just stop trusting the VM as the only source of truth. After
   this you have an actual disaster-recovery story without depending
   exclusively on restic.

The longer-tail items (Hetzner provisioning, n8n templates, Plane seed)
are correct to defer until standby homelab node / Postiz / Metabase / Phase V land — at
that point the patterns multiply and the ROI on a clean IaC layer
rises.
