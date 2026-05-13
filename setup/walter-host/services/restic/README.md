# Walter-VM restic backups

Two-repo strategy:

```
                    ┌─────────────────────────────────────┐
                    │  Walter-VM data                     │
                    │   /var/lib/docker/volumes (services) │
                    │   /opt/walter-vm/services            │
                    │   /etc/{walter-vm,cloudflared,caddy} │
                    │   /home/walter                       │
                    └────────────┬────────────────────────┘
                                 │ restic backup
                                 │ (client-side encrypted, AES-256)
                                 ▼
              ┌──────────────────────────────────────────┐
              │  PRIMARY repo (fast restore)             │
              │  /mnt/walter-vm-data/restic-local        │
              │   (Hetzner Cloud Volume, same DC as VM)  │
              │   ✓ < 1 min restore, ✓ daily snapshots   │
              │   ✗ NOT off-provider                     │
              └────────────┬─────────────────────────────┘
                           │ restic copy (rclone)
                           ▼
              ┌──────────────────────────────────────────┐
              │  SECONDARY repo (real off-site)          │
              │  rclone:gdrive:walter-vm-backup          │
              │   (Google Drive, Google datacenters)     │
              │   ✓ off-provider, ✓ encrypted at rest    │
              │   ✗ slower restore (Drive API rate)      │
              └──────────────────────────────────────────┘
```

## Cost

- Cloud Volume (already provisioned): €4.76/mo for 100 GB
- rclone:gdrive: **€0 marginal** if you already have Drive 100GB+ plan
- Restic: free
- **Total backup-only cost**: €0 marginal

## What gets backed up

```
/var/lib/docker/volumes      # Plane DB, Forgejo, Infisical, n8n, LiteLLM, Kuma, Homepage
/opt/walter-vm/services      # compose.yml + .env per service (encryption keys!)
/etc/walter-vm               # alerting.env, restic.env, infisical creds
/etc/cloudflared             # tunnel cred + config
/etc/letsencrypt             # certs (if any custom)
/etc/caddy                   # reverse-proxy config
/etc/fstab                   # disk mounts
/etc/passwd /etc/group /etc/shadow   # user accounts
/home/walter                 # walter user state (excludes ~/.cache/, node_modules)
```

What's intentionally NOT backed up:
- `/var/log/*` — re-creatable, large
- `*/node_modules/*` — re-creatable
- `*/.cache/*` — re-creatable
- `/tmp/*`
- `/proc /sys /dev` — kernel state

## Schedule

| When | What |
|---|---|
| Daily 02:00 BA | Backup → PRIMARY → mirror to SECONDARY |
| Weekly Sun 03:00 BA | Prune SECONDARY (Drive can drift faster) |
| Monthly 1st 04:00 BA | `restic check --read-data-subset=10%` (integrity verify) |

Retention policy: **7 daily + 4 weekly + 12 monthly = ~23 snapshots steady state**.

## Setup

```bash
# 1. Configure rclone on VM (see RCLONE-SETUP.md, ~10 min)
ssh walter-vm
sudo -u walter rclone config   # create remote 'gdrive'

# 2. Run setup
sudo bash /opt/walter-vm/services/restic/setup.sh

# Setup script:
#   - Generates RESTIC_PASSWORD (you'll see it ONCE — save to 1Password!)
#   - Initializes both repos
#   - Runs initial backup (creates first snapshot)
#   - Installs /etc/cron.d/walter-restic
```

## Restore drill (DO THIS once you set up — never tested = no backup)

```bash
# List snapshots
restic -r /mnt/walter-vm-data/restic-local snapshots

# Restore a single file from latest snapshot
restic -r /mnt/walter-vm-data/restic-local restore latest \
  --include /etc/cloudflared/config.yml \
  --target /tmp/restore-test

diff /tmp/restore-test/etc/cloudflared/config.yml /etc/cloudflared/config.yml
# should be identical

# Restore from SECONDARY (test off-site path works)
restic -r rclone:gdrive:walter-vm-backup restore latest \
  --include /etc/walter-vm/alerting.env \
  --target /tmp/restore-test-remote
```

If both work → backups are verified. Run drill every 90 days minimum.

## Disaster recovery (the real test)

If Walter-VM is destroyed, recover on a new Hetzner VM:

```bash
# 1. Provision new VM (hcloud server create + bootstrap-vm.sh)
# 2. Install restic + rclone
# 3. Configure rclone:gdrive (or service account)
# 4. Restore everything to new VM:
restic -r rclone:gdrive:walter-vm-backup restore latest --target /
# 5. Reboot, services come back up
```

End-to-end DR test once per year is the operational safety bar.

## Monitoring backup health

- Daily backup completion → Telegram bot ping (Tier 2 alerting)
- Backup failure → Telegram alert with log location
- Repo size growth → eventually we add to Grafana dashboard (Phase K4.2)
- Snapshot age (last successful > 36h) → Uptime-Kuma "push" monitor

## Files

- `setup.sh` — one-shot setup + cron install
- `restic-backup.sh` — actual backup logic (daily/weekly/verify modes)
- `RCLONE-SETUP.md` — Google Drive headless OAuth walkthrough

## What this skill / service does NOT cover

- Database-consistent dumps (we back up Postgres files raw — for safer
  point-in-time, add `pg_dump` to a pre-backup hook)
- Live replication (this is restic, not streaming replication)
- Application-level state in cloud services (Vercel, Railway, GitHub) —
  those are separate backup concerns

## References

- https://restic.readthedocs.io/
- https://rclone.org/drive/
- skills/data-migration-safety/ — DB dump + restore patterns
- skills/secrets-yubikey-unlock/ — where RESTIC_PASSWORD belongs in
  Infisical
