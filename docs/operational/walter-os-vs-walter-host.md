# Walter-OS vs Walter-Host: Client Framework vs Server Stack

**Last updated**: 2026-05-12
**Status**: Active
**Related**: `setup/walter-host/`, `docs/operational/hosting-providers-comparison.md`

---

## The two components

Walter-OS is one repository that ships two distinct things. Understanding which
part you need is the first decision every new operator makes.

| Component | What it is | Where it runs |
|---|---|---|
| **walter-os** | Client agent framework: skills, contexts, AGENTS.md cascade, the `walter` CLI, Walter Council agents | Operator's workstation (Mac or Linux) |
| **walter-host** | Self-hosted service stack: Plane, Forgejo, LiteLLM, Grafana, Caddy, Headscale, n8n, and 20+ other services | A dedicated server: VM, homelab, or same machine |

**You do not need walter-host to use walter-os.** The client framework runs
entirely on your workstation and can integrate with SaaS alternatives (GitHub
instead of Forgejo, Linear instead of Plane, Anthropic API directly instead of
LiteLLM).

---

## Adoption modes

There are four ways to use Walter-OS. These are adoption modes, not maturity
levels. Choose the smallest mode that gives you value.

| Mode | Setup | When to use | Recommended? |
|---|---|---|---|
| **Clone-only reference** | Clone the repo; do not run `install.sh` | Study the system, copy an `AGENTS.md` pattern, review skills/hooks/specs before installing, or use it as an operating playbook | **Yes** — for evaluation and lightweight reuse |
| **Client install** | Install walter-os on your workstation, no walter-host | Make Claude Code, Codex CLI, Cursor, and repo-level agents follow the same rules and workflows everywhere | **Yes** — default starting point |
| **Client + selected services** | Client install plus only the services you need, self-hosted or SaaS | Add Infisical, LiteLLM, Grafana, Syncthing, n8n, or other pieces without running the full stack | **Yes** — best incremental path |
| **Full walter-host** | Client install plus the complete server stack on a VM, homelab node, or local lab machine | Full private control plane for secrets, model routing, issue tracking, git hosting, dashboards, automation, backups, and Council operations | **Yes** — for operators who want full self-hosting |

### Trade-offs in detail

**Clone-only reference** is the zero-footprint mode. You can read the global
`AGENTS.md`, copy context templates, inspect hooks, browse skills, and adapt the
workflow to another repo without writing anything to `~/.claude`,
`~/.codex`, or `~/.config/walter-os`. This is the right mode when you are
auditing Walter-OS before trusting it or only want the operating model.

**Client install** is the right start for most operators. You install walter-os
(`./install.sh`), scaffold `~/.config/walter-os/overlay/`, set
`WALTER_GITHUB_ORG` and any provider-specific values, and have a working agent
framework in minutes. You keep using GitHub, Linear, and the Anthropic API
directly. No VM to maintain.

**Client + selected services** is the incremental path. Add Infisical when shell
secrets become hard to manage. Add LiteLLM when you want one model gateway,
semantic model aliases, and spend/audit visibility. Add Grafana or Control Tower
when you need human-visible agent telemetry. Add Syncthing when you want memory
and overlay material to follow you across trusted devices. Keep SaaS where it is
still the better trade-off.

**Full walter-host** is the complete private backend. It gives agents a private
issue tracker, git host, secrets vault, model gateway, dashboards, automations,
and backups. The cost is operational: DNS, tunnels, updates, backups,
monitoring, and incident response become your responsibility.

## Walter-host topologies

Once you choose to run walter-host, it can live in three places:

| Topology | Setup | When to use | Caveat |
|---|---|---|---|
| **Local lab** | walter-os and walter-host on the same laptop or desktop | Testing the full stack or working from a powerful single-user machine | Resource intensive; competes with IDE/browser/video calls |
| **Remote VM** | walter-os on workstation, walter-host on a dedicated cloud VM | Production use, multi-device access, simple always-on operations | Monthly cloud spend; reference path is Hetzner Ubuntu 24.04 |
| **Homelab node** | walter-host on local hardware such as Proxmox, bare metal, or a mini-PC | Privacy-first operation, no cloud spend, full data ownership | You own hardware reliability, power, backups, and remote access |

Remote VM is the recommended default for operators who want full self-hosting
without maintaining physical hardware. Homelab is best when data sovereignty is
worth the extra operational work. Local lab is useful for validation but is not
the preferred always-on setup.

---

## Which directories belong to which component

```
walter-os (client — runs on your workstation)
├── skills/                  Agent skills
├── agents/                  Walter Council agent definitions
├── contexts/                AGENTS.md cascade templates + examples
├── commands/                Slash command definitions
├── hooks/                   Git hooks and approval gates
├── bin/walter               The walter CLI entry point
├── bin/walter-os            The walter-os CLI (full commands)
├── scripts/walter/          Subcommands: new-project, deploy, etc.
└── setup/bootstrap.sh       Workstation setup (not VM)
    setup/Brewfile           Workstation packages (Homebrew)
    setup/personal-overlay-init.sh  Overlay scaffolding script

walter-host (server — runs on a dedicated machine)
└── setup/walter-host/       Full self-hosted service stack
    ├── bootstrap-vm.sh      Initial server setup script
    ├── install-cron.sh      Cron job installer
    ├── lock-ssh.sh          SSH hardening
    ├── services/            Per-service docker-compose + configs
    │   ├── forgejo/         Self-hosted Git + CI
    │   ├── plane/           Project management
    │   ├── litellm/         LLM model gateway (walter-bridge)
    │   ├── grafana/         Metrics dashboards
    │   ├── n8n/             Workflow automation
    │   └── ...              20+ additional services
    ├── cloudflare/          CF Tunnel + Access setup scripts
    └── singer/              Analytics data taps

shared (root-level compose + configs used by both)
├── compose.yml              Root docker-compose (all-in-one deploy)
└── .env.example             Shared env var template
```

---

## Operator modes

### Mode 1 — Clone-only reference

Clone the repository and use it as a reference. Do not run installers.

```bash
git clone https://github.com/xipher-labs/walter-os ~/Projects/walter-os
cd ~/Projects/walter-os
less AGENTS.md
find contexts skills commands hooks -maxdepth 2 -type f | sort
```

**Required**: nothing beyond Git.
**Writes to your machine**: none outside the clone.
**Use this for**: evaluation, security review, copying patterns into another
repo, or learning the operating model before installing it.

### Mode 2 — Client install

Install walter-os on your workstation. Use SaaS for everything else.

```bash
# Install
git clone https://github.com/xipher-labs/walter-os ~/Projects/walter-os
cd ~/Projects/walter-os
./install.sh

# Configure
cp contexts/_examples/personal.env.example ~/.config/walter-os/overlay/personal.env
# Edit ~/.config/walter-os/overlay/personal.env — set WALTER_GITHUB_ORG at minimum

# Verify
walter doctor
```

**Required**: `WALTER_GITHUB_ORG` in personal.env.
**Not required**: `WALTER_OPERATOR_USER`, `WALTER_DOMAIN` (use defaults).

### Mode 3 — Client + selected services

Run walter-os client on your workstation, then add only the services that solve
a real problem for your setup.

Common examples:

- Infisical for a centralized secrets vault and Machine Identity based runtime
  secrets.
- LiteLLM for model aliases, routing, cost tracking, and audit visibility.
- Grafana or Control Tower for human-visible agent telemetry.
- Syncthing for trusted-device memory and overlay synchronization.
- n8n for workflow automation that agents can trigger or inspect.

You can use SaaS for the rest. For example: GitHub + Linear + Infisical +
LiteLLM is a perfectly valid Walter-OS deployment.

Deploy only the services you need from `setup/walter-host/services/`. Each
service directory has its own compose/config surface and can be promoted into
the full stack later.

### Mode 4 — Full stack (walter-os + walter-host)

Deploy walter-host on a VM, homelab node, or local lab machine, then connect
walter-os on your workstation.

The commands below are the **remote VM example**, which is the reference path
for v0.2.0. Homelab and local-lab installs reuse the same service directories,
but skip cloud VM provisioning and may use a local network or Tailscale-only
access path instead of Cloudflare Tunnel.

```bash
# 1. Provision VM (Hetzner CX31 or equivalent, Ubuntu 24.04)
# 2. Run bootstrap on VM
scp setup/walter-host/bootstrap-vm.sh root@<vm-ip>:/tmp/
ssh root@<vm-ip> "bash /tmp/bootstrap-vm.sh"

# 3. Set up Cloudflare Tunnel (for public HTTPS access)
./setup/walter-host/cloudflare/01-create-zone.sh
./setup/walter-host/cloudflare/02-create-tunnel.sh
./setup/walter-host/cloudflare/03-install-cloudflared.sh
./setup/walter-host/cloudflare/04-create-access.sh

# 4. Deploy services
docker compose up -d

# 5. Configure workstation to use your walter-host services
# Set WALTER_DOMAIN in personal.env
```

**Required**: `WALTER_GITHUB_ORG` and `WALTER_DOMAIN` in personal.env.
The walter-host bootstrap currently creates and uses the fixed server account
`walter`; custom server usernames are not a supported public install path yet.
See `docs/operational/operator-setup-runbook.md` for the full walkthrough.

---

## Frequently asked questions

**Do I need to run a VM to use Walter-OS?**
No. Client-only mode works for the full agent framework (skills, contexts,
Walter Council agents). A VM is only needed if you want the self-hosted service
stack (Plane, Forgejo, LiteLLM, etc.).

**Can I use Walter-OS with my existing SaaS tools?**
Yes. Configure your providers in `~/.config/walter-os/overlay/personal.env`. The agent
framework works with GitHub (instead of Forgejo), Linear (instead of Plane),
and the Anthropic API directly (instead of LiteLLM). Set the relevant API keys
and the Walter Council agents will use them.

**What does `walter vm` do?**
It SSHes into the walter-host VM using the SSH config set up by `bootstrap-vm.sh`.
This command is only relevant in full-stack or homelab mode. In client-only mode,
there is no VM to connect to.

**Can I migrate from client-only to full-stack later?**
Yes. The migration path is:
1. Provision a VM (or repurpose hardware).
2. Run `bootstrap-vm.sh` on the server.
3. Update `WALTER_DOMAIN` in personal.env.
4. Deploy walter-host services.
5. Update your API keys to point at your self-hosted LiteLLM, Forgejo, etc.

No data migration is needed for the client framework itself — skills, contexts,
and AGENTS.md are all workstation-local.

**What is the resource floor for walter-host?**
See `docs/operational/hosting-providers-comparison.md` for the full breakdown.
The minimum tested configuration is 4 vCPU + 8 GB RAM + 80 GB SSD for the core
service subset. The full stack (including PostHog) needs 8 GB RAM minimum,
16 GB recommended.

---

## Why one repository?

Both components live in the same repository for v0.2.0 to simplify distribution:
one `install.sh` bootstraps everything, and the `compose.yml` at the repo root
ties the services together. Post-v0.2.0, walter-host may split to its own
repository if maintenance pressure warrants it (tracked as a future decision).
If and when that split happens, the `setup/walter-host/` directory will become
the new repo's root.
