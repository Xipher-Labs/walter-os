# Listmonk on Walter-VM

Optional self-hosted newsletter and mailing-list manager for devrel work: release notes, product updates, private beta cohorts, launch follow-ups, event lists, and transactional email experiments that should not live inside the social scheduler.

Listmonk is intentionally outside the default Walter-VM stack. It stores subscriber data, sends email, and has compliance obligations, so operators should only enable it when they have a real newsletter/devrel workflow and an SMTP provider ready.

## URL

`https://listmonk.${WALTER_DOMAIN}`

Do not expose Listmonk with a public Docker host port. Attach the service to `walter_net` and add a Caddy route:

```caddy
listmonk.{$WALTER_DOMAIN} {
  import admin_auth_gate
  reverse_proxy listmonk:9000
}
```

Public subscription, link tracking, campaign pixel, and upload routes may need a narrower public-bypass policy if you use Cloudflare Access. Keep the admin UI and `/api/*` behind operator authentication.

## Stack

- Listmonk `listmonk/listmonk:v6.1.0`, pinned exactly.
- Dedicated Postgres `postgres:17-alpine`.
- Named volumes: `listmonk_pg` for the database and `listmonk_uploads` for media uploads.
- Docker Compose profile: `listmonk`, disabled unless explicitly requested.

Official Listmonk Docker guidance uses Compose, Postgres, `LISTMONK_*` environment configuration, and the install/upgrade/start command sequence. This profile follows that shape while removing public host ports and requiring credentials at compose-render time.

## Configure

```bash
cd /opt/walter-vm/services/listmonk
cp .env.template .env
$EDITOR .env
```

Fill:

- `WALTER_DOMAIN`
- `LISTMONK_POSTGRES_PASSWORD`
- `LISTMONK_ADMIN_USER`
- `LISTMONK_ADMIN_PASSWORD`

Generate random passwords with:

```bash
openssl rand -base64 32
```

The compose file uses `${VAR:?required ...}` for the database password and first-boot admin credentials. Missing values stop startup instead of creating an exposed instance with defaults.

## Start

```bash
docker compose --env-file .env --profile listmonk up -d
docker compose --env-file .env --profile listmonk ps
docker compose --env-file .env --profile listmonk logs -f listmonk
```

Then open `https://listmonk.${WALTER_DOMAIN}` through Caddy.

## SMTP dependency

Listmonk will not send campaigns until SMTP is configured in the admin settings. Use a provider that supports your domain's SPF, DKIM, DMARC, bounce handling, and sending limits. Do a small internal test list before importing external contacts.

Some hosts block outbound SMTP ports such as 25 and 465. If delivery fails, check the provider port, firewall, and host network policy before debugging Listmonk itself.

## Unsubscribe and compliance caveat

Newsletter use is regulated. Before sending to real subscribers, verify consent source, sender identity, physical mailing-address requirements for your jurisdiction, unsubscribe links, bounce handling, and retention/deletion process.

Listmonk provides subscription and unsubscribe flows, but the operator is still responsible for lawful list import, campaign copy, and honoring opt-outs. Do not import scraped contacts.

## Backups

Back up both named volumes before upgrades or campaign imports:

```bash
docker run --rm \
  -v listmonk_listmonk_pg:/var/lib/postgresql/data:ro \
  -v "$PWD:/backup" \
  alpine tar -czf /backup/listmonk-pg-volume.tgz /var/lib/postgresql/data

docker run --rm \
  -v listmonk_listmonk_uploads:/listmonk/uploads:ro \
  -v "$PWD:/backup" \
  alpine tar -czf /backup/listmonk-uploads-volume.tgz /listmonk/uploads
```

If you use a custom Compose project name, confirm the actual volume names with
`docker volume ls | grep listmonk` and adjust the `-v` arguments before running
the backup commands.

For cleaner database restores, also schedule a logical `pg_dump` from the `listmonk-db` container and include `.env` in the VM's encrypted restic set.

## Upgrade

1. Read the official Listmonk release notes.
2. Back up Postgres and uploads.
3. Change the pinned image tag in `compose.yml`.
4. Run:

   ```bash
   docker compose --env-file .env --profile listmonk pull
   docker compose --env-file .env --profile listmonk up -d
   docker compose --env-file .env --profile listmonk logs -f listmonk
   ```

The app command runs Listmonk's idempotent install and upgrade steps before starting the server.
