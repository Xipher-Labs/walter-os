# Walter-VM known issues (active)

## claude-code-router daemon won't bind reliably

`ccr start` daemonizes; reports "claude-code-router server is running"
but TCP listener on 3456 doesn't always come up. Container stays alive
(sleep infinity wrapper) but operator can't reach the UI.

**Workaround**: SSH tunnel + retry. `ssh -L 3456:127.0.0.1:3456 -N walter-vm`
then `http://localhost:3456/ui` — refresh until it loads.

**Real fix**: replace `ccr start` invocation with direct `node` call into
the cli.js server module to keep server in foreground. Tracked as TODO.

## Headscale admin UI served at /admin/ not /

`goodieshq/headscale-admin` serves the SPA under `/admin/`. The
cloudflared route to `hs.${WALTER_DOMAIN}` doesn't rewrite paths.

**Workaround**: visit `https://hs.${WALTER_DOMAIN}/admin/` directly.

**Real fix**: add Caddy/nginx in front of headscale-admin that 301
redirects `/` → `/admin/`. Or change cloudflared to use `originRequest`
with a path rewrite.

## PostHog blank page when reached via tunnel (Caddy host-header mismatch)

PostHog ships its own `posthog-proxy-1` Caddy that fronts all
PostHog sub-services (`web`, `capture`, `flags`, `surveys`, `livestream`,
etc.) under a single `Host: localhost:8000` site block (the Caddyfile
literally starts with `http://localhost:8000 { … }`). When cloudflared
forwards a request from the public tunnel, it carries
`Host: posthog.${WALTER_DOMAIN}` — Caddy finds no matching site, falls
through to its default handler, and replies `HTTP 200` with an empty
body and **no `Content-Type` header**. Browsers receive what looks like
plain text → render nothing → blank screen.

The PostHog Django backend itself (`posthog-web-1`) is fine — the bug
is purely in the cloudflared → Caddy boundary.

**Fix on the VM** (already applied in `/etc/cloudflared/config.yml`,
rotated 2026-05-24): rewrite the host header at the cloudflared
ingress so the inner Caddy matches its own site block.

```yaml
- hostname: posthog.${WALTER_DOMAIN}
  service: http://127.0.0.1:8100
  originRequest:
    httpHostHeader: localhost:8000   # match posthog-proxy-1's Caddyfile
```

**Verification**:

```bash
TOK=$(cloudflared access token --app https://posthog.${WALTER_DOMAIN}/)
curl -sS -i -H "cf-access-token: $TOK" "https://posthog.${WALTER_DOMAIN}/" | head -5
# Expect: HTTP/2 302 + location: /login + content-type: text/html
# (NOT: HTTP/2 200 + content-length: 0)
```

**Pitfall when re-provisioning**: `setup/walter-host/cloudflare/02-create-tunnel.sh`
generates ingress entries from the `SUBDOMAINS` array assuming every
service is fronted by the walter-os central Caddy on `127.0.0.1:80`.
PostHog escapes that pattern because it brings its own proxy. Either
keep this override applied after every cloudflared config refresh OR
add a `service: http://127.0.0.1:80` route to the walter-os central
Caddy that does the same `header_up Host localhost:8000` rewrite — the
latter is cleaner and removes the special case from cloudflared, but
requires the walter-os Caddy container to be on `posthog_default`
network (or use the host port 8100 as we do today).

**Same trap, other stacks**: any upstream stack that ships a self-
hosted Caddy/nginx with a hard-coded `Host: localhost` matcher will
hit the same blank-screen failure when fronted by cloudflared. Notable
candidates to audit: Plane (`plane-proxy`), PostHog (this case),
Postiz if it grows a proxy, Penpot, Synapse. Test before declaring a
service "exposed".

## OpenAI / Google / Claude subscription proxies

Pending implementation. Notes:
- OpenAI: pandora-next went paid; alternatives (xqdoo00o/ChatGPT-To-API,
  gngpp/ninja) less stable. Operator's CLI access via Codex CLI direct
  works as workaround.
- Google Gemini: no current subscription proxy that's stable.
- Anthropic: claude-code-router (above issue blocks).
- LiteLLM fallback chain configured to use `claude-sub` model name
  pointing at claude-code-router; activates once ccr is stable.
