#!/usr/bin/env python3
"""
kuma-bulk-monitors.py — bulk-create Walter-VM monitors via Uptime-Kuma API.
Idempotent: skips monitors with the same name.

Requires: uptime-kuma-api (pip install uptime-kuma-api)

Usage:
    pip install uptime-kuma-api  # or: uvx --from uptime-kuma-api python kuma-bulk-monitors.py
    WALTER_DOMAIN=yourdomain.com KUMA_USER=admin KUMA_PASS=<from-kuma-ui> \
        python3 kuma-bulk-monitors.py

Environment variables:
    WALTER_DOMAIN  — required. All monitor URLs (Plane, Forgejo, LiteLLM, etc.)
                     are derived from this domain. There is no way to run this
                     script without it because the monitored services live at
                     subdomains of WALTER_DOMAIN.
    KUMA_URL       — optional override for the Uptime Kuma SERVER endpoint only
                     (i.e. where this script connects to manage monitors).
                     Default: https://status.{WALTER_DOMAIN}
                     Note: KUMA_URL does NOT affect the URLs of the services being
                     monitored — those always come from WALTER_DOMAIN.
    OPENCLAW_TUNNEL_HOSTNAME
                   — optional override for the OpenClaw monitor hostname.
                     Default: claw.{WALTER_DOMAIN}
    KUMA_USER      — required. Uptime Kuma login username.
    KUMA_PASS      — required. Uptime Kuma login password (set via UI on first run).
"""
import os
import sys

try:
    from uptime_kuma_api import UptimeKumaApi, MonitorType
except ImportError:
    print("Run: pip install uptime-kuma-api  (or via uvx)", file=sys.stderr)
    sys.exit(1)

WALTER_DOMAIN = os.environ.get("WALTER_DOMAIN")
if not WALTER_DOMAIN:
    print("ERROR: WALTER_DOMAIN env var required (e.g. yourdomain.com)", file=sys.stderr)
    sys.exit(1)

KUMA_URL = os.environ.get("KUMA_URL", f"https://status.{WALTER_DOMAIN}")
OPENCLAW_TUNNEL_HOSTNAME = os.environ.get("OPENCLAW_TUNNEL_HOSTNAME", f"claw.{WALTER_DOMAIN}")
KUMA_USER = os.environ.get("KUMA_USER")
KUMA_PASS = os.environ.get("KUMA_PASS")

if not (KUMA_USER and KUMA_PASS):
    print("Set KUMA_USER and KUMA_PASS env vars", file=sys.stderr)
    sys.exit(1)

# Walter-VM service inventory: monitors to ensure exist.
# All URLs are derived from WALTER_DOMAIN — no hardcoded operator domains.
MONITORS = [
    # name, url, expected_keyword, interval_seconds
    ("Plane",        f"https://plane.{WALTER_DOMAIN}",                   None,    60),
    ("Forgejo",      f"https://git.{WALTER_DOMAIN}",                     None,    60),
    ("Infisical",    f"https://secrets.{WALTER_DOMAIN}",                 None,    60),
    ("LiteLLM",      f"https://llm.{WALTER_DOMAIN}/health/liveliness",   "alive", 60),
    ("n8n",          f"https://n8n.{WALTER_DOMAIN}",                     None,    60),
    ("Grafana",      f"https://grafana.{WALTER_DOMAIN}/api/health",      "ok",    60),
    ("Penpot",       f"https://penpot.{WALTER_DOMAIN}",                  None,    60),
    ("Drawio",       f"https://draw.{WALTER_DOMAIN}",                    None,    60),
    ("RocketChat",   f"https://chat.{WALTER_DOMAIN}",                    None,    60),
    ("Syncthing",    f"https://sync.{WALTER_DOMAIN}",                    None,    60),
    ("Homepage",     f"https://home.{WALTER_DOMAIN}",                    None,    60),
    ("Metabase",     f"https://metabase.{WALTER_DOMAIN}/api/health",     "ok",    60),
    ("PostHog",      f"https://posthog.{WALTER_DOMAIN}/_health/",        "ok",    60),
    ("Postiz",       f"https://postiz.{WALTER_DOMAIN}/api/health",       None,    60),
    ("Control Tower", f"https://tower.{WALTER_DOMAIN}/api/health",       None,    60),
    ("Headscale",    f"https://headscale.{WALTER_DOMAIN}/health",        None,   120),
    ("Hermes Agent", f"https://hermes.{WALTER_DOMAIN}/health",           None,    60),
    # OpenClaw — multi-channel personal assistant gateway. Hits the public URL
    # behind Cloudflare Access; accepted_statuscodes (200-299, 302) covers the
    # OTP redirect, which proves the tunnel + Access are alive. For deeper
    # health (gateway-level), add a private monitor or a CF Access service
    # token bypass on /healthz — see docs/specs/openclaw.md §9.
    ("OpenClaw",     f"https://{OPENCLAW_TUNNEL_HOSTNAME}",              None,    60),
    # Telegram Bot API liveness — `/bot<token>/getMe` requires the real
    # token and we don't bake secrets into this script. Hit the API root
    # instead (always returns 302); for actual bot health, the bot itself
    # heartbeats a Kuma Push monitor created out-of-band.
    ("Telegram API",       "https://api.telegram.org",           None, 300),
    ("Cloudflare canary",  "https://cloudflare.com/cdn-cgi/trace", None, 300),
    # -------------------------------------------------------------------------
    # Subscription LLM routers (internal-only, no Caddy vhost).
    # These are LiteLLM-internal services on ports 1456-1458, not exposed via
    # Caddy. Monitor via their LiteLLM proxy health rather than direct HTTP.
    # TODO: if a Caddy vhost is added later, replace with:
    #   ("Codex Router",  f"https://codex.{WALTER_DOMAIN}/health",  None, 60)
    #   ("Claude Router", f"https://claude.{WALTER_DOMAIN}/health", None, 60)
    #   ("Gemini Router", f"https://gemini.{WALTER_DOMAIN}/health", None, 60)
    # -------------------------------------------------------------------------
    # SeaweedFS S3 endpoint (127.0.0.1:8333) — internal-only, no Caddy vhost.
    # Monitor via the PostHog health check which depends on S3 connectivity, or
    # add a Push monitor from inside the VM:
    #   curl -s http://localhost:8333/ | grep -q "SeaweedFS"
    # TODO: if an S3 subdomain is added to Caddy, monitor as:
    #   ("SeaweedFS S3", f"https://s3.{WALTER_DOMAIN}", None, 60)
    # -------------------------------------------------------------------------
]

def main():
    print(f"→ connecting to {KUMA_URL}")
    with UptimeKumaApi(KUMA_URL) as api:
        api.login(KUMA_USER, KUMA_PASS)

        # Existing monitors
        existing = {m["name"]: m for m in api.get_monitors()}
        print(f"  existing: {len(existing)} monitors")

        added = 0
        skipped = 0
        for name, url, keyword, interval in MONITORS:
            if name in existing:
                skipped += 1
                print(f"  o {name:<22} (exists)")
                continue
            mtype = MonitorType.KEYWORD if keyword else MonitorType.HTTP
            # Bypass `add_monitor` (lib is Kuma 1.x); use _call directly with raw payload.
            # Kuma 2.x requires `conditions` field (NOT NULL constraint).
            # Kuma 2.x schema is different from 1.x. Minimal payload that matches.
            data = {
                "type": "keyword" if keyword else "http",
                "name": name,
                "url": url,
                "interval": interval,
                "retryInterval": 30,
                "maxretries": 3,
                "accepted_statuscodes": ["200-299", "302"],
                "method": "GET",
                "active": True,
                "conditions": [],     # JSON array, NOT a string
                "ignoreTls": False,
                "upsideDown": False,
                "expiryNotification": False,
                "maxredirects": 10,
                "timeout": 48,
            }
            if keyword:
                data["keyword"] = keyword
            api._call("add", data)
            added += 1
            print(f"  + {name:<22} added ({url})")

        print(f"\n-> done: {added} added, {skipped} skipped")
        print(f"-> Open https://status.{WALTER_DOMAIN} to attach the Telegram notification")
        print(f"   to all monitors (Settings -> Notifications -> Apply on existing)")

if __name__ == "__main__":
    main()
