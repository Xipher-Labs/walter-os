# Headscale Runbook

Headscale is optional mesh networking for Walter-VM. It is useful for private
admin paths, but it is not the primary out-of-band recovery path.

Do not rely on Headscale as the primary break-glass path. Use the Hetzner Cloud
Firewall SSH allow-list documented in `docs/runbooks/break-glass-recovery.md`
when Cloudflare Tunnel or Cloudflare Access becomes unavailable.

## Registration Fails With HTTP 500

Observed failure:

```text
tailscaled: register request: POST https://headscale.example.com/machine/register
  -> unexpected HTTP response: 500 Internal Server Error
```

Server-side Headscale log:

```text
ERR user msg: capability version must be set code=400
```

Known affected combination from issue #363:

- Headscale 0.26.0, pinned in `compose.yml`
- Tailscale 1.96.4 clients

This is capability-version drift between the Tailscale client and Headscale
server support. Newer Tailscale clients may advertise capability versions that
the currently pinned Headscale release does not understand.

## Diagnose

Run these on Walter-VM:

```bash
docker compose -f /opt/walter-vm/services/headscale/compose.yml ps
docker logs headscale --since 10m
docker exec headscale headscale version
tailscale version
```

Run this on the client trying to join:

```bash
tailscale version
tailscale up --login-server=https://headscale.example.com
```

If `/key` is reachable but `/machine/register` fails, the path is likely not a
Cloudflare Access bypass problem. Check the Headscale logs before changing
tunnel routing.

## Resolution Paths

### Preferred During Outages

Use the Hetzner Cloud Firewall SSH allow-list break-glass path, repair the VM,
and keep Headscale out of the critical recovery path until version compatibility
is known-good.

### Version Pin Path

Pin Tailscale clients to a Headscale-compatible version only when the operator
accepts the maintenance and security trade-off. This affects every joining
device, not only Walter-VM.

Record pins in the personal overlay or config-personal repository, not in this
public repo.

### Upgrade Path

Upgrade the pinned Headscale image only after confirming the target Headscale
release supports the client capability version in use. Do not assume that
bumping Headscale to the latest release supports the newest Tailscale client.

After changing versions:

```bash
docker compose -f /opt/walter-vm/services/headscale/compose.yml pull
docker compose -f /opt/walter-vm/services/headscale/compose.yml up -d
docker logs headscale --since 10m
```

Then retry registration from a client and confirm the tailnet has at least one
node.

## Release Tracking

Watch Headscale release notes for client compatibility changes before changing
the pinned image. Treat very new Tailscale clients as potentially incompatible
until a registration smoke test passes.
