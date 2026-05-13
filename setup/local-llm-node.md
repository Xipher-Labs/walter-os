# local LLM node Setup Guide

> **Status**: Phase 2 — outline only. Full Ansible playbooks land in the next
> iteration of Walter-OS. This document captures the architecture so you can
> start sourcing hardware.

## What is local LLM node

The local homelab that hosts your self-hosted services (Plane, Vaultwarden,
n8n, Penpot, Postiz, Affine, Grafana stack, monitoring) plus — eventually —
local LLM inference on Apple Silicon.

Accessed exclusively via Tailscale. No public internet exposure.

## Hardware (Phase 1 — services-only, no LLM)

**Recommended**: Mini-PC with Linux + Proxmox VE 9.

Concrete options as of May 2026, priced for Argentina import:

| Box | CPU | RAM | Storage | Price USD |
|---|---|---|---|---|
| Minisforum MS-A2 | Ryzen 9 8945HS | 64 GB DDR5 | 2 TB NVMe + slot | ~$1,100 |
| Beelink SER9 | Ryzen AI 9 365 | 64 GB DDR5 | 2 TB NVMe + slot | ~$1,200 |
| Geekom A8 Max | Ryzen 9 8945HS | 64 GB DDR5 | 2 TB NVMe + slot | ~$1,000 |

All three: dual 2.5GbE, USB4, runs cool and silent. Good for 24/7 ops.

## Hardware (Phase 2 — adds LLM inference)

When the M5 Max arrives and the M2 Ultra (32 GB unified memory) frees up:
**M2 Ultra becomes the dedicated AI inference node**. Tailscale-meshed with
the mini-PC.

This is **better than adding a GPU to the mini-PC** for your case:

- Apple Silicon's unified memory means models that wouldn't fit in 24GB GPU
  VRAM run fine in 32GB unified.
- MLX-LM and Ollama on macOS are mature and fast on Apple Silicon.
- No noisy GPU fans, no PCIe passthrough fiddling, no GPU+driver headaches.
- 32 GB unified comfortably runs: Llama 3.3 70B (Q3), Qwen 2.5 72B (Q3),
  DeepSeek V3 distill (Q4), most 30B-class at Q5/Q6.
- For PHI/medical data: a dedicated machine with no internet egress
  policies (Tailscale-only) is exactly the right architecture.

The M2 Ultra path also removes the GPU passthrough VM from Proxmox — the
mini-PC just runs the services VMs, the M2 Ultra runs Ollama natively.

## Architecture (Phase 1)

```
local LLM node (mini-PC, Proxmox VE 9)
├── LXC: vaultwarden          (256MB,  secrets server)
├── LXC: n8n                  (1GB,    automation/orchestration backbone)
├── LXC: plane                (2GB,    PM tool for personal projects)
├── LXC: postiz               (1GB,    social scheduler with analytics)
├── LXC: penpot               (2GB,    design / branding)
├── LXC: affine               (1GB,    collab wiki for shared projects)
├── LXC: grafana-stack        (2GB,    Grafana + Prometheus + Loki + Alertmanager)
├── LXC: uptime-kuma          (256MB,  external URL monitoring)
├── LXC: forgejo              (1GB,    private git for sensitive repos)
├── LXC: dashboard            (256MB,  Homepage homelab dashboard)
├── LXC: tailscale            (256MB,  control plane node)
└── PBS: backups              (Proxmox Backup Server, replicates to NAS or B2)
```

Total committed RAM at idle: ~12 GB. Headroom for spikes and additional services.

## Architecture (Phase 2 addition)

```
M2 Ultra (Mac mini, native macOS)
├── Ollama  (serves models on Tailscale)
├── OpenWebUI  (chat interface for general use)
└── MLX-LM  (alternative runtime for Apple-native models)

Tailscale mesh:
  local-llm-node (mini-PC) ←→ m2-ultra (Mac) ←→ daily-driver (M5 Max)
```

The mini-PC stays as the services hub (it's stable and cheap to leave
running). The M2 Ultra wakes from sleep on Tailscale request when LLM
inference is needed.

## Network and access

- **Tailscale** is the only access path. No port forwards, no public DNS.
- Each service gets a Tailscale-only DNS name: `plane.walter.tail-net.ts.net`,
  `vaultwarden.walter.tail-net.ts.net`, etc.
- TLS via Tailscale's built-in certificates (no Let's Encrypt needed for
  internal-only traffic, but you can still use Caddy if you prefer named
  certs).
- ACLs configured so devices can only reach services they need (your phone
  doesn't need direct access to Postgres).

## Backup strategy

Three tiers:

1. **Local snapshots** — Proxmox built-in snapshots, hourly for the
   important LXCs.
2. **Local backup** — PBS to a separate disk in the box, or to a small NAS
   on the same network. Daily full + hourly incremental.
3. **Off-site** — encrypted nightly push to Backblaze B2 or Hetzner Storage
   Box. ~$5/month for terabytes. Encrypted with a key NOT stored on the box.

Restore drills: every quarter, restore a random LXC to verify the chain
works.

## Bootstrap order (when hardware arrives)

1. Install Proxmox VE 9 from USB.
2. Configure ZFS pool on the second NVMe.
3. Set up Tailscale at the host level.
4. Restrict the Proxmox web UI to Tailscale-only.
5. Create LXC templates: `debian-base`, `nodejs-base`, `postgres-base`.
6. Run the Walter-OS Ansible playbook (Phase 2 deliverable) to provision
   each service LXC from template + per-service config.
7. Verify each service via Tailscale DNS.
8. Set up backup destinations and run a first full backup.
9. Set up Grafana dashboards (the playbook ships canonical dashboards
   for: box health, service uptime, AI spend, personal-project metrics).
10. Switch your daily Mac to using these services (Plane, Vaultwarden,
    Obsidian sync target).

## What's missing from this document (Phase 2 work)

- Actual Ansible playbooks (`setup/ansible/*`).
- Tailscale ACL JSON for the configured layout.
- LXC template definitions (cloud-init configs).
- Service-specific configs (Plane env, n8n credentials encryption, Postiz
  app keys, etc.).
- Grafana dashboards as JSON.
- Migration runbook from any current setup.

These land in Walter-OS Phase 2 once the hardware is in hand and you've
confirmed the layout matches your actual usage patterns.
