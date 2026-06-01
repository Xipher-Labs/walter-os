# Authentik service

Optional self-hosted SSO and identity provider for Walter-OS.

Authentik is useful when a Walter-OS install has multiple human users,
multiple internal apps, or a need for central login policy. Solo and personal
installs can keep Authentik disabled and continue using Cloudflare Access,
local admin tokens, or app-native authentication until central SSO is worth the
operational cost.

## Enable

The stack is disabled by default. Start it only when you want the SSO profile:

```bash
cd /opt/walter-vm/services/authentik
cp .env.template .env
openssl rand -base64 60
openssl rand -base64 36
$EDITOR .env
docker compose --profile authentik up -d
```

Every service in `compose.yml` has `profiles: ["authentik"]`, so plain
`docker compose up -d` does not start Authentik.

## Routing

This compose file intentionally publishes no host ports. Route
`https://auth.${WALTER_DOMAIN}` through Caddy or Cloudflare Tunnel to
`http://authentik-server:9000` on the internal Docker network. Keep Cloudflare
Access in front during bootstrap so the first admin setup URL is not reachable
from the public internet without the outer access policy.

Do not add `ports:` unless you are debugging on a private host. If local
debugging is unavoidable, bind to loopback only and remove the mapping before
committing or deploying.

## Initial setup

After the containers are healthy and routing is in place, open:

```text
https://auth.${WALTER_DOMAIN}/if/flow/initial-setup/
```

Create the first admin user, then immediately configure MFA for that account.
Leave local authentik login available as a break-glass path until the first
OIDC integration has been tested.

## OIDC role in Walter-OS

Use Authentik as the OIDC issuer for Walter-OS web apps that support external
identity providers. The typical pattern is:

- Authentik stores users, groups, MFA policy, and OIDC clients.
- Caddy or Cloudflare Access handles edge routing and coarse network access.
- Each app trusts Authentik for login through its own OIDC client.

Prefer per-app OIDC clients with narrow redirect URIs. Do not reuse one client
secret across unrelated Walter-OS services.

## Backup and restore

Back up these named volumes together:

- `authentik-postgresql-data`
- `authentik-data`
- `authentik-certs`
- `authentik-templates`

Also store `AUTHENTIK_SECRET_KEY` and `AUTHENTIK_POSTGRESQL__PASSWORD` in the
operator secret store. A database dump without `AUTHENTIK_SECRET_KEY` is not a
complete restore path.

Create a logical PostgreSQL backup:

```bash
docker compose --profile authentik exec authentik-postgresql \
  pg_dump -U authentik -d authentik -cC > authentik-postgres-backup.sql
```

Restore during a maintenance window:

```bash
docker compose --profile authentik stop authentik-server authentik-worker
docker compose --profile authentik exec -T authentik-postgresql \
  psql -U authentik < authentik-postgres-backup.sql
docker compose --profile authentik up -d
```

Test restores before depending on Authentik for critical services. If Authentik
becomes the only login path and the restore has never been rehearsed, SSO turns
into a single point of failure.

## Upgrade

This profile pins `ghcr.io/goauthentik/server:2026.5.2` and
`docker.io/library/postgres:16-alpine`. Upgrade by reading the official
authentik release notes for the target version, updating both server and worker
tags together, then running:

```bash
docker compose --profile authentik pull
docker compose --profile authentik up -d
```
