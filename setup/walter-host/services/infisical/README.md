# Infisical service

App-runtime secrets manager for Walter-OS. Open-source, self-hostable
alternative to HashiCorp Vault. Apps fetch secrets via SDK / CLI at startup.

## URL

`https://secrets.${WALTER_DOMAIN}` (behind Cloudflare Tunnel + Access policy
allowing only `@${WALTER_DOMAIN}` emails).

## Stack

- **infisical-backend** — main API + UI (Node.js)
- **infisical-db** — Postgres 16
- **infisical-redis** — Redis 7

All on internal Docker network `infisical`. Only backend port `8080`
mapped to `127.0.0.1:8800` on the host (cloudflared proxies).

## Persistent secrets

Generated once during deploy, NEVER regenerate without restoring backup:

- `INFISICAL_ENCRYPTION_KEY` (16 hex chars) — encrypts secrets at rest
- `INFISICAL_AUTH_SECRET` (base64) — signs JWTs
- `INFISICAL_DB_PASS` — Postgres user password
- `INFISICAL_REDIS_PASS` — Redis auth password

These live in `~/.config/walter-os/secrets.env` on operator machine and
in `/opt/walter-vm/services/infisical/.env` on the VM (mode 600, root-owned).

## First-run admin signup

1. Open `https://secrets.${WALTER_DOMAIN}/admin/signup` in browser.
2. CF Access challenge → login with `${WALTER_ADMIN_EMAIL}` (Google or OTP-to-email).
3. Create admin account in Infisical UI.
4. Create first organization + project.

## Migration to use

After admin setup:

1. Create projects per app: `myapp-prod`, `myapp-staging`, `walter-os`, etc.
2. Add secrets via UI or CLI: `infisical secrets set ANTHROPIC_API_KEY=...`
3. Apps consume via:
   - **CLI inject**: `infisical run --env=prod --projectId=... -- node app.js`
   - **SDK**: `@infisical/sdk` in Node, `infisical` in Python.
   - **K8s operator** (later): pulls secrets into K8s Secrets.

## Backup

Postgres dump → restic → Drive (Phase K7):

```bash
docker exec infisical-db pg_dump -U infisical infisical | gzip > infisical-backup.sql.gz
```

This file plus `INFISICAL_ENCRYPTION_KEY` is everything needed to restore.

## Update

```bash
cd /opt/walter-vm/services/infisical
docker compose pull
docker compose up -d
```

Migration runs automatically on backend startup (entrypoint runs
`npm run migration:latest` before `node main.mjs`).
