# n8n on Walter-VM

Workflow automation engine. Drives the **Plane → IA → automated build** flow:
new issue → webhook → Claude/GPT plans → operator approves → Claude Code
container executes → PR opened → Telegram bot pings.

## URL

**`https://n8n.${WALTER_DOMAIN}`** — behind Cloudflare Tunnel + Cloudflare Access
(Google IdP, allow `@${WALTER_DOMAIN}`).

## Stack

- **n8n** 2.18.7 (pinned, not `latest` — predictable)
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

## Authentication strategy — two layers (audit P1-03 closed)

The compose ships **two independent auth layers**. Both must pass before
a request reaches the workflow editor or the credential vault:

```
Internet
   │
   ▼
Cloudflare Access (perimeter)
   • Google IdP, allow @${WALTER_DOMAIN}
   │  (passes only authed identities)
   ▼
Cloudflare Tunnel → 127.0.0.1:5678
   │
   ▼
n8n basic auth (defense in depth)
   • N8N_BASIC_AUTH_USER
   • N8N_BASIC_AUTH_PASSWORD
   │  (passes only with valid basic creds)
   ▼
n8n editor + credential vault
```

### Why both layers

n8n has direct Postgres credentials, Execute Command nodes, and access
to every credential the operator has saved. A single-layer setup with
only CF Access at the perimeter is one misconfig away from full
exposure:

- **CF Access misconfig** — wrong allow rule, expired identity-provider
  binding, or a paused application.
- **Tunnel bypass** — if the firewall ever stops blocking direct
  Walter-VM access on port 5678 (regression in `ufw` rule, debug shell
  that opens it temporarily, etc.).
- **cloudflared CVE** — a vulnerability that bypasses Access enforcement.
- **Subdomain takeover** — DNS pointed at an unhealthy tunnel that
  silently re-maps.

n8n basic auth catches every one of those.

### Operator setup

1. Add the two basic-auth secrets to Infisical:

   ```bash
   infisical secrets set N8N_BASIC_AUTH_USER='walter-admin'
   infisical secrets set N8N_BASIC_AUTH_PASSWORD="$(openssl rand -base64 24)"
   ```

   `N8N_BASIC_AUTH_USER` can be anything memorable; the password should
   be **24+ random characters** (the example above gives 32). Save both
   in your password manager.

2. Write them into the service's local `.env` file. The deploy flow
   (`deploy.sh`) generates `/opt/walter-vm/services/n8n/.env` on first
   run from `.env.template`; either edit the generated file directly
   or pull-and-render via your secrets manager.

   ```bash
   # Option A — Infisical CLI writes the .env directly:
   cd /opt/walter-vm/services/n8n
   infisical export --env=prod --format=dotenv >> .env

   # Option B — append manually (use ONLY for testing):
   echo "N8N_BASIC_AUTH_USER=walter-admin" >> .env
   echo "N8N_BASIC_AUTH_PASSWORD=<paste-from-password-manager>" >> .env
   ```

   Note: `walter-os secrets-pull` is the DEPRECATED Bitwarden/
   Vaultwarden bridge (see `bin/walter-os`) and does NOT sync from
   Infisical, so it is NOT the right command for this flow.

3. Restart n8n to pick up the new env (compose reads `.env` via
   `--env-file .env` per `deploy.sh`):

   ```bash
   cd setup/walter-host/services/n8n
   docker compose --env-file .env up -d
   ```

4. The first browser hit will prompt for basic-auth credentials AFTER
   CF Access succeeds.

If either env var is missing at boot, the compose **fails with a clear
error** (`N8N_BASIC_AUTH_USER required …`) thanks to the `${VAR:?msg}`
substitution. This is deliberate — it prevents the
"silent fallback to `N8N_BASIC_AUTH_ACTIVE: false`" anti-pattern that
caused audit P1-03 in the first place.

### Why not n8n user management instead

n8n's built-in multi-user management is richer (per-user permissions,
SSO, etc.) but it requires running in a multi-tenant mode that adds
attack surface and complicates upgrades. For a solo-operator or small-
team self-host, basic auth is the simpler, smaller surface.

If you DO want full user management, leave
`N8N_USER_MANAGEMENT_DISABLED: "false"` (already the default) and
follow <https://docs.n8n.io/user-management/>. Basic auth can coexist
as a third layer.

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

### Plane PR sync adapters

For the Plane ↔ Forgejo PR lifecycle, call Walter-OS adapters from Execute
Command nodes instead of assembling shell commands from raw webhook JSON.

Use `plane-pr-sync-trigger.sh` for trusted internal workflows where n8n already
knows the Plane issue ID:

```bash
scripts/agents/plane-pr-sync-trigger.sh \
  --event pull_request \
  --issue "$PLANE_ISSUE_ID" \
  --payload-file "$FORGEJO_PAYLOAD_JSON"
```

The adapter validates the payload shape, rejects unsupported events/actions,
rejects newline-bearing fields, and calls `plane-pr-sync.sh` using argv arrays.
It maps opened/reopened/synchronized PRs to `link`, merged PR closures to
`merged`, and closed-unmerged PRs to no-op.

Use `plane-pr-sync-webhook.sh` for public Forgejo/Gitea merge webhooks. n8n
must preserve the original raw request body and pass the signature header
through unchanged; do not JSON re-serialize the body before verification:

```bash
scripts/agents/plane-pr-sync-webhook.sh \
  --event "$FORGEJO_EVENT" \
  --signature "$FORGEJO_SIGNATURE" \
  --payload-file "$RAW_FORGEJO_PAYLOAD"
```

Map `FORGEJO_EVENT` from `X-Gitea-Event` or `X-Forgejo-Event`. Map
`FORGEJO_SIGNATURE` from `X-Gitea-Signature` or `X-Forgejo-Signature`. Store the
shared secret in n8n/Infisical as `WALTER_FORGEJO_WEBHOOK_SECRET`; the adapter
reads the secret from the environment and never from argv.

Set `WALTER_FORGEJO_WEBHOOK_REPOS` to the comma-separated `owner/repo` names
accepted by that webhook secret, for example:

```bash
export WALTER_FORGEJO_WEBHOOK_REPOS="Xipher-Labs/walter-os"
```

The allowlist is mandatory. A signed payload from any repo outside the allowlist
fails closed before comment fetches or Plane mutation.

Set `WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS` to the comma-separated Forgejo/Gitea
logins whose PR comments may bind Plane issues, for example:

```bash
export WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS="walter-bot"
```

This should be the automation account used by `plane-pr-sync.sh link`. Markers
from other comment authors are ignored.

`plane-pr-sync-webhook.sh` verifies HMAC-SHA256 over the raw payload before JSON
parsing, comment fetches, or Plane/Forgejo mutation. It only acts on
`pull_request.closed` events with `merged == true`; closed-unmerged PRs are
no-op. For merged PRs it resolves exactly one `walter-plane-issue:<id>` marker
from trusted Forgejo comment bodies, then calls `plane-pr-sync.sh` with argv
arrays. Repeated copies of the same marker are accepted for webhook redelivery;
missing markers or multiple distinct markers fail closed. PR title/body text is
not a marker source.

`plane-pr-sync.sh link` writes the stable marker into Forgejo comments before it
moves Plane to review. If `tea` is missing, comment inspection fails, or the
marker comment cannot be written, link fails closed instead of leaving a Plane
issue in review without a trusted PR binding. Public merge webhooks should
depend on that marker, not on arbitrary PR body text. When
`WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS` contains a non-empty comma-separated
list, existing markers from other authors do not satisfy the link-stage binding
check.

Neither adapter is a public HTTP listener. The full n8n workflow JSON remains
out of scope until the CLI adapters are proven in operator use.

## Versioning / upgrades

Pinned to `n8n:2.18.7`. To upgrade:
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
