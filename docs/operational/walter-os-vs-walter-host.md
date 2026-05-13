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

## Deployment patterns

Four patterns are supported. Choose based on your situation.

| Pattern | Setup | When to use | Recommended? |
|---|---|---|---|
| **Client-only** | walter-os on workstation, no walter-host | Just the agent framework; use SaaS for git, issues, and LLM APIs | **Yes** — for individual users starting out |
| **Local walter-host** | Both walter-os and walter-host on the same machine (laptop or desktop) | Single-user development, full offline capability, testing the full stack | **Acceptable but discouraged** — resource intensive, no multi-device access |
| **Remote walter-host** | walter-os on workstation, walter-host on a dedicated VM (Hetzner CX31 or equivalent) | Production use, multi-device access, team usage | **Yes — recommended default** for operators who want full self-hosting |
| **Homelab walter-host** | walter-host on a local server (Proxmox, bare metal, mini-PC) | Privacy-first, no cloud spend, full control over data | **Yes** — for privacy-focused operators |

### Trade-offs in detail

**Client-only** is the right start for most operators. You install walter-os
(`./install.sh`), set `WALTER_GITHUB_ORG` and a few other vars in
`~/.config/walter-os/overlay/personal.env`, and have a working agent framework in
minutes. You keep using GitHub, Linear, and the Anthropic API directly.
No VM to maintain.

**Local walter-host** works but has a real cost: the full walter-host stack
needs at least 4 GB RAM and significant CPU headroom (see
`docs/operational/hosting-providers-comparison.md` for the resource floor).
Running that on your laptop competes with your daily workload (IDE, browser,
video calls). It is useful for testing the full stack without paying for a VM,
or for operators who work from a powerful desktop with no multi-device needs.

**Remote walter-host (VM)** is the recommended production pattern because:
1. Resources do not compete with your daily workload.
2. The stack is accessible from any workstation via Tailscale or Cloudflare Tunnel.
3. Cleaner separation of concerns: client code on your Mac, services on the VM.
4. Hetzner CX31 (~€7/month) covers the minimum resource floor comfortably.

**Homelab walter-host** is the best choice for operators who want full data
sovereignty, no cloud spend, and are comfortable maintaining physical hardware.
Proxmox on a repurposed server or a mini-PC like a NUC runs the stack well.
The Tailscale-based access model in `setup/walter-host/` works equally well
over a local network.

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

### Mode 1 — Client-only

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

### Mode 2 — Full stack (walter-os + remote walter-host VM)

Deploy walter-host on a VM, then connect walter-os on your workstation.

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
# Set WALTER_DOMAIN, WALTER_OPERATOR_USER in personal.env
```

**Required**: `WALTER_GITHUB_ORG`, `WALTER_DOMAIN`, `WALTER_OPERATOR_USER` in personal.env.
See `docs/operational/operator-setup-runbook.md` for the full walkthrough.

### Mode 3 — Hybrid

Run walter-os client on your workstation but only deploy a subset of
walter-host services. Common hybrid: use GitHub + Linear (SaaS) but self-host
LiteLLM for cost routing and Grafana for observability.

Deploy only the services you need from `setup/walter-host/services/`.
Each service directory has its own `compose.yml` that can be deployed
independently.

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
3. Update `WALTER_DOMAIN` and `WALTER_OPERATOR_USER` in personal.env.
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
