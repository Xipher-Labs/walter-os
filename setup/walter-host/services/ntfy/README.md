# ntfy on Walter-VM

ntfy is an optional self-hosted notification service for alerts that should reach a phone without tying the whole stack to Telegram, Slack, or email.

It is disabled by default. Start it only when you want a dedicated push channel for Walter-VM alerts:

```bash
docker compose --profile notifications up -d
```

The `ntfy` profile name remains as a service-specific alias; use
`notifications` for Walter-OS-wide verification commands.

## What it is for

- Uptime and service health alerts from Uptime Kuma, Grafana, cron jobs, and watchdog scripts.
- Human-actionable automation alerts, such as failed backups or stalled deploys.
- Low-friction notifications from local scripts with `curl` or webhook actions.

It is optional because many operators already use Telegram, email, Slack, or mobile OS notifications from another service. Keeping ntfy behind an explicit Compose profile avoids another internet-facing endpoint, another mobile app dependency, and another database to back up unless it is actually useful.

## Files

- `compose.yml` defines the optional `ntfy` profile and publishes no host ports.
- `.env.template` is copied to `.env` for local environment values.
- `server.yml.template` is copied to `server.yml`, edited, and mounted into `/etc/ntfy/server.yml`.

The Docker image does not ship a usable `/etc/ntfy/server.yml` in the container. Create it from the template before first boot:

```bash
cp .env.template .env
cp server.yml.template server.yml
sed -i.bak 's/\${WALTER_DOMAIN}/example.com/g' server.yml
docker network create ntfy_net 2>/dev/null || true
```

Replace `example.com` with the real `WALTER_DOMAIN`. For this example, the
resulting `base-url` should be:

```yaml
base-url: "https://ntfy.example.com"
```

## Security defaults

The template starts with:

```yaml
auth-default-access: deny-all
```

Create explicit users and topic permissions after first boot:

```bash
docker compose --profile notifications exec ntfy ntfy user add walter
docker compose --profile notifications exec ntfy ntfy access walter alerts rw
docker compose --profile notifications exec ntfy ntfy access walter backups rw
```

Use separate topics for different alert classes, for example `alerts`, `backups`, `deploys`, and `security`. Grant read/write narrowly. Do not rely on obscure topic names as the only control.

## Caddy route

Do not add a public host port to this Compose file. Route `https://ntfy.${WALTER_DOMAIN}` through Caddy or the existing tunnel layer to the container on port `80`.

A Caddy route should proxy both normal HTTP requests and websocket upgrade traffic. ntfy clients use long-lived connections for realtime delivery, so keep proxy buffering off or minimal, preserve `Host`, and pass the standard upgrade headers. If Caddy runs outside this Compose project, attach it to the `ntfy_net` Docker network or route through a local private bridge rather than publishing `0.0.0.0:80`.

## Mobile and iOS push tradeoffs

The Android app can talk directly to a self-hosted ntfy server for push-style notifications.

iOS push has a platform tradeoff: Apple's push system requires the official ntfy app's upstream push relay for background delivery. A self-hosted server can still be used from iOS, but fully private background push is constrained by APNs. Decide whether that relay is acceptable for your alert sensitivity. For high-sensitivity alerts, prefer topics that contain no secret material and require opening the protected Walter service for details.

## Backups

Back up both named Docker volumes:

- `ntfy_data` stores the auth database at `/var/lib/ntfy/user.db`.
- `ntfy_cache` stores cached messages and attachment cache data under `/var/cache/ntfy`.

Also back up the profile-local `server.yml` and `.env` files from the host. Restores need the config file plus both volumes to preserve users, permissions, cached messages, and attachments.

## Operations

Start or update:

```bash
docker compose --profile notifications up -d
```

Check logs:

```bash
docker compose --profile notifications logs -f ntfy
```

Send a test notification after creating a user and topic. Set `NTFY_PASSWORD`
in your shell first:

```bash
curl -u "walter:${NTFY_PASSWORD}" "https://ntfy.${WALTER_DOMAIN}/alerts" \
  -H "Title: Walter test" \
  -d "ntfy profile is reachable"
```
