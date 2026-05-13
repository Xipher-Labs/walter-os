> **EXAMPLE FILE — Self-Hosted Enthusiast / Homelab Operator**
> This file shows how a self-hosted enthusiast running a homelab might
> configure their personal context overlay. All domain names and hardware
> references are fictional. Replace every `[BRACKETED]` or placeholder value
> with your actual situation before placing this file at
> `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`.

# AGENTS.md — Personal Context [Self-Hosted Enthusiast]

## Homelab overview

- **Primary server**: repurposed server (2x Xeon, 128 GB RAM, Ubuntu 24.04)
  running Proxmox. Hosts 8 VMs and 12 LXC containers.
- **NAS**: Synology RS1221+ with 6x 8 TB WD Red Pro (RAID-6). ZFS pool.
- **Network**: UniFi Dream Machine Pro, VLAN segmentation per trust zone.
- **Tailscale**: full mesh VPN connecting workstation, server, NAS, and phone.
- **Domain**: `<your-domain>` (Cloudflare DNS + Tunnel for public services).

## Services running

- **Forgejo**: self-hosted git at `git.<your-domain>`
- **Jellyfin**: media server (local network only, never exposed to internet)
- **Vaultwarden**: password manager at `vault.<your-domain>` (Tailscale-only)
- **Uptime Kuma**: health monitoring at `status.<your-domain>`
- **Nextcloud**: file sync + calendar + contacts
- **Immich**: photo backup (replaces Google Photos)

## Backup strategy

- **3-2-1 rule**: 3 copies, 2 media types, 1 offsite.
- Primary: ZFS snapshots (hourly, keep 24h; daily, keep 30d).
- Secondary: Restic to Backblaze B2 (nightly, encrypted).
- Offsite: quarterly manual backup to external drive at [location].

## Agent behavior in this context

- Mode: assist only. No autonomous changes to server config.
- The agent may draft Ansible playbooks, Dockerfile changes, and docker-compose
  edits, but never applies them without operator confirmation.
- Never auto-restart services that other household members depend on
  (Jellyfin, Nextcloud) without a 24-hour notice period.
- PHI rule: if any health tracking data appears, local LLM only.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS for my **personal** context. I run a homelab and
> self-host most of my services. My specifics:
>
> - Hardware: [server specs / NAS / SBC like Raspberry Pi / mini PC / other]
> - Virtualization: [Proxmox / VMware / bare Docker / LXC / other]
> - Storage: [NAS model and capacity / external drives / ZFS / BTRFS]
> - Networking: [router brand, VLANs yes/no, VPN type]
> - Domain: [own domain with Cloudflare / DuckDNS / no public access]
> - Main services running: [list your key self-hosted services]
> - Backup strategy: [current backup approach]
> - Other household members who depend on services: [yes/no]
> - Privacy requirements: [any PHI or sensitive data? local LLM needed?]
>
> Based on the generic Walter-OS personal context template, generate a
> customized `AGENTS.md` for me. Output only the Markdown content of the
> `AGENTS.md` file, ready to drop into
> `~/.config/walter-os/overlay/contexts/personal/AGENTS.md`.
