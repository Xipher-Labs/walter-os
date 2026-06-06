# Break-Glass Recovery Runbook

This runbook gives Walter-VM an out-of-band recovery path that does not depend on cloudflared, Cloudflare Tunnel, or Cloudflare Access.
Use it only when the normal tunnel path is down and you need temporary SSH access to repair the host.

Operator-specific values such as public IP ranges, personal devices, and
tailnet membership belong in private config, not this repository.

## Prerequisites

- A working Hetzner Cloud token in the operator's own shell.
- The Walter-VM server name or ID.
- The operator-controlled public source range for SSH, exported as
  `WALTER_BREAK_GLASS_SSH_CIDR`.
- An SSH key already installed for the `walter` user.

Use the narrowest source range possible:

```bash
export HCLOUD_SERVER_NAME=walter-vm
export WALTER_BREAK_GLASS_SSH_CIDR=203.0.113.10/32
```

Do not use `0.0.0.0/0` or `::/0`.

## Plan The Firewall Change

Dry-run first:

```bash
setup/walter-host/recovery/hetzner-break-glass-ssh.sh \
  --server "$HCLOUD_SERVER_NAME" \
  --cidr "$WALTER_BREAK_GLASS_SSH_CIDR"
```

The command prints the `hcloud firewall create`, `hcloud firewall add-rule`, and
`hcloud firewall apply-to-resource` commands it would run. The committed JSON
template at `setup/walter-host/recovery/hetzner-break-glass-ssh.rules.json.template`
shows the equivalent SSH-only rule shape.

## Apply During Recovery

Only after confirming the server and source CIDR:

```bash
setup/walter-host/recovery/hetzner-break-glass-ssh.sh \
  --server "$HCLOUD_SERVER_NAME" \
  --cidr "$WALTER_BREAK_GLASS_SSH_CIDR" \
  --apply
```

Then SSH directly to the VM address:

```bash
ssh walter@<vm-public-ip>
```

Repair the tunnel from inside the VM:

```bash
sudo systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 100 --no-pager
sudo systemctl restart cloudflared
```

Verify the normal path before removing break-glass access:

```bash
sudo cloudflared tunnel ingress validate /etc/cloudflared/config.yml
sudo systemctl is-active --quiet cloudflared
```

## Teardown

After the normal tunnel or tailnet path is healthy, remove the firewall from the
server. The helper prints the exact command after `--apply`; the shape is:

```bash
hcloud firewall remove-from-resource \
  walter-vm-break-glass-ssh \
  --type server \
  --server "$HCLOUD_SERVER_NAME"
```

Keep the firewall object if you want a reusable template, but do not leave it
attached to the VM after recovery.

## Tailnet Alternative

Tailscale/Headscale is the preferred steady-state non-tunnel path when it is
healthy:

```bash
ssh walter@walter-vm
```

If Headscale registration is broken, use the Hetzner firewall path above first,
then repair Headscale from the VM. A working tailnet path still needs private
operator setup: which device joins, which auth key is used, and which SSH keys
are trusted are operator-specific.
