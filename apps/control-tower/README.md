# Walter Council Control Tower

Next.js app that ships with Walter-OS to manage the Walter Council from a
single dashboard: live agent state (SSE), mode toggle, Plane backlog,
Grafana metrics, LiteLLM spend, consensus timeline. Deployed inside the
Walter-VM and reached over Tailscale only.

## Local development

```bash
pnpm install
pnpm dev
```

Open <http://localhost:3000>. Set `CONTROL_TOWER_AUTH_DISABLED=true` (only
honoured outside `NODE_ENV=production`) to skip the admin-token gate while
iterating on UI.

## Production deployment

The container is built from `Dockerfile` (multi-stage, Next.js standalone)
and wired into `compose.yml` at the repo root under the `tier4` profile.
For the standalone reference deployment, see
[`setup/walter-host/services/control-tower/compose.yml`](../../setup/walter-host/services/control-tower/compose.yml).

### Behind a reverse proxy (Cloudflare Tunnel, Tailscale Serve, Caddy)

The standalone server binds to `HOSTNAME=0.0.0.0` so the container can
accept forwarded traffic from any interface. As a side effect, the URL
the Next.js runtime sees in `request.url` is `http://0.0.0.0:3000/...`,
which the browser refuses to follow when it appears in a `Location`
redirect header.

Control Tower compensates by consulting the canonical public URL in this
priority order (see [`lib/canonical-url.ts`](./lib/canonical-url.ts)):

1. `CONTROL_TOWER_PUBLIC_URL` env var — **recommended for production**.
   Set it to the externally-reachable origin
   (`https://tower.${WALTER_DOMAIN}`) so redirects are deterministic
   regardless of the proxy chain.
2. `X-Forwarded-Host` + `X-Forwarded-Proto` headers — both Cloudflare
   Tunnel and Tailscale Serve set these reliably.
3. The `Host` header (when it is not the bind-only `0.0.0.0`).
4. The framework-provided URL — last-resort fallback.

If neither (1) nor (2) is available (Control Tower exposed directly with
no proxy), browsers will not be able to follow login redirects. Setting
`CONTROL_TOWER_PUBLIC_URL` also closes an open-redirect risk: without it,
an attacker who can inject `X-Forwarded-Host` into the request could trick
the login flow into redirecting to a hostile origin. **Always set
`CONTROL_TOWER_PUBLIC_URL` in production.**

## Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `CONTROL_TOWER_ADMIN_TOKEN` | yes (prod) | Bearer / cookie token gate for the dashboard. The container refuses to serve traffic without it. |
| `CONTROL_TOWER_PUBLIC_URL` | recommended | External base URL the browser uses. Example: `https://tower.xipherlabs.xyz`. Closes the 0.0.0.0 redirect bug and prevents X-Forwarded-Host spoofing. |
| `CONTROL_TOWER_AUTH_DISABLED` | no | Skip the token gate. Only honoured when `NODE_ENV != production`. |
| `TAILSCALE_ENFORCE` | no (default `true`) | When `true`, reject requests whose client IP is not in `TAILSCALE_CGNAT_CIDR`. |
| `TAILSCALE_CGNAT_CIDR` | no (default `100.64.0.0/10`) | Tailnet CGNAT range. Override only if you run a custom Headscale topology. |
| `LITELLM_BASE_URL`, `LITELLM_API_KEY` | per-tile | LiteLLM gateway for spend + chat tiles. |
| `PLANE_API_URL`, `PLANE_API_TOKEN`, `PLANE_WORKSPACE_SLUG`, `PLANE_PROJECT_ID` | per-tile | Plane backlog tile. |
| `GRAFANA_URL`, `GRAFANA_SA_TOKEN` | per-tile | Grafana dashboards tile. |

## Tests

```bash
pnpm test:unit     # vitest — auth, tailscale, canonical-url, login redirect
pnpm test          # playwright — e2e against a running dev server
pnpm typecheck
pnpm lint
```

## References

- Spec: [`docs/specs/walter-council-v2.md`](../../docs/specs/walter-council-v2.md)
- ADR (stack choice): [`docs/decisions/0008-control-tower-stack.md`](../../docs/decisions/0008-control-tower-stack.md)
- Runbook: [`docs/operational/council-v2-deployment-runbook.md`](../../docs/operational/council-v2-deployment-runbook.md)
