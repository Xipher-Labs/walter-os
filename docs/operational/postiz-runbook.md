# Runbook: Postiz on Walter-VM

> Operational guide for deploying, configuring, and troubleshooting
> Postiz — the social media scheduler in the Walter-OS stack.
> IaC: `setup/walter-host/services/postiz/`. Env template: `setup/walter-host/services/postiz/.env.template`.
>
> Harmonized from feat/social-pipeline branch (2026-05-12).

## What it is

Postiz is an open-source social media management tool (AGPL-3.0). Supports
scheduling and publishing across X, LinkedIn, Instagram, TikTok, YouTube Shorts,
Facebook, Threads, Bluesky, Pinterest, Reddit, Mastodon.

## Where it runs

- **Host**: Walter-VM (or any Linux VPS with Docker Compose).
- **IaC path**: `/opt/walter-vm/services/postiz/` on the VM.
- **Public URL**: `https://postiz.${WALTER_DOMAIN}` (Caddy reverse-proxy or CF Tunnel).
- **Internal port**: `127.0.0.1:5000` → container port 3000.
- **Persistence**: named Docker volumes `postiz_uploads`, `postiz_pg`, `postiz_redis`.

## Deploy (first time)

```bash
# Copy .env.template → .env and fill in secrets
cp setup/walter-host/services/postiz/.env.template /opt/walter-vm/services/postiz/.env
# Edit .env: set POSTIZ_JWT_SECRET, POSTIZ_PG_PASS, WALTER_DOMAIN, etc.

# Bring up
cd /opt/walter-vm/services/postiz
docker compose --env-file .env up -d

# Verify
docker compose ps
curl -s http://localhost:5000/api/health
```

First-run setup:
1. Navigate to `https://postiz.${WALTER_DOMAIN}`.
2. Create the owner account (registration is open only until the first user is created).
3. Add channels.

## Connect channels (manual, one-time per channel)

Postiz needs OAuth credentials for each social platform.

### X (Twitter)
1. https://developer.twitter.com/ → New project → New app.
2. App settings → User authentication → enable OAuth 2.0.
3. Callback URL: `https://postiz.${WALTER_DOMAIN}/integrations/social/x`.
4. Copy Client ID + Client Secret → Postiz: Settings → Channels → X → connect.

### LinkedIn
1. https://www.linkedin.com/developers/apps → Create app.
2. Auth → Redirect URLs: `https://postiz.${WALTER_DOMAIN}/integrations/social/linkedin`.
3. Products → request `Share on LinkedIn` + `Sign In with LinkedIn`.
4. Copy Client ID + Client Secret → Postiz.

### Instagram (Graph API)
1. https://developers.facebook.com/apps → Create app → Business type.
2. Add Instagram Graph API + Facebook Login.
3. Redirect URI: `https://postiz.${WALTER_DOMAIN}/integrations/social/instagram`.
4. Requires a Facebook page connected to the IG business account.
5. Copy App ID + App Secret → Postiz.

### TikTok
1. https://developers.tiktok.com/apps → Create app.
2. Login Kit + Content Posting API.
3. Redirect: `https://postiz.${WALTER_DOMAIN}/integrations/social/tiktok`.
4. Copy Client Key + Client Secret → Postiz.

### YouTube Shorts
1. https://console.cloud.google.com/ → Enable YouTube Data API v3.
2. OAuth consent screen → External, add scopes:
   `youtube.upload`, `youtube.readonly`.
3. Credentials → OAuth client ID → Web app.
4. Redirect: `https://postiz.${WALTER_DOMAIN}/integrations/social/youtube`.
5. Copy Client ID + Client Secret → Postiz.

## Common operations

```bash
# View logs
docker compose -f /opt/walter-vm/services/postiz/docker-compose.yml logs -f --tail=100

# Restart
docker compose -f /opt/walter-vm/services/postiz/docker-compose.yml restart

# Upgrade (bump image tag in compose.yml first)
docker compose pull && docker compose up -d
```

## Troubleshooting

**Posts scheduled but never published**
- Check Postiz queue page — ensure state is "scheduled" not "draft".
- Channel token may have expired. Reconnect in Postiz UI.
- Check container time: `docker exec postiz date` — should be UTC.

**Internal server error on homepage**
- Check Postgres: `docker exec postiz-pg psql -U postiz -c '\l'`
- Check Redis: `docker exec postiz-redis redis-cli ping`
- Verify `JWT_SECRET` is set and non-empty.

**Image upload fails**
- Default limit is 50 MB. Bump `NEXT_PUBLIC_UPLOAD_LIMIT_MB` in env for videos.

## Rotate JWT secret

```bash
# Generate new secret
openssl rand -hex 32

# Stop, update .env, restart
docker compose down
# Edit .env → JWT_SECRET=<new-value>
docker compose up -d
```

Note: all active sessions are invalidated; users must re-login.

## Resources

| Resource | Approx |
|---|---|
| RAM (idle) | ~300-500 MB |
| RAM (under load) | ~700 MB |
| Disk (uploads) | grows with media |
| Disk (Postgres) | ~50 MB/month at moderate usage |

## References

- Postiz repo: https://github.com/gitroomhq/postiz-app
- Postiz docs: https://docs.postiz.com
- Analytics export: `docs/operational/postiz-analytics-export.md`
- SUGGESTIONS.md: `setup/walter-host/services/postiz/SUGGESTIONS.md`
