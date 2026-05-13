# Hosting providers comparison

> **Audience**: operator who hasn't picked a cloud provider yet, or who is
> migrating Walter-OS from one provider to another.
>
> Walter-OS runs entirely in Docker Compose and is not tied to any specific
> provider. Hetzner Cloud is the reference platform because that's where the
> stack has been tested end-to-end. Every other provider on this list will
> work — what differs is pricing, region availability, and a handful of
> provider-specific gotchas documented below.

---

## Minimum specs for Walter-OS

| Resource | Minimum (v0.2.0+) | Recommended |
|---|---|---|
| RAM | 8 GB | 16 GB |
| vCPU | 4 | 8 |
| SSD | 80 GB | 160 GB (backups included) |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| IPv4 | Required for Let's Encrypt (or use Tailscale/Cloudflare Tunnel) | — |
| Outbound UDP | Required for WireGuard / Headscale | — |

**RAM note (v0.2.0+)**: The marketing core (PostHog + ClickHouse + Postiz + Metabase +
Control Tower) adds ~6 GB on top of the base stack. 8 GB is the new minimum floor.
The previous 4 GB minimum applied only to the base stack without marketing services;
that floor is no longer valid once `docker compose up -d` starts PostHog by default.
See `docs/operational/marketing-core-stack.md` for the full RAM breakdown.

**RAM note (pre-v0.2.0)**: 4 GB fit the base core stack (Forgejo, Plane, Infisical,
LiteLLM, Headscale, Caddy, Prometheus, Grafana, n8n) without any profile-gated
services. This is only valid if you explicitly remove or comment out the marketing
core services from `compose.yml`.

**Public IPv4 note**: Caddy uses Let's Encrypt HTTP-01 challenge by default,
which requires a public IPv4 and ports 80/443 open. If you have no public IP
(home lab, NAT-only VPS), use Cloudflare Tunnel or Tailscale — both bypass
this requirement. See the self-host and local-only entries below.

---

## Provider reference

### Hetzner Cloud — recommended default

**Pricing**: ~€4–50/mo depending on instance type.
**Datacenters**: Nuremberg, Falkenstein, Helsinki, Ashburn (US East, added 2023).
**Privacy law**: German BDSG + EU GDPR. Data remains in EU by default.

| Instance | vCPU | RAM | SSD | Price (approx.) | Walter-OS fit |
|---|---|---|---|---|---|
| CX22 | 2 shared | 4 GB | 40 GB | ~€4.50/mo | Minimum — works, no headroom |
| CX31 | 2 shared | 8 GB | 80 GB | ~€7.65/mo | Base stack only (no PostHog) |
| CX41 | 4 shared | 16 GB | 160 GB | ~€15.90/mo | Comfortable with devrel profile |
| CX52 | 8 shared | 32 GB | 240 GB | ~€35/mo | Headroom for heavy workloads |
| CX53 | 16 shared | 32 GB | 360 GB | ~€49/mo | Overkill for solo; good for teams |
| CCX13 | 2 dedicated | 8 GB | 80 GB | ~€14.40/mo | Best price/performance if latency matters |
| CCX33 | 8 dedicated | 16 GB | 240 GB | ~€36/mo | Recommended for full stack + marketing |

**Recommended for full stack (marketing core enabled)**:
**CX41** (4 vCPU, 16 GB RAM) is the minimum comfortable spec once PostHog and
the full marketing layer are running. The full-stack RAM budget:

| Service group | Approx RAM |
|---|---|
| PostHog (6 containers via include:) | 4–6 GB |
| Plane (9 containers) | 1.5 GB |
| Postgres shared | 0.5 GB |
| Observability (Prometheus/Loki/Grafana/etc.) | 1.5 GB |
| LiteLLM + n8n | 1 GB |
| Postiz + Redis | 0.5 GB |
| Metabase | 1.5 GB |
| SeaweedFS | 0.3 GB |
| Subscription routers (3×) | 0.3 GB |
| Control Tower | 0.3 GB |
| Forgejo + Infisical | 0.5 GB |
| OS + Docker overhead | 1–2 GB |
| **Total** | **~14–16 GB** |

CX41 (16 GB) fits the full stack with moderate headroom. CX53 (32 GB) is
comfortable for teams with heavy PostHog event volume or multiple Metabase users.
CX52 (8 GB) is **insufficient** once PostHog is running — the ClickHouse JVM
alone needs 2–3 GB.

**Recommended for lean personal setup (no PostHog / no marketing core)**:
CX31 (€7.65/mo) is the starting point. Disable the PostHog include: stanza
in `compose.yml` if RAM is the binding constraint.

**Gotchas**:
- Hetzner does not assign IPv6 by default on all plans — check before relying
  on dual-stack. IPv4 is always included.
- Block storage is separate (€0.0476/GB/mo). Buy if you need more than the
  instance SSD for Forgejo repos or Syncthing data.
- Snapshots cost extra (€0.0119/GB/snapshot). Plan your backup strategy
  accordingly — restic to Backblaze B2 is cheaper than daily snapshots.
- Firewall is configurable at the Hetzner Cloud console. Walter-OS expects
  ports 22 (SSH), 80 (HTTP, for Let's Encrypt), 443 (HTTPS), and UDP 41641
  (Headscale/WireGuard) to be open inbound.

**Where to spin up**: https://console.hetzner.cloud

---

### DigitalOcean — good UX, higher cost per spec

**Pricing**: ~$6–50/mo.
**Datacenters**: NYC, SFO, AMS, SGP, LON, FRA, BLR, SYD, TOR.
**Privacy law**: US company, EU-US DPF compliant. EU region data stays in EU.

| Droplet | vCPU | RAM | SSD | Price (approx.) | Walter-OS fit |
|---|---|---|---|---|---|
| Basic 4 GB | 2 shared | 4 GB | 80 GB | $24/mo | Minimum |
| Basic 8 GB | 2 shared | 8 GB | 160 GB | $48/mo | Recommended |
| Premium AMD 8 GB | 2 premium AMD | 8 GB | 100 GB NVMe | $48/mo | Better I/O |

**Note**: DigitalOcean is 2–3× more expensive than Hetzner for equivalent RAM.
The advantage is UI quality, excellent documentation, and a large community.
If you're already paying for DigitalOcean for other services and want to
consolidate billing, it's fine. Otherwise, Hetzner gives you more for less.

**Gotchas**:
- Reserved IPs cost $4/mo when not attached to a Droplet. Don't use them
  unless you need a stable IP across Droplet rebuilds.
- Managed databases and block storage are priced separately.
- The $6/mo Droplet (1 GB RAM) is too small for Walter-OS.

**Where to spin up**: https://cloud.digitalocean.com

---

### Vultr — wide global coverage

**Pricing**: ~$6–100/mo.
**Datacenters**: 32 locations across Americas, Europe, Asia, Oceania.
**Privacy law**: US company. Region-local data residency for EU locations.

| Plan | vCPU | RAM | SSD | Price (approx.) | Walter-OS fit |
|---|---|---|---|---|---|
| Cloud Compute 4 GB | 2 shared | 4 GB | 80 GB | $24/mo | Minimum |
| High Frequency 4 GB | 2 HF AMD | 4 GB | 128 GB NVMe | $30/mo | Better I/O than regular |
| Cloud Compute 8 GB | 4 shared | 8 GB | 160 GB | $48/mo | Recommended |

**Gotchas**:
- "High Frequency" instances use NVMe storage and AMD CPUs — meaningfully
  faster disk I/O, relevant for Postgres (Plane, Infisical) under load.
- Pricing similar to DigitalOcean; Hetzner still wins on cost per spec.
- Check IOPS limits on the shared plans — at peak, database-heavy workloads
  can feel sluggish.

**Where to spin up**: https://my.vultr.com

---

### Linode (Akamai Cloud) — stable, DigitalOcean-like

**Pricing**: ~$5–60/mo.
**Datacenters**: 12 locations, global.
**Privacy law**: US company. EU sites covered under Akamai's DPA.

| Plan | vCPU | RAM | SSD | Price (approx.) | Walter-OS fit |
|---|---|---|---|---|---|
| Nanode 1 GB | 1 | 1 GB | 25 GB | $5/mo | Too small |
| Linode 4 GB | 2 | 4 GB | 80 GB | $24/mo | Minimum |
| Linode 8 GB | 4 | 8 GB | 160 GB | $48/mo | Recommended |

**Note**: Linode is a decade-old platform with strong community docs. Pricing
and feature set are nearly identical to DigitalOcean. If you have existing
Akamai CDN relationships, consolidation can be useful.

**Gotchas**:
- Object storage is available in some regions (S3-compatible, good for restic
  backup target if you don't want Backblaze B2).
- The "Nanode" 1 GB plan is the cheapest tier but cannot run Walter-OS.

**Where to spin up**: https://cloud.linode.com

---

### OVH Cloud — cheap, especially in EU

**Pricing**: ~€3–30/mo.
**Datacenters**: France, UK, Germany, Canada, Australia, Singapore, US.
**Privacy law**: French company, GDPR compliant. Competitive EU privacy story.

| Plan | vCPU | RAM | SSD | Price (approx.) | Walter-OS fit |
|---|---|---|---|---|---|
| Starter | 1 | 2 GB | 40 GB | ~€3.50/mo | Too small |
| Value | 1 | 4 GB | 40 GB | ~€6/mo | Minimum (1 CPU may bottleneck) |
| Essential | 2 | 4 GB | 80 GB | ~€9/mo | Minimum, better |
| Comfort | 4 | 8 GB | 160 GB | ~€18/mo | Recommended |

**Gotchas**:
- OVH's UI is less polished than Hetzner/DO. First-time setup takes longer.
- Some plans are marketed as "Public Cloud" (OpenStack-based) vs "VPS" — the
  Public Cloud (Compute) line maps to the prices above. The VPS line is
  cheaper but uses older hardware and is less reliable for production.
- OVH has had notable outages (Strasbourg fire, 2021). Use backups.
- Object storage available (S3-compatible) at €0.01/GB/mo — good for restic.

**Where to spin up**: https://www.ovhcloud.com/en/public-cloud

---

### Scaleway — EU-native, good developer experience

**Pricing**: ~€4–40/mo. Stardust instances (€3.06/mo) useful for dev/test.
**Datacenters**: Paris, Amsterdam, Warsaw.
**Privacy law**: French company, GDPR. Data sovereignty story is strong.

| Plan | vCPU | RAM | SSD | Price (approx.) | Walter-OS fit |
|---|---|---|---|---|---|
| Stardust1-s | 1 | 1 GB | 10 GB | €3.06/mo | Dev/test only (too small for prod) |
| PLAY2-PICO | 1 | 1 GB | — | €3.60/mo | Too small |
| PRO2-S | 3 | 8 GB | — | ~€11/mo | Recommended for core stack |
| PRO2-M | 5 | 16 GB | — | ~€22/mo | Comfortable with devrel profile |

**Note**: Scaleway separates compute from block storage — the PRO2 instances
don't include local SSD, so you'll add a 40–80 GB block volume (~€4–8/mo).
Factor that into the total cost.

**Gotchas**:
- Scaleway has a generous free tier for Object Storage (75 GB). Good for
  restic backup target.
- Stardust instances are useful for testing the install.sh wizard on a clean
  machine before committing to a larger instance. Too constrained for real use.

**Where to spin up**: https://www.scaleway.com/en/

---

### AWS Lightsail, GCP Compute Engine, Azure VMs

**Short version**: avoid unless you're already deep in one of these ecosystems.

All three providers are 4–8× more expensive per spec than Hetzner. A
comparable 8 GB / 2 vCPU / 80 GB SSD instance runs:
- AWS Lightsail: $40/mo
- GCP e2-medium (2 vCPU / 4 GB): ~$35/mo (no persistent disk included)
- Azure B2s (2 vCPU / 4 GB): ~$35/mo

Walter-OS has no dependency on any cloud-native service (no managed RDS, no
cloud IAM, no proprietary object storage). You'd be paying hyperscaler
premium for a Linux VM that runs Docker — the same thing you can get from
Hetzner for €8.

**When it makes sense**: if your employer provides AWS/GCP/Azure credits, or
if you need to co-locate Walter-OS with existing infrastructure in that cloud.
In those cases, the integration cost justifies the price premium.

---

### Self-host on home server (local LLM node pattern)

**Hardware examples**: rack server standby homelab node, Synology NAS, old desktop/mini PC.
**Effective cost**: electricity + bandwidth (~$5–30/mo depending on hardware
and local rates).
**Privacy**: maximum — data never leaves your network.

This is the reference homelab pattern (standby homelab node, see
`docs/specs/archive/local-llm-node.md`). The tradeoffs are:

| Advantage | Disadvantage |
|---|---|
| No monthly cloud bill (amortized hardware) | You are the datacenter: power, cooling, UPS, ISP |
| Data physically under your control | Home ISP may block inbound ports 80/443 |
| No egress fees | Residential IP may trigger CAPTCHA / blocklists |
| Can run GPU workloads locally (Ollama) | No SLA on home internet (outages affect everything) |

**Making it work**:
- Use Cloudflare Tunnel (`cloudflared`) to expose services without opening
  ports on your router. Tunnel connects outbound from your server to
  Cloudflare's edge. No port forwarding needed. Works on any ISP.
- Or use Tailscale/Headscale for private access only (no public exposure).
- Static IP from ISP is helpful but not required when using either of the above.

**Gotchas**:
- Power outages kill the VM unless you have a UPS.
- Home ISP symmetric upload speeds can be a bottleneck for Forgejo clone
  operations or Syncthing sync.
- standby homelab node draws 200–400W under typical load — factor into electricity cost.

---

### Local-only (no cloud, no home server)

**Setup**: Mac Mini or any always-on laptop on your LAN, with Tailscale for
remote access.
**Cost**: essentially zero if hardware already exists (electricity only).

This is the minimal viable Walter-OS: everything runs in Docker Compose on a
local machine, access via Tailscale from other devices. No public-facing
services. No Let's Encrypt (use Caddy with a self-signed cert, or skip HTTPS
entirely on the local network).

**Limitations**:
- Forgejo, Plane, n8n, etc. are only reachable when you're on Tailscale.
- No public webhooks from GitHub, Stripe, or any external service unless
  you expose a Tailscale funnel endpoint (Tailscale's tunnel feature).
- Relies on the local machine being on and not sleeping.

**Good for**: testing Walter-OS before committing to a VPS, or for an
entirely private single-device setup.

---

## Walter-OS portability notes

All services run via Docker Compose. There is no provider lock-in at the
application layer.

| Component | How it's portable |
|---|---|
| Services | `compose.yml` runs identically on any Ubuntu/Debian host with Docker |
| SSL | Caddy handles Let's Encrypt automatically — no manual cert management |
| VPN | WireGuard + Headscale work on any provider that allows UDP traffic |
| Backups | restic to Backblaze B2 or any S3-compatible endpoint — provider-agnostic |
| DNS | Cloudflare DNS + Tunnel — provider of the VPS is irrelevant to DNS |
| Secrets | Infisical self-hosted — follows the Docker Compose, moves with you |

Migrating from one provider to another is:
1. Snapshot the old VM (or run `restic backup` manually).
2. Spin up a new VM on the new provider.
3. Run `./install.sh` on the new VM.
4. Restore from the restic snapshot.
5. Update your DNS records to point to the new IP.
6. Decommission the old VM.

End-to-end: roughly 1–2 hours, depending on how large your Forgejo repos and
Plane database are.

---

## Quick decision guide

```
Do you have a home server running 24/7?
  Yes → Self-host. Use Cloudflare Tunnel for public access.
  No  → Pick a VPS.

Do you need EU data residency?
  Yes → Hetzner (Germany) or OVH/Scaleway (France).
  No  → Hetzner Ashburn or Vultr (wider regions).

Are you already on AWS/GCP/Azure?
  Yes → Use their cheapest VM type. Accept the price premium.
  No  → Hetzner CX31 (€7.65/mo). Start there.

Do you want maximum simplicity for first install?
  → Hetzner CX31 + Ubuntu 24.04. Tested. Documented. Cheapest.
```
