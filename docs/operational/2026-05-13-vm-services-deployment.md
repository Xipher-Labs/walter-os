# Walter-VM services deployment — 2026-05-13

Session goal: deploy Control Tower, Metabase, Postiz, Hermes Agent; tighten CF Access; retire Vaultwarden.

## What landed (verified)

### Infrastructure (Phase 1)
- **CF Access apps**: added `matrix`, `posthog`, `tower`, `metabase`, `postiz`, `hermes` (24 total apps on `*.xipherlabs.xyz`). Deleted `vault` app (Vaultwarden retired — Infisical is the secret store).
- **Cloudflared tunnel**: 4 new ingress rules (tower→3050, metabase→3051, postiz→5000, hermes→9119). Removed `vault.xipherlabs.xyz → 127.0.0.1:8222`.
- **CF DNS**: 4 new proxied CNAMEs (`{tower,metabase,postiz,hermes}.xipherlabs.xyz → <tunnel-id>.cfargotunnel.com`).
- **Homepage YAML**: added Hermes + OpenClaw entries under "Agents & AI"; uncommented Communications (RocketChat, Element) and Design (Penpot, Drawio) sections; reflects what's actually running on the VM.

### Services (Phase 3)
- **Metabase** ✅ deployed on walter-vm. 3 containers (metabase, metabase-pg, social-pg) + sidecar. Healthy, `127.0.0.1:3051/api/health` returns 200, public URL `https://metabase.xipherlabs.xyz` returns 302 (Access intercept). First-time wizard at the URL once operator logs in via CF Access.
- **Infisical sidecar pattern**: `walter-vm-internal/prod/metabase` folder has 3 secrets (`METABASE_DB_PASS`, `SOCIAL_PG_PASS`, `METABASE_ENCRYPTION_KEY`), all generated.

## Deferred (deploy runbooks below)

### Postiz — deferred (needs Temporal addon)
Root cause: Postiz v2.21.x requires a Temporal server (`temporal:7233`) for job orchestration. The standalone compose at `setup/walter-host/services/postiz/compose.yml` predates this dependency; my deploy attempt crashed with `Backend failed to start on port 3000` after `ECONNREFUSED ::1:7233`.

**Runbook to complete the deploy**:
1. Add Temporal mini-stack (`temporalio/auto-setup:1.26.2` + `temporalio/ui:2.47.2`) to `setup/walter-host/services/postiz/compose.yml`. Pattern available in `setup/walter-host/services/posthog/compose.yml` lines that show posthog-temporal-1 setup.
2. Add Temporal connection env vars to the postiz service: `TEMPORAL_HOST=temporal`, `TEMPORAL_PORT=7233`.
3. Push generated secrets to Infisical: `POSTIZ_PG_PASS`, `POSTIZ_JWT_SECRET` already in `walter-vm-internal/prod/postiz` (no-op).
4. Deploy + verify per the metabase pattern.

Per-platform OAuth client IDs/secrets (X, LinkedIn, YouTube, etc.) are added by the operator via the Postiz admin UI post-first-login. They live in `postiz-pg`, not env.

### Hermes Agent — deferred (CLI-first image, needs dashboard-server mode investigation)
Root cause: `nousresearch/hermes-agent:v2026.5.7` boots an interactive CLI (`/opt/hermes/.venv/bin/hermes`) that exits cleanly when stdin is not a TTY. The container's `entrypoint.sh` does start `hermes dashboard` as a BACKGROUND process when `HERMES_DASHBOARD=1`, but the foreground `hermes` exit kills the container, taking the dashboard with it.

**Runbook to complete the deploy**:
1. Override `command:` to `["dashboard", "--port", "9119", "--host", "0.0.0.0"]` (so the dashboard runs as the foreground process instead of as a background sidecar).
2. Or use `command: ["sleep", "infinity"]` — but then `hermes dashboard` runs in the background and the container stays up. Less elegant.
3. Verify with `docker logs hermes-agent` that the dashboard is serving on `:9119` after boot.
4. Operator action: mint a real LiteLLM virtual key from `https://llm.xipherlabs.xyz` → Virtual Keys → Create Key named `hermes-agent`. Update Infisical at `walter-vm-internal/prod/hermes/LITELLM_HERMES_KEY` (currently a placeholder string).

Optional follow-up: read `setup/walter-host/services/hermes-agent/SUGGESTIONS.md` for Telegram / Discord / Slack bot integration (each adds its own bot-token secret).

### Control Tower — deferred (image not on registry + operator-provided tokens)
Root cause: `apps/control-tower/Dockerfile` exists but `walter-control-tower:<tag>` is not pushed to any registry. Image must be built locally.

**Runbook to complete the deploy**:
1. **Build the image**, either locally and `docker save` + `docker load` to the VM, OR push to a registry (Forgejo at `git.xipherlabs.xyz` has a container registry):
   ```bash
   cd /Users/nico/Projects-personal/walter-os
   docker build -t walter-control-tower:v0.2.0 -f apps/control-tower/Dockerfile .
   docker save walter-control-tower:v0.2.0 | ssh walter-vm "sudo docker load"
   ```
2. **Mint operator tokens** (3 of them):
   - LiteLLM virtual key named `control-tower` from `https://llm.xipherlabs.xyz` → push to `walter-vm-internal/prod/tower/LITELLM_API_KEY`.
   - Plane API token: log in to `https://plane.xipherlabs.xyz` → Profile → API Tokens → Create → push to `walter-vm-internal/prod/tower/PLANE_API_TOKEN`. Also note the workspace slug and the project ID (these are CONFIG, not secrets — set in compose env).
   - Grafana service account token: `https://grafana.xipherlabs.xyz` → Administration → Service accounts → Add → Token → push to `walter-vm-internal/prod/tower/GRAFANA_SA_TOKEN`. Role: Viewer is sufficient.
3. Deploy per the metabase pattern. Standalone compose at `setup/walter-host/services/control-tower/compose.yml` is the template — wrap with Infisical sidecar + override port to `3050` (avoids `3000` = forgejo).
4. Override `TAILSCALE_ENFORCE: "false"` (CF Access fronts it; Tailscale enforcement at the app layer is redundant and adds confusion).
5. Verify dashboard at `https://tower.xipherlabs.xyz`.

## Operator action items

Today (no urgency):
1. **Mint 3 tokens for Control Tower** when you're ready to deploy it (Plane API, Grafana SA, LiteLLM virtual key).
2. **Mint 1 LiteLLM key for Hermes** before deploying.
3. **Rotate creds you pasted in chat** during this session (Gemini key, Grafana pw) — already in Infisical, but the chat transcript persists.

This week:
4. **Postiz Temporal stack** if you want to deploy social scheduling. Lower urgency since Postiz isn't on the critical path.

## Final state verification

```bash
# Public URLs (all should return 302 — CF Access redirect to login):
for h in metabase tower postiz hermes; do
  echo "https://${h}.xipherlabs.xyz → $(curl -sf -o /dev/null -m 5 -w '%{http_code}' https://${h}.xipherlabs.xyz)"
done
# expected: 302 each (metabase: backend up; tower/postiz/hermes: backend not deployed yet,
# but CF Access still intercepts — operator sees the login page, then a 502/connection
# refused after auth until the backend is deployed).

# Homepage at https://home.xipherlabs.xyz shows: 16 services with valid links;
# 4 of those (tower, postiz, hermes, tower again under Agents & AI) point at
# subdomains where the backend isn't running YET — broken-link state by design,
# resolved as each runbook above is executed.
```

## Files touched in this PR (repo side)

- `setup/walter-host/cloudflare/04-create-access.sh` — added `matrix posthog tower metabase postiz hermes` to the sub list; removed `vault`.
- `setup/walter-host/cloudflare/cloudflared-config.yml` — NEW, declarative source-of-truth for tunnel ingress (mirrors `/etc/cloudflared/config.yml` on walter-vm). Update here then `rsync` to the VM.
- `setup/walter-host/services/metabase/compose.vm.yml` — NEW, walter-vm variant with Infisical sidecar wrapping. The original `compose.yml` stays as the all-in-one variant (root `compose.yml` consumer).
- `setup/homepage/config/services.yaml` — added Hermes + OpenClaw; uncommented Communications + Design sections.
- This file.

## IaC source-of-truth map (post-handoff)

| Artifact | Repo path | Live location | Reconciliation |
|---|---|---|---|
| Tunnel ingress | `setup/walter-host/cloudflare/cloudflared-config.yml` | `/etc/cloudflared/config.yml` | manual rsync + `systemctl restart cloudflared` |
| CF Access apps | `setup/walter-host/cloudflare/04-create-access.sh` | CF dashboard | re-run script (idempotent) |
| CF DNS records | none (CF API direct) | CF dashboard | `cloudflared tunnel route dns` OR CF API |
| Service composes (VM) | `setup/walter-host/services/<svc>/compose.vm.yml` (sidecar variant) | `/opt/walter-vm/services/<svc>/compose.yml` | manual scp + `docker compose up -d` |
| Infisical secrets | none (Infisical UI / CLI) | Infisical workspace | declarative via Infisical's own audit log; deploy script asserts presence at boot |
| Homepage YAML | `setup/homepage/config/services.yaml` | `/opt/walter-vm/services/homepage/config/services.yaml` | manual scp + `docker restart homepage` |

**Convention going forward**:
- Anything declarative AND repeatable lives in the repo.
- State-ful items (secrets, DB rows, CF DNS records that target a tunnel id) are intentionally NOT in IaC — they're either operator-managed or persistence-managed.
- The 04-create-access.sh + cloudflared-config.yml pair is the closest thing to a single-source-of-truth for the public surface. Update both when adding/removing services.

## Login-policy bug fix — 2026-05-16 (post-merge)

Initial CF Access script run used `AUTH_DOMAIN=xipherlabs.xyz` which set every policy to `allow @xipherlabs.xyz`. Operator's email is `@solx.ar`, so every login attempted with `nico@solx.ar` returned "That account does not have access".

Fix: re-ran `bash setup/walter-host/cloudflare/04-create-access.sh xipherlabs.xyz solx.ar otp+google`. All 24 apps now have `allow @solx.ar`. Login restored.

Lesson: AUTH_DOMAIN is the operator-email domain, NOT the service domain. The script header documents this; I misread the arg meaning on first invocation.
