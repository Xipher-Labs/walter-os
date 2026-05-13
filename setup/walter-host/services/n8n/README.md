# n8n on Walter-VM

Workflow automation engine. Drives the **Plane → IA → automated build** flow:
new issue → webhook → Claude/GPT plans → operator approves → Claude Code
container executes → PR opened → Telegram bot pings.

## URL

**https://n8n.${WALTER_DOMAIN}** — behind Cloudflare Tunnel + Cloudflare Access
(Google IdP, allow `@${WALTER_DOMAIN}`).

## Stack

- **n8n** 1.65.2 (pinned, not `latest` — predictable)
- **Postgres** 16-alpine (separate from Plane's pg, isolated)
- Persistence via named Docker volumes (`n8n_data`, `n8n_pg`)
- File workspace at `./files` (bind-mounted, included in restic backups)

## Prerequisites

1. cloudflared tunnel running on the VM
2. DNS record: `n8n.${WALTER_DOMAIN}` CNAMEd to the tunnel
3. CF Access policy created for `n8n.${WALTER_DOMAIN}` (Google IdP, @${WALTER_DOMAIN})
4. Walter-VM bootstrap done (`docker`, `docker compose` available)

## Deploy

```bash
# From your Mac (one-shot):
scp -r setup/walter-host/services/n8n walter-vm:/opt/walter-vm/services/
ssh walter-vm 'cd /opt/walter-vm/services/n8n && bash deploy.sh'

# After first run:
# - https://n8n.${WALTER_DOMAIN}/ → CF Access auth → create owner account
# - Save N8N_ENCRYPTION_KEY to Infisical workspace=walter-vm-internal env=prod
```

`deploy.sh` is idempotent — re-running is safe and only reapplies state.

## Persistence

| What | Where | Survives `down` | Survives `down -v` |
|---|---|---|---|
| Workflow definitions | `n8n_pg` (Postgres) | ✅ | ❌ |
| Encrypted credentials | `n8n_data` + `n8n_pg` | ✅ | ❌ |
| Bind-mounted files | `./files/` | ✅ | ✅ |

**Critical**: `N8N_ENCRYPTION_KEY` rotation breaks all stored credentials.
Back it up to Infisical the moment `deploy.sh` runs first time.

## Restic backups

Once Phase K4.1 (restic) lands, backups include:
- `/var/lib/docker/volumes/n8n_*` (Postgres + n8n state)
- `/opt/walter-vm/services/n8n/files/` (workflow file workspace)
- `/opt/walter-vm/services/n8n/.env` (encryption key — restore-critical)

## Workflow templates (Walter-OS opinionated)

These live as JSON exports in `templates/` (TODO — populate as we build):

- **plane-issue-to-spec**: webhook from Plane → Claude via LiteLLM → comment plan
- **plane-comment-to-execute**: comment `/go` → spawn Claude Code container
- **deploy-notify**: GitHub webhook → Telegram bot ping
- **uptime-alert-router**: Uptime-Kuma webhook → Telegram + Slack
- **hackaton-spinup-trigger**: new dir under `Hackatons/*` → invoke discovery

Import via n8n UI: Settings → Import.

## Authentication strategy

We rely on **Cloudflare Access** in front of the tunnel. n8n's basic auth
is disabled (`N8N_BASIC_AUTH_ACTIVE=false`).

If CF Access is removed or you want defense-in-depth:
- Set `N8N_BASIC_AUTH_ACTIVE=true` in `.env`
- Add `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD`
- Restart: `docker compose up -d n8n`

## Webhooks (incoming)

n8n webhook URLs look like:
```
https://n8n.${WALTER_DOMAIN}/webhook/<workflow-id>
```

These need to be **excluded from CF Access** (otherwise external services like
GitHub / Plane can't POST to them — they don't have OAuth tokens). In CF Access:

```
Application: n8n.${WALTER_DOMAIN}
  → Bypass policy
    → Path matches: /webhook/*
```

Each external service still authenticates via its own webhook signature
(GitHub HMAC, Plane bearer token, etc.) — n8n nodes verify those signatures.

## Versioning / upgrades

Pinned to `n8n:1.65.2`. To upgrade:
1. Read the [release notes](https://github.com/n8n-io/n8n/releases) — they
   sometimes have breaking workflow-format changes.
2. Edit `compose.yml` → bump tag.
3. Re-run `deploy.sh`.
4. Verify: `docker logs -f n8n` for migration errors.

## Troubleshooting

### 502 Bad Gateway via Cloudflare
- cloudflared service down: `ssh walter-vm 'sudo systemctl status cloudflared'`
- n8n container down: `ssh walter-vm 'docker ps | grep n8n'`
- Network issue: `ssh walter-vm 'docker logs --tail 30 n8n'`

### Workflows fail with "Encryption key mismatch"
- The `.env` was regenerated but the DB has credentials from an older key.
- Restore the original `N8N_ENCRYPTION_KEY` from Infisical, or re-create
  credentials via the UI (slow but recoverable).

### n8n won't start, complains about Postgres
- `docker logs n8n-pg`
- If volume corrupted: stop, restore from restic, restart.

## Related skills

- `skills/telegram-bot-cli/` — outbound notifications from workflows
- `skills/forgejo-cli` / `vercel-cli` / `railway-cli` — n8n shells out to
  these via Execute Command node
- `skills/secrets-yubikey-unlock/` — n8n credentials sourced from Infisical
  via the dedicated n8n-Infisical credential type
