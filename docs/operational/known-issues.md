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

## OpenAI / Google / Claude subscription proxies

Pending implementation. Notes:
- OpenAI: pandora-next went paid; alternatives (xqdoo00o/ChatGPT-To-API,
  gngpp/ninja) less stable. Operator's CLI access via Codex CLI direct
  works as workaround.
- Google Gemini: no current subscription proxy that's stable.
- Anthropic: claude-code-router (above issue blocks).
- LiteLLM fallback chain configured to use `claude-sub` model name
  pointing at claude-code-router; activates once ccr is stable.
