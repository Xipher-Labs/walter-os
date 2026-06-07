# Walter-VM provisioning

Scripts to bring a fresh Hetzner VM into a Walter-VM serving state. Idempotent
where possible; safe to re-run.

## Target hardware

Recommended for the **FULL profile**: **Hetzner CX53** or equivalent
(16 vCPU / 32 GB RAM / 320 GB disk), Ubuntu 24.04 LTS. A **CX43**-class host
(8 vCPU / 16 GB RAM / 160 GB disk) is the medium tier and should not run every
Walter-host service on one VM.

Before deploying, run:

```bash
./setup/walter-host/preflight-check.sh full
```

Use `floor` or `medium` for smaller service selections. Set
`WALTER_PREFLIGHT_ALLOW_UNDERSIZED=1` only for an intentional, operator-owned
override.

Bundled load alerts derive the vCPU ceiling from runtime host metrics, so
smaller or larger plans should not require manual threshold edits.

## Order

```
1. setup/walter-host/bootstrap-vm.sh         # all base setup (idempotent)
2. (operator) add walter SSH pubkey
3. (operator) tailscale up
4. setup/walter-host/lock-ssh.sh             # AFTER walter SSH verified
5. setup/walter-host/services/<name>/...     # service-by-service deploy (Phase K3)
```

## What `bootstrap-vm.sh` does

- apt update + upgrade
- Base CLIs: curl, git, jq, vim, tmux, htop, ripgrep, age, restic, rclone, etc.
- Security: ufw, fail2ban, unattended-upgrades enabled
- 4GB swap (CX/CPX plans ship with no swap)
- `walter` non-root user with `sudo NOPASSWD` and docker group
- Tailscale binary installed (`tailscale up` is separate — needs auth key)
- Docker CE + compose plugin
- Caddy (reverse proxy, host service — not container)
- UFW: default-deny + 22/80/443/41641-udp + tailscale0 trusted
- Initial Caddyfile in `/etc/caddy/Caddyfile`
- `/opt/walter-vm/` directory layout with `docker-compose.yml` skeleton

## What `bootstrap-vm.sh` does NOT do

- `tailscale up` — needs auth key from operator
- SSH lockdown — would lock you out if walter has no key
- Deploy any service — separate scripts per service

## Running

```bash
# From your Mac:
scp setup/walter-host/bootstrap-vm.sh root@<vm-ip>:/tmp/
ssh root@<vm-ip> "bash /tmp/bootstrap-vm.sh"
```

Re-running on already-provisioned VM is safe — each step checks state first.

## After bootstrap, in this order

### Step A — walter SSH key

```bash
cat ~/.ssh/id_ed25519.pub | ssh root@<vm-ip> \
  "tee /home/walter/.ssh/authorized_keys >/dev/null && \
   chmod 600 /home/walter/.ssh/authorized_keys && \
   chown walter:walter /home/walter/.ssh/authorized_keys"

# Verify (NEW terminal — keep root session open as fallback):
ssh walter@<vm-ip> "id; sudo whoami"
```

### Step B — Tailscale up

Get auth key from https://login.tailscale.com/admin/settings/keys
(use ephemeral + tagged key for VM identity, e.g., `tag:walter-vm`).

```bash
ssh root@<vm-ip> "tailscale up \
  --auth-key=tskey-auth-... \
  --hostname=walter-vm \
  --advertise-tags=tag:walter-vm \
  --ssh"
```

### Step C — Lock SSH (only after A + B verified)

Before locking SSH, configure at least one break-glass recovery path that does
not depend on the Cloudflare Tunnel. The recovery runbook covers a temporary
Hetzner firewall rule for SSH from an operator-controlled IP/CIDR:
[`docs/runbooks/break-glass-recovery.md`](../../docs/runbooks/break-glass-recovery.md).

```bash
ssh root@<vm-ip> "bash" < setup/walter-host/lock-ssh.sh
```

After this, root SSH is disabled. Future access: `ssh walter@<vm-ip>`
or via Tailscale: `ssh walter@walter-vm.<tailnet>.ts.net`.

### Step D — Deploy services (Phase K3)

Per-service scripts under `setup/walter-host/services/`:

- `vaultwarden/` — secrets manager (deploy first to migrate other secrets)
- `litellm/` — AI gateway (cost tracking + smart routing)
- `plane/` — PM
- `forgejo/` — git + Obsidian sync target
- `uptime-kuma/` — uptime monitoring
- `homepage/` — homelab dashboard

Each service folder contains:
- `compose.yml` — docker-compose service definition
- `deploy.sh` — idempotent deploy script
- `README.md` — what the service does + post-deploy steps

## Troubleshooting

### SSH lockout

If you locked yourself out:
1. Hetzner Cloud Console → ISO console (browser-based root shell)
2. Edit `/etc/ssh/sshd_config.d/99-walter-os.conf` to set
   `PermitRootLogin yes` temporarily
3. `systemctl reload ssh`
4. Fix the underlying issue, re-run `lock-ssh.sh`

### Caddy not serving

```bash
caddy validate --config /etc/caddy/Caddyfile
journalctl -u caddy -n 50
```

### Docker permission denied for walter

`walter` was added to docker group during bootstrap. Re-login required:
```bash
exit
ssh walter@<vm-ip>
```

### UFW blocking something

```bash
sudo ufw status numbered
sudo ufw allow <port>/tcp comment "<reason>"
```
