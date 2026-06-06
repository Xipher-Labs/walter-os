# Walter-VM Ansible

Declarative replacement for the per-service `deploy.sh` scripts. Same
infrastructure, but version-controlled state + tag-based selective deploys.

## Status

Phase K5 — **scaffolding only**. The `service` role works for any service
that follows the convention (compose.yml + .env.template). Per-service
custom logic (cloudflared route adds, DNS records, CF Access apps) still
lives in helper scripts. Ansible deploys/updates compose state idempotently;
non-compose state stays in scripts.

## Usage

```bash
# Activate operator's ansible venv
ans

# Or if no venv:
brew install ansible community.general ansible.posix

cd ansible/

# Apply everything
ansible-playbook walter-vm.yml

# Just one service
ansible-playbook walter-vm.yml --tags grafana

# Multiple services / categories
ansible-playbook walter-vm.yml --tags monitoring   # observability + uptime-kuma
ansible-playbook walter-vm.yml --tags vpn          # wireguard + headscale

# Base OS layer only (no services)
ansible-playbook walter-vm.yml --tags base

# Dry-run (check mode)
ansible-playbook walter-vm.yml --check --diff

# Verbose
ansible-playbook walter-vm.yml -vv
```

## Layout

```
ansible/
├── inventory.yml          # walter-vm host (via cloudflared SSH tunnel)
├── ansible.cfg            # defaults
├── walter-vm.yml          # master playbook
├── group_vars/
│   └── all.yml            # vars across all hosts
├── roles/
│   ├── base/              # apt, ufw, swap, walter user, fs layout
│   ├── cloudflared/       # tunnel config + service
│   ├── service/           # generic Docker service deployer (data-driven by service_name)
│   └── alerting/          # Tier 2-4 cron scripts
└── README.md
```

## Service role contract

`roles/service/` deploys ANY service that follows this convention in
`setup/walter-host/services/<name>/`:

```
setup/walter-host/services/<name>/
├── compose.yml            # required
├── .env.template          # optional — copied to .env if missing
├── (other files)          # synced to VM (configs, scripts)
```

Role steps (idempotent):
1. Create `/opt/walter-vm/services/<name>/`
2. Rsync everything except `.env` (preserves operator-set values)
3. Copy `.env.template` → `.env` only if `.env` doesn't exist yet
4. `docker compose pull`
5. `docker compose --env-file .env up -d`

## Cloudflared role contract

`roles/cloudflared/` installs the `cloudflared` package and can install the
tunnel as a systemd service when tunnel files already exist locally.

By default it looks for:

```
/tmp/walter-cf/
├── credentials.json
└── config.yml
```

Override the source directory with:

```bash
WALTER_CLOUDFLARED_LOCAL_DIR=/path/to/walter-cf ansible-playbook walter-vm.yml --tags cloudflared
```

If those files are absent, the role installs the package but skips service
configuration. Creating tunnels, DNS records, and Cloudflare Access apps still
lives in `setup/walter-host/cloudflare/*.sh`.

## Alerting role contract

`roles/alerting/` ships the Walter-VM watchdog scripts and `cron.example` to
`/opt/walter-vm/services/alerting/`. It does not install cron automatically
because the scripts require root-owned credentials in
`/etc/walter-vm/alerting.env`. Create that file with `sudo install -m 600`
after filling Telegram and Hetzner values.

## What this DOES NOT replace

- Cloudflare DNS / Access apps (use `setup/walter-host/cloudflare/*.sh`)
- One-off setup like `restic init`, `headscale users create`, etc.
  (use the per-service deploy.sh for those)

## Migration plan

We move services to Ansible incrementally:

| Service | Status |
|---|---|
| base / cloudflared | scaffolded |
| Plane / Forgejo / Infisical | should-just-work via service role |
| LiteLLM / n8n / Grafana | should-just-work |
| Synapse / Element | should-just-work |
| Restic | needs special init → per-service deploy.sh stays |
| OpenClaw | needs interactive onboard → per-service deploy.sh stays |
| Headscale | needs `headscale users create` → per-service deploy.sh stays |

## Future: Ansible-Vault for secrets

Currently service `.env` files are populated manually OR by per-service
`deploy.sh`. Future: pull from Infisical at deploy time via:

```yaml
- name: Fetch secrets from Infisical
  ansible.builtin.command: >
    infisical export --domain=https://secrets.${WALTER_DOMAIN}
    --projectName={{ infisical_workspace }}
    --env={{ infisical_env }}
    --format=dotenv > {{ walter_services_dir }}/{{ service_name }}/.env
```

This requires Infisical machine identity setup (see skills/secrets-yubikey-unlock).
