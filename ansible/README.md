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

## Optional Service Placement Overlay

By default, `walter-vm.yml` preserves the current behavior for the play's target
hosts: every service listed in the playbook is deployed to hosts in the
`walter_vm` inventory group.

Operators with a private multi-host topology can provide an overlay placement
manifest without committing their host names, VM roles, sizing, or service map
to this public repo:

```bash
WALTER_SERVICE_PLACEMENT_FILE=/path/to/service-placement.yml \
  ansible-playbook walter-vm.yml
```

The path must be absolute. The same value can also be passed as an Ansible
extra var:

```bash
ansible-playbook walter-vm.yml \
  -e walter_service_placement_file=/path/to/service-placement.yml
```

The placement file maps service names to Ansible inventory group names:

```yaml
services:
  litellm:
    vms: [walter_vm]
  posthog:
    vms: [vm_aux]
```

When a placement file is loaded, the generic `service` role deploys a service
only if one of its `vms` entries matches the current host's inventory groups.
Hosts assigned to auxiliary groups must also be included in the play target
(for example, as members of `walter_vm`) or handled by a separate play.
Services omitted from the placement file are skipped. See
`ansible/examples/service-placement.example.yml` for a generic template.

## Layout

```
ansible/
├── inventory.yml          # walter-vm host (via cloudflared SSH tunnel)
├── ansible.cfg            # defaults
├── walter-vm.yml          # master playbook
├── examples/
│   └── service-placement.example.yml
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

Role steps for the default `present` state (idempotent):
1. Create `/opt/walter-vm/services/<name>/`
2. Rsync everything except `.env` (preserves operator-set values)
3. Copy `.env.template` → `.env` only if `.env` doesn't exist yet
4. `docker compose pull`
5. `docker compose --env-file .env up -d`

Set `service_state` when including the role to reconcile a service lifecycle:

| `service_state` | Behavior |
|---|---|
| `present` (default) | Sync service files, pull images, and run `docker compose up -d` |
| `stopped` | Run `docker compose stop`; containers remain defined |
| `absent` | Run `docker compose down`; containers/networks are removed but the role never removes volumes |

Placement filters only gate the default `present` deployment path. Explicit stopped/absent requests still reconcile an existing service directory, even if the current placement overlay no longer assigns that service to the host.

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
