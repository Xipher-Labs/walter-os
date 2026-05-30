# Troubleshooting — common operational issues

Symptom → cause → fix for the 20 most common Walter-OS friction points.
This page is searched-against by the daily audit + linked from per-service
error messages. Add a row whenever an operator hits something not already
listed.

| Symptom | Cause | Fix |
|---|---|---|
| Postiz fails to start / exits immediately | `POSTIZ_PG_PASS` unset or contains special characters (e.g., `@`, `#`) | Regenerate: `openssl rand -hex 16`; update in `.env.local`; `docker compose restart postiz` |
| PostHog OOM at container startup | ClickHouse requires `ulimit -n 262144`; 32 GB RAM minimum | `ulimit -n 262144` before compose; add to `/etc/security/limits.conf` for persistence: `* soft nofile 262144` and `* hard nofile 262144` |
| Control Tower image not found / compose fails with "pull access denied" | Image not built yet (`walter-control-tower:latest` is a local image) | `docker build -f apps/control-tower/Dockerfile -t walter-control-tower:latest .` |
| Cloudflare Tunnel cert error / CERT_INVALID in browser | Stale or rotated tunnel token | Re-run `./setup/walter-host/cloudflare/02-create-tunnel.sh`; update `CLOUDFLARE_TUNNEL_TOKEN` in `.env.local`; `docker compose restart cloudflared` |
| ClickHouse won't start / segfault at startup | `nofile` ulimit too low (kernel default is 1024; ClickHouse requires 262144) | See [`known-issues.md`](known-issues.md) for the exact `/etc/security/limits.conf` entries; requires VM reboot or session restart |
| `git submodule update` fails with "fatal: reference is not a tree" | Upstream repo has force-pushed past the pinned commit | Check `.gitmodules` comments for recovery hash; run `git submodule update --init --force` |
| Walter-Bridge (LiteLLM) returns 401 Unauthorized | `LITELLM_MASTER_KEY` in `.env.local` does not match what the container was started with, or the key has been rotated | `docker compose down litellm && docker compose up -d litellm` after correcting the key; verify with `curl -H "Authorization: Bearer $KEY" https://bridge.your-domain/health` |
| Element won't complete login to Synapse ("Homeserver not found") | `element/config.json` was not rendered from the template during deploy | Re-run `./setup/walter-host/services/synapse/deploy.sh` which renders the template with your domain; restart synapse and element |
| Plane API returns 403 on all agent calls | Plane API token expired or not created | Plane UI → Profile → API Tokens → create new token; update `PLANE_API_TOKEN` in `.env.local` and in Infisical |
| Grafana dashboards show "No data" | Node Exporter not scraping, or Prometheus datasource URL misconfigured | Check `curl localhost:9090/targets` on the VM; verify `prometheus.yml` scrape interval and target IPs; confirm Node Exporter container is running |
| Forgejo SSH clone returns "Permission denied (publickey)" | SSH public key not added to Forgejo account | Forgejo UI → Settings → SSH / GPG Keys → "Add Key" → paste `~/.ssh/id_ed25519.pub` |
| Headscale node enrollment fails ("invalid auth key") | Preauth key has expired (default 1-hour TTL) | Generate a fresh key: `docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 24h` |
| n8n workflow import fails ("version mismatch") | Exported workflow JSON was created with a newer n8n version than your running instance | Upgrade n8n: update the image tag in `setup/walter-host/services/n8n/compose.yml`; `docker compose pull n8n && docker compose up -d n8n` |
| RocketChat admin wizard loops / won't complete | Browser cookie issue after a failed first-run attempt | Clear site data for the RocketChat URL (`chrome://settings/siteData`), then retry in a fresh browser session |
| Metabase "Database connection failed" on first setup | Postgres container not reachable from Metabase by hostname | Verify both services share a Docker network; check: `docker network inspect analytics_net`; ensure Metabase's `MB_DB_HOST` matches the Postgres container name |
| Syncthing "Out of sync" for agent-memory folder | Conflicting edits from two machines simultaneously | Syncthing creates conflict files (`.sync-conflict-*`); keep the newer-timestamp version; delete conflict files; press "Rescan" in Syncthing UI |
| Infisical "Organization not found" on first login | Machine Identity not created; `INFISICAL_TOKEN` is blank or invalid | Infisical UI → Organization → Machine Identities → create identity; export token; set `INFISICAL_TOKEN` in `.env.local` |
| `docker compose up` fails: "network not found" | Docker networks were deleted or never created | `docker compose down --remove-orphans` then `./scripts/bootstrap.sh` then `docker compose up -d` |
| LiteLLM model alias returns "LLM Provider NOT provided" | Model alias not configured in `config.yaml` | Add the alias under `model_list` in `setup/walter-host/services/litellm/config.yaml`; `docker compose restart litellm` |
| Caddy certificate issuance fails / "ACME error: connection refused" | Port 80 blocked by VM firewall (required for ACME HTTP-01 challenge) | Open port 80 temporarily: `ufw allow 80/tcp`; allow 60s for Caddy to obtain certs; can close port 80 again after initial issuance if using CF Tunnel mode |
| Postiz social accounts won't authorize (OAuth redirect error) | `POSTIZ_BACKEND_URL` does not match the exact registered redirect URI in your OAuth app settings | Update `POSTIZ_BACKEND_URL` in `.env.local` to match exactly; regenerate OAuth app credentials if redirect URIs were changed |
| OpenClaw returns "model not found" | OpenClaw is configured to use a LiteLLM alias that no longer exists | Check `OPENCLAW_MODEL` in `.env.local`; verify the model alias exists in `config.yaml`; default should be `litellm/sonnet` with `OPENCLAW_BASE_URL=http://litellm:4000` |
| `walter-os egress test <host>` says denied but the host is in the file | The hook reads from `$WALTER_CONFIG/egress-allowlist.txt`; if you've exported a custom `WALTER_CONFIG`, make sure your shell + Claude Code see the same value | `walter-os egress list` prints the resolved path; compare against `echo $WALTER_CONFIG` in both shells |
| `install.sh --uninstall` says "no backup to restore" but I had pre-Walter-OS files | The backup naming pre-v0.5.1 used `.pre-walter-os.<unix-timestamp>`; the new code looks for ISO-8601 form first. Old backups still work but may not be detected | Manually `ls -la ~/.claude/CLAUDE.md.pre-walter-os.*` to find the oldest by mtime, then `mv` it into place |

## Per-service runbooks

- [`control-tower-runbook.md`](control-tower-runbook.md) — CT-specific
- [`postiz-runbook.md`](postiz-runbook.md) — Postiz-specific
- [`council-v2-deployment-runbook.md`](council-v2-deployment-runbook.md) — Council deploy
- [`known-issues.md`](known-issues.md) — tracked issues that aren't quick fixes

## Reporting new issues

If you hit something not in this table, please open a GitHub issue with:

1. Exact symptom (error message + paste verbatim if possible)
2. The command that triggered it
3. Output of `walter-os doctor` and `walter-os audit` (redacted of secrets)
4. Your platform (macOS ARM / Ubuntu 24.04 / etc.) + Docker version

The maintainer (or another operator who's hit it) will reply with a fix
and a row gets added here.
