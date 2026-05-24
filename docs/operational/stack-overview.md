# Stack at a glance — services in `setup/walter-host/`

This is the catalogue of the **optional** self-hosted service stack
(Mode 3 in the [README](../../README.md) install section). Mode 1 / Mode
2 install paths don't deploy any of this.

> RAM budget values are typical RSS under moderate load, not hard container
> limits. Actual usage varies significantly with usage patterns.

| Service | What it does | Hostname | Profile | RAM budget | Compose file |
|---|---|---|---|---|---|
| **Homepage** | Dashboard / service tiles | `home.your-domain` | core | ~128 MB | [`setup/walter-host/services/homepage/`](../../setup/walter-host/services/homepage/) |
| **Forgejo** | Self-hosted Git + CI runner | `git.your-domain` | core | ~256 MB | [`setup/walter-host/services/forgejo/`](../../setup/walter-host/services/forgejo/) |
| **Plane** | Project management + issue tracker | `plane.your-domain` | core | ~512 MB | [`setup/walter-host/services/plane/`](../../setup/walter-host/services/plane/) |
| **Infisical** | Secrets vault (runtime + operator) | `secrets.your-domain` | core | ~512 MB | [`setup/walter-host/services/infisical/`](../../setup/walter-host/services/infisical/) |
| **LiteLLM (Walter-Bridge)** | AI model gateway (37 aliases across 17 providers) | `bridge.your-domain` | core | ~256 MB | [`setup/walter-host/services/litellm/`](../../setup/walter-host/services/litellm/) |
| **n8n** | Workflow automation | `n8n.your-domain` | core | ~512 MB | [`setup/walter-host/services/n8n/`](../../setup/walter-host/services/n8n/) |
| **Uptime Kuma** | Service health monitoring | `status.your-domain` | core | ~128 MB | [`setup/walter-host/services/uptime-kuma/`](../../setup/walter-host/services/uptime-kuma/) |
| **Grafana** | Metrics dashboards + alerting | `grafana.your-domain` | monitoring | ~256 MB | [`setup/walter-host/services/observability/`](../../setup/walter-host/services/observability/) |
| **Prometheus** | Metrics scraper | internal | monitoring | ~256 MB | [`setup/walter-host/services/observability/`](../../setup/walter-host/services/observability/) |
| **Syncthing** | File sync across devices | `sync.your-domain` | core | ~128 MB | [`setup/walter-host/services/syncthing/`](../../setup/walter-host/services/syncthing/) |
| **Penpot** | UI/UX design tool (Figma alternative) | `penpot.your-domain` | design | ~512 MB | [`setup/walter-host/services/penpot/`](../../setup/walter-host/services/penpot/) |
| **Drawio** | Technical diagrams | `draw.your-domain` | design | ~128 MB | [`setup/walter-host/services/drawio/`](../../setup/walter-host/services/drawio/) |
| **RocketChat** | Team messaging | `chat.your-domain` | comms | ~512 MB | [`setup/walter-host/services/rocketchat/`](../../setup/walter-host/services/rocketchat/) |
| **Synapse** | Matrix homeserver | `matrix.your-domain` | comms | ~256 MB | [`setup/walter-host/services/synapse/`](../../setup/walter-host/services/synapse/) |
| **Element** | Matrix web client | `element.your-domain` | comms | ~64 MB | [`setup/walter-host/services/synapse/`](../../setup/walter-host/services/synapse/) |
| **Headscale** | Self-hosted Tailscale control plane | `hs.your-domain` | core | ~64 MB | [`setup/walter-host/services/headscale/`](../../setup/walter-host/services/headscale/) |
| **Headscale UI** | Headscale web interface | `hsui.your-domain` | core | ~32 MB | [`setup/walter-host/services/headscale/`](../../setup/walter-host/services/headscale/) |
| **wg-easy (WireGuard)** | WireGuard VPN with admin UI | `wg.your-domain` | core | ~32 MB | [`setup/walter-host/services/wireguard/`](../../setup/walter-host/services/wireguard/) |
| **Metabase** | Analytics / SQL dashboards | `analytics.your-domain` | analytics | ~1 GB | [`setup/walter-host/services/`](../../setup/walter-host/services/) |
| **PostHog** | Product analytics + session replay | `ph.your-domain` | marketing | ~6 GB* | [`setup/walter-host/services/`](../../setup/walter-host/services/) |
| **Postiz** | Social media scheduling | `postiz.your-domain` | marketing | ~512 MB | [`setup/walter-host/services/postiz/`](../../setup/walter-host/services/postiz/) |
| **SeaweedFS** | Distributed object storage | internal | analytics | ~256 MB | [`setup/walter-host/services/`](../../setup/walter-host/services/) |
| **Control Tower** | Agent Council browser UI | Tailscale-only | core | ~512 MB | [`apps/control-tower/`](../../apps/control-tower/) |
| **OpenClaw** | Open-source Claude interface | `openclaw.your-domain` | core | ~128 MB | [`setup/walter-host/services/openclaw/`](../../setup/walter-host/services/openclaw/) |
| **LLM proxies** | Subscription-backed model routers | internal | core | ~256 MB | [`setup/walter-host/services/llm-proxies/`](../../setup/walter-host/services/llm-proxies/) |
| **Postgres** | Shared database for Plane, Infisical, n8n, Metabase | internal | core | ~256 MB | [`setup/walter-host/services/postgres/`](../../setup/walter-host/services/postgres/) |
| **Restic** | Automated backups | cron | core | ~64 MB | [`setup/walter-host/services/restic/`](../../setup/walter-host/services/restic/) |
| **Alerting** | Grafana alert routing (email/Telegram) | internal | monitoring | ~32 MB | [`setup/walter-host/services/alerting/`](../../setup/walter-host/services/alerting/) |

*PostHog with ClickHouse and session replay enabled; ClickHouse alone
accounts for ~2 GB. Requires `ulimit -n 262144` — see
[`troubleshooting.md`](troubleshooting.md).

## Compose profiles

| Profile | Activation | Always-on? |
|---|---|---|
| `core` | `docker compose up -d` | Yes |
| `monitoring` | `docker compose --profile monitoring up -d` | Opt-in |
| `design` | `docker compose --profile design up -d` | Opt-in |
| `comms` | `docker compose --profile comms up -d` | Opt-in |
| `analytics` | `docker compose --profile analytics up -d` | Opt-in |
| `marketing` | `docker compose --profile marketing up -d` | Opt-in |
| `tier4` | `docker compose --profile tier4 up -d` | Opt-in (Control Tower + Council) |

Combine profiles with multiple `--profile` flags. Total RAM budget grows
roughly linearly — see [`resource-budget.md`](resource-budget.md) for
sizing guidance.

## Related

- [`requirements.md`](requirements.md) — hardware + DNS + SSH prereqs
- [`resource-budget.md`](resource-budget.md) — VM sizing per profile combo
- [`operator-setup-runbook.md`](operator-setup-runbook.md) — full step-by-step
- [`walter-bridge.md`](walter-bridge.md) — LiteLLM gateway deep-dive
- [`troubleshooting.md`](troubleshooting.md) — common operational issues
