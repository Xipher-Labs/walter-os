# Resource budget — VM sizing per profile combo

Sizing guidance for the self-hosted stack (Mode 3 in the
[README](../../README.md)). Mode 1 / Mode 2 installs don't need a VM at
all — they run on the operator's workstation.

**Minimum specs**: 4 vCPUs, 16 GB RAM, 80 GB SSD for core-only. Full stack
(all profiles) requires 8 vCPUs, 32 GB RAM, 240 GB SSD.

Before provisioning, run `./setup/walter-host/preflight-check.sh` to verify
minimum requirements on an existing VM.

## Hetzner Cloud sizing

| Tier | Use case | Hetzner SKU | vCPU | RAM | SSD | Max monthly | Per-hour |
|---|---|---|---|---|---|---|---|
| Floor | Core services only (no PostHog, no Postiz) | CX33 | 4 | 8 GB | 80 GB | $8.59 | $0.0118 |
| Medium | Core + PostHog minimal setup | CX43 | 8 | 16 GB | 160 GB | $14.59 | $0.0200 |
| **Recommended / Production** | Full stack, single operator | **CX53** | **16** | **32 GB** | **320 GB** | **$27.09** | **$0.0371** |
| Heavy | Multi-zone HA, load-balanced | CX53 × 2 | 32 | 64 GB | 640 GB | $54.18 | $0.0742 |

> Prices: Hetzner Cloud as of 2026-05-12 (USD, excl. VAT, Intel/AMD line —
> Ampere ARM line is similar). `Per-hour` values are derived from `Max
> monthly` using a 730 h/month assumption. Verify current pricing at
> [Hetzner Cloud pricing](https://www.hetzner.com/cloud).
>
> **Heavy tier caveat**: requires improvements for cross-zone load
> balancing (tracked as a future roadmap item; no specific release
> target). For now, single-node CX53 is the recommended ceiling.
>
> For hosting alternatives (DigitalOcean, Vultr, bare metal), see
> [`hosting-providers-comparison.md`](hosting-providers-comparison.md).

## RAM budget by service

Typical RSS under moderate load. Containers can spike; budget ~20%
headroom above the totals below for the OS + Docker + Caddy +
cloudflared.

| Service | Typical RSS | Notes |
|---|---|---|
| PostHog (full) | ~6 GB | ClickHouse ~2 GB; ingestion + UI ~1 GB; shared Postgres ~512 MB |
| Metabase | ~1 GB | JVM-based; heap settable via `JAVA_OPTS` |
| Plane | ~512 MB | Includes Plane API + worker + beat + frontend |
| Infisical | ~512 MB | Backend + frontend |
| n8n | ~512 MB | Node.js runtime |
| Penpot | ~512 MB | Penpot app + Penpot exporter |
| RocketChat | ~512 MB | Node.js, can spike to 1 GB |
| Control Tower | ~512 MB | Next.js app server |
| LiteLLM | ~256 MB | Python; spikes to 512 MB under parallel requests |
| Forgejo | ~256 MB | Go binary; very lean |
| Synapse | ~256 MB | Python; scales with rooms and users |
| Prometheus | ~256 MB | Scales with metric count and retention |
| Grafana | ~256 MB | Go binary |
| Postgres (shared) | ~256 MB | Shared by Plane, Infisical, n8n, Metabase |
| LLM proxies | ~256 MB | Three router containers |
| OpenClaw | ~128 MB | Node.js |
| Homepage | ~128 MB | Go binary |
| Uptime Kuma | ~128 MB | Node.js |
| Syncthing | ~128 MB | Go binary; scales with number of folders |
| Headscale | ~64 MB | Go binary |
| Headscale UI | ~32 MB | Static + minimal server |
| wg-easy | ~32 MB | Node.js; very lean |
| Alerting | ~32 MB | Shared Grafana alerting pipeline |
| Restic | ~64 MB | Go binary; peaks during backup window |
| Drawio | ~128 MB | Java; varies with diagram complexity |
| SeaweedFS | ~256 MB | Go binary; scales with volume count |
| **Total (core)** | **~3.5 GB** | Without monitoring/comms/design/analytics/marketing profiles |
| **Total (full)** | **~12–14 GB** | All profiles; PostHog is the largest contributor |

On a **32 GB VM** you have comfortable headroom for the full stack plus
kernel, Docker, Caddy, cloudflared, and OS overhead (~2 GB baseline).

## LiteLLM resource caps

The Walter-Bridge service stack declares per-container limits via the
`x-walter-limits` anchors in
[`setup/walter-host/services/litellm/compose.yml`](../../setup/walter-host/services/litellm/compose.yml).
These are the first critical-path caps for #351 and should be extended to the
rest of `setup/walter-host/services/*/compose.yml`.

| Container | Default limit | Reservation | vCPU cap | PIDs cap | Override env |
|---|---:|---:|---:|---:|---|
| `litellm` | 1024 MB | 512 MB | 2.0 | 512 | `LITELLM_MEM_LIMIT`, `LITELLM_MEM_RESERVATION`, `LITELLM_CPUS` |
| `litellm-db` | 1024 MB | 512 MB | 1.0 | 256 | `LITELLM_DB_MEM_LIMIT`, `LITELLM_DB_MEM_RESERVATION`, `LITELLM_DB_CPUS` |
| `litellm-pgbouncer` | 128 MB | 64 MB | 0.25 | 128 | `LITELLM_PGBOUNCER_MEM_LIMIT`, `LITELLM_PGBOUNCER_MEM_RESERVATION`, `LITELLM_PGBOUNCER_CPUS` |

The PIDs caps are fixed in compose today; they intentionally do not have env
overrides until the repo-wide #351 standard defines a shared naming scheme.

## Disk + bandwidth

| Component | Disk | Notes |
|---|---|---|
| Postgres (shared) | 5–20 GB | Grows with Plane history + n8n executions |
| ClickHouse (PostHog) | 20–100 GB | Aggressive — set retention via PostHog UI |
| Forgejo repos | 5–50 GB | Operator-dependent |
| Restic backups (local) | 20–80 GB | Rotated; offsite copy to B2/S3 recommended |
| Container images | 10–20 GB | `docker system prune` monthly |
| Total recommended | **240 GB** | For comfortable full-stack runway |

Cloudflared egress is free under Cloudflare's free tier; Hetzner egress is
20 TB/month included on CX-class VMs.

## Related

- [`requirements.md`](requirements.md) — hardware + DNS + SSH prereqs
- [`stack-overview.md`](stack-overview.md) — service-by-service catalogue
- [`hosting-providers-comparison.md`](hosting-providers-comparison.md) —
  alternatives to Hetzner
- [`council-v2-prereqs.md`](council-v2-prereqs.md) — Council-specific
  resource notes
