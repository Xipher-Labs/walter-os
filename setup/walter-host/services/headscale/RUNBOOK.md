# Headscale Runbook

Headscale is optional mesh networking for Walter-VM. It is useful for private
admin paths, but it is not the primary out-of-band recovery path.

Do not rely on Headscale as the primary break-glass path. Use the Walter-VM
Hetzner Cloud Firewall SSH allow-list path when Cloudflare Tunnel or Cloudflare
Access becomes unavailable: temporarily allow TCP/22 from your current public
IP/CIDR to the Walter-VM server, repair the VM over SSH, then remove that
allow-list rule after normal access is healthy again.

## Registration Fails With HTTP 500

Observed failure:

```text
tailscaled: register request: POST https://headscale.${WALTER_DOMAIN}/machine/register
  -> unexpected HTTP response: 500 Internal Server Error
```

Server-side Headscale log:

```text
ERR user msg: capability version must be set code=400
```

The client can still surface this as HTTP 500 even when Headscale logs the
underlying registration error as `code=400`; check both sides before assuming
the proxy or tunnel rewrote the status.

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

Or run the read-only diagnostic helper:

```bash
cd /opt/walter-vm/services/headscale
./deploy.sh --diagnose
```

If the helper prints one of these known blockers, follow the matching recovery
path before treating Headscale as healthy:

- `Headscale container is not running` means the service is stopped or exited.
  Start it with:

  ```bash
  docker compose -f /opt/walter-vm/services/headscale/compose.yml up -d
  ```

  Then re-run `./deploy.sh --diagnose`. Do not use stale logs as proof of
  health after the container has stopped.
- `capability-version drift detected` means the server rejected client
  registration before the node joined the tailnet. Use the version pin or
  upgrade paths below.
- `TS2021 WebSocket proxy warning detected` means Headscale saw a TS2021 request
  without an `Upgrade` header. Inspect the Cloudflare Tunnel/Caddy route for
  `headscale.${WALTER_DOMAIN}` and verify WebSocket upgrade headers reach the
  Headscale container.

Run this on the client trying to join:

```bash
tailscale version
tailscale up --login-server=https://headscale.${WALTER_DOMAIN}
```

If `/key` is reachable but `/machine/register` fails, the path is likely not a
Cloudflare Access bypass problem. Check the Headscale logs before changing
tunnel routing.

If Headscale logs this instead:

```text
No Upgrade header in TS2021 request
```

the client registration path is going through an incompatible proxy path.
Do not route `headscale.${WALTER_DOMAIN}` through Cloudflare Tunnel. Cloudflare
does not support the WebSocket POSTs required by Headscale/Tailscale TS2021
traffic. Keep `headscale-admin.${WALTER_DOMAIN}` behind Cloudflare Access, but
publish the client control-plane hostname through a DNS-only direct origin path
to Caddy/Headscale. Reference:
<https://headscale.net/0.26.1/ref/integration/reverse-proxy/#cloudflare>.

## Resolution Paths

### Preferred During Outages

Use the Hetzner Cloud Firewall SSH allow-list break-glass path, repair the VM,
and keep Headscale out of the critical recovery path until version compatibility
is known-good. In Hetzner, the minimal action is to allow TCP/22 only from your
current public IP/CIDR to Walter-VM, then remove that allow-list after recovery.

### Direct Route Path

For normal client registration, publish `headscale.${WALTER_DOMAIN}` outside
Cloudflare Tunnel:

1. Leave `headscale-admin.${WALTER_DOMAIN}` in Cloudflare Access.
2. Create or update `headscale.${WALTER_DOMAIN}` as a DNS-only record that
   reaches the Walter-VM origin/Caddy path.
3. Remove any old proxied CNAME to `<tunnel-id>.cfargotunnel.com` for
   `headscale.${WALTER_DOMAIN}`.
4. Retry `tailscale up --login-server=https://headscale.${WALTER_DOMAIN}`.
5. Confirm `docker exec headscale headscale nodes list` shows the joined node.

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
