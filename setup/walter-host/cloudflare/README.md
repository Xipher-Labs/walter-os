# Cloudflare Tunnel + Access setup for Walter-VM

Replaces Tailscale for VM connectivity. Uses Cloudflare's edge to terminate
TLS + auth, with `cloudflared` running on the VM as the only outbound
connection (no inbound ports needed).

## Architecture

```
[your browser]
    ↓ HTTPS
[Cloudflare edge — TLS + auth]
    ↓ (Cloudflare Access policy: must be email @${WALTER_DOMAIN})
[walter-vm.cfargotunnel.com — outbound-only QUIC tunnel]
    ↓
[cloudflared on Walter-VM]
    ↓
[Caddy on host:80]
    ↓
[docker-compose service ports on 127.0.0.1]
```

**Public ports on Hetzner**: only `22/tcp` (SSH) until you lock that down too.
Nothing else. Even `80`/`443` can be closed in UFW after Tunnel is verified.

## Domain layout

8 hostnames covering the planned service stack, all under `${WALTER_DOMAIN}`:

| Hostname | Service | Local port |
|---|---|---|
| `vault.${WALTER_DOMAIN}` | (deprecated — using 1Password instead) | 8222 (kept for compat) |
| `llm.${WALTER_DOMAIN}` | LiteLLM AI gateway | 4000 |
| `plane.${WALTER_DOMAIN}` | Plane (PM) | 8090 |
| `git.${WALTER_DOMAIN}` | Forgejo | 3000 |
| `secrets.${WALTER_DOMAIN}` | Infisical (app secrets) | 8800 |
| `status.${WALTER_DOMAIN}` | Uptime-Kuma | 3001 |
| `home.${WALTER_DOMAIN}` | Homepage dashboard | 3010 |
| `uptime.${WALTER_DOMAIN}` | (alias of status.${WALTER_DOMAIN}) | 3001 |

Auth: Cloudflare Access policy = "email domain ends in `${WALTER_DOMAIN}`".
Login methods: Google (via Workspace) OR One-Time PIN to email.

## Files

- `01-create-zone.sh` — create `${WALTER_DOMAIN}` zone in CF + import existing DNS
- `02-create-tunnel.sh` — create Tunnel + service CNAMEs + cloudflared config
- `03-install-cloudflared.sh` — install + run cloudflared on the VM
- `04-create-access.sh` — Access app + policy (run AFTER zone is active)
- `config.yml.template` — reference cloudflared config
- `.env.example` — required env vars

## Required env vars

Source from `~/.config/walter-os/secrets.env`:

```bash
export CF_EMAIL="${WALTER_ADMIN_EMAIL}"
export CF_KEY="cfk_..."           # Global API Key
export CF_ACCOUNT="c65e33d..."    # Account ID
export ZONE_ID="..."              # filled by 01-create-zone.sh
export TUNNEL_ID="..."            # filled by 02-create-tunnel.sh
```

## Order of execution

1. Run `01-create-zone.sh` — outputs the NS pair.
2. **MANUAL**: change nameservers at registrar to the CF NS.
3. Run `02-create-tunnel.sh`.
4. Run `03-install-cloudflared.sh` (SSH to VM).
5. Wait for zone to go `active` in CF (NS propagation: minutes-to-hours).
6. Run `04-create-access.sh`.
7. Test by visiting any hostname.

## Why this beats Tailscale for this use case

- ✅ No client install on Mac (browser-only access)
- ✅ Works from any device, anywhere
- ✅ No inbound ports on Hetzner
- ✅ Browser-based auth (no auth-key juggling)
- ✅ Granular per-hostname policies if needed later
- ✅ Free for personal use

## What this does NOT cover

- SSH to the VM (separate; goes via Hetzner public IP + key auth, OR can be
  added via `cloudflared access ssh` for a SSH-over-Cloudflare flow).
- Inter-service communication (services talk to each other on the docker
  network internally, not via Cloudflare).
