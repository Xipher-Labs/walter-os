---
name: alerting-stack
description: Walter-VM lightweight alerting — replaces PagerDuty / Opsgenie complexity with a 4-tier stack pushing to a single Telegram bot. Use this skill whenever the user asks "set up alerts", "I want to know if a service goes down", "monitor my LLM spend", "Hetzner cost alert", or anything related to monitoring + notifications. No paid services, no SaaS lock-in. Single notification channel (Telegram bot) keeps it cognitively cheap.
---

# Walter-VM alerting stack — the simple version

PagerDuty and Opsgenie are overkill for a one-operator self-hosted setup.
You want: "ping me on Telegram if something breaks". Four tiers cover
every realistic failure mode.

## The bot (one bot, all tiers)

You already have:
- Telegram bot via @BotFather (skill: `telegram-bot-cli`)
- Bot token in `WALTER_TELEGRAM_BOT_TOKEN`
- Your chat ID in `WALTER_TELEGRAM_CHAT_ID`

Every tier below pushes to the same bot. One pinned chat, one mute toggle,
one "shut up" button when you're sleeping.

## Tier 1 — Service uptime (Uptime-Kuma → Telegram)

**Covers**: any HTTP/TCP/DNS service down, including Plane / Forgejo /
LiteLLM / Infisical / n8n / public sites you care about.

**Setup** (in https://status.${WALTER_DOMAIN}):

1. Settings → **Notifications** → **Setup Notification**
2. Type: **Telegram**
3. Friendly name: `walter-bot`
4. Bot Token: paste `WALTER_TELEGRAM_BOT_TOKEN`
5. Chat ID: paste `WALTER_TELEGRAM_CHAT_ID`
6. Click **Test** — should arrive instantly.
7. **Default Enabled** + **Apply on all existing monitors** — checked.
8. Save.

Then add monitors for:

| Monitor | Type | Target | Interval |
|---|---|---|---|
| Plane | HTTP(s) keyword | https://plane.${WALTER_DOMAIN}, expect 200/302/CF Access redirect | 60s |
| Forgejo | HTTP(s) | https://git.${WALTER_DOMAIN} | 60s |
| LiteLLM | HTTP(s) | https://llm.${WALTER_DOMAIN}/health | 60s |
| Infisical | HTTP(s) | https://secrets.${WALTER_DOMAIN} | 60s |
| n8n | HTTP(s) | https://n8n.${WALTER_DOMAIN}/healthz (after CF Access bypass on /healthz) | 60s |
| Walter-VM SSH | TCP | walter-os.cf:22 (CF Access tunnel doesn't break this — Kuma checks tunnel health indirectly) | 5min |
| ${WALTER_DOMAIN} email MX | DNS | ${WALTER_DOMAIN} (MX record exists) | 30min |
| Cloudflare itself | HTTP | https://cloudflare.com/cdn-cgi/trace | 5min (canary) |

**Retry / Down threshold**: 3 failed × 60s = 3min before page. Avoid
flapping at 1 fail.

**Dependencies**: Mark `Cloudflare itself` as a **dependency** of all CF-fronted
services. If CF is the cause of "everything is down", you get one alert,
not eight.

## Tier 2 — VM resources (cron script → Telegram)

**Covers**: VM disk full, RAM exhausted, CPU pinned, swap thrashing.
Things Kuma can't see by default.

Deploy: `setup/walter-host/services/alerting/walter-vm-watchdog.sh` — a 60-line
bash script that runs every 5 minutes via cron, checks thresholds, posts
to Telegram on transition (NOT on every poll — uses a state file to
debounce).

Thresholds:
- Disk root `/` > 85% used → alert
- Disk `/mnt/walter-vm-data` > 85% used → alert
- RAM > 90% used → alert
- Load average 1m > 8.0 (we have 8 vCPU) → alert
- Swap > 50% used → alert

State file: `/var/run/walter-watchdog.state` — tracks "last alerted level"
per metric. Only sends a Telegram message when crossing UP into trouble
or DOWN into clear.

## Tier 3 — LLM spend (LiteLLM → n8n → Telegram)

**Covers**: virtual key budget exhausted, daily/monthly spend cap hit,
unexpected usage spike.

LiteLLM has built-in budget alerts via webhook. Setup:

1. LiteLLM admin UI → Settings → Alerts
2. Add webhook URL: `https://n8n.${WALTER_DOMAIN}/webhook/litellm-spend-alert`
3. Trigger conditions:
   - 80% budget consumed (warning)
   - 95% budget consumed (critical)
   - Daily spend > $5 (sanity check)
   - Single request > $0.50 (catches runaway prompts)

4. In n8n, create workflow `litellm-spend-alert`:
   - Webhook trigger at `/webhook/litellm-spend-alert`
   - Function: format the alert payload nicely
   - Telegram node: send to bot
   - Optional: tag with `🚨` emoji and the virtual key name

**Where the budget per virtual key is set**: LiteLLM admin UI → Virtual
Keys → per-key max budget + reset interval (daily/weekly/monthly).

## Tier 4 — Hetzner spend trend (cron + hcloud → Telegram)

**Covers**: a forgotten test VM, snapshot accumulation, accidental
high-spec resize.

Deploy: `setup/walter-host/services/alerting/hetzner-spend-watch.sh` — runs daily
at 09:00 (cron), uses hcloud CLI to fetch all running resources + their
monthly cost, computes the projected month-end total, alerts if delta
vs. yesterday > 10% OR if absolute monthly > €100.

Output sample (sent only on threshold cross):
```
Hetzner spend update — 2026-05-04
  Servers:   walter-os (CX43)        €25.20
  Volumes:   walter-vm-data (100GB)  €4.76
  Snapshots: (0)                     €0.00
  ─────────────────────────────────────────
  Projected: €29.96/mo  (+0% vs yesterday)
```

## What this stack does NOT replace

- **Status page for users** — Kuma can publish one (status.${WALTER_DOMAIN}),
  but it's a "is it up?" surface, not an SLO tracker.
- **Postmortems / incident management** — write them in Obsidian (vault
  has `incidents/` folder). Or use a simple Plane project `walter-vm-incidents`.
- **Pager rotation** — there's only you. If you need someone else to
  cover, that's a different problem (and PagerDuty is the right tool then).
- **Anomaly detection** — Grafana with Loki + Prometheus is Phase K4.2.
  This skill is the "human-readable alerts" layer, separate from
  observability data store.

## Hard rules

- **One channel.** Don't fan out to email + Slack + Telegram. You'll
  ignore all of them. One bot, pinned chat.
- **Debounce everything.** The watchdog state file pattern (alert on
  transition only) is non-negotiable. Otherwise you train yourself to
  mute the bot.
- **Test the test.** Once a month, manually fail a service (kill
  cloudflared for 5 min, then restart). Verify: alert arrives, recovery
  arrives. If silent, fix.
- **Mute pattern**: send `/mute 1h` to the bot — n8n workflow consumes
  that and pauses Tier 2-4 for the duration. Tier 1 (Kuma) you mute via
  the Kuma UI directly. Document the runbook for muting in Obsidian
  `~/Obsidian/vault/runbooks/walter-vm-alerts.md`.

## Getting started — the 30-minute setup

```
1.  [5min]  BotFather → create bot → token to Infisical
2.  [5min]  Get chat ID via curl getUpdates
3.  [5min]  Kuma → notifications → Telegram → test
4.  [5min]  Add the 8 monitors above
5.  [5min]  Copy walter-vm-watchdog.sh to VM, add to crontab
6.  [5min]  Copy hetzner-spend-watch.sh to VM, add to crontab
DONE → 30min and you have PD-class coverage for €0/mo
```

LiteLLM webhook (Tier 3) waits until you have actual API keys loaded
into LiteLLM — that part can land later.

## Files

- `setup/walter-host/services/alerting/walter-vm-watchdog.sh` — Tier 2 script
- `setup/walter-host/services/alerting/hetzner-spend-watch.sh` — Tier 4 script
- `setup/walter-host/services/alerting/cron.example` — crontab snippets
- `setup/walter-host/services/alerting/n8n-workflows/` — JSON exports for Tier 3

## References

- https://github.com/louislam/uptime-kuma — Kuma docs
- https://docs.litellm.ai/docs/proxy/alerting — LiteLLM alert config
- https://core.telegram.org/bots/api#sendmessage — bot API
- skills/telegram-bot-cli/SKILL.md — outbound notifications
