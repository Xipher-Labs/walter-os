# Beeper self-hosted on Walter-VM (+ Mac Studio iMessage relay)

Operator decision: self-host Beeper bridges instead of paying $10/mo cloud
subscription. Mac Studio is always-on at home → covers iMessage relay
requirement.

## Architecture

```
                ┌─────────────────────────────────┐
                │  Mac Studio (always-on, casa)   │
                │   - mautrix-imessage relay      │
                │     (Apple ID + iMessage chats) │
                └────────────┬────────────────────┘
                             │ Tailscale + Matrix federation
                             ▼
   ┌─────────────────────────────────────────────────────────┐
   │  Walter-VM (Hetzner CX53, Helsinki)                     │
   │                                                          │
   │   Synapse (Matrix homeserver) :8008                     │
   │     /matrix.${WALTER_DOMAIN}                              │
   │                                                          │
   │   ├── mautrix-whatsapp     (QR scan from phone)         │
   │   ├── mautrix-telegram     (your user account)          │
   │   ├── mautrix-instagram    (Instagram login)            │
   │   ├── mautrix-signal       (linked device — phone QR)   │
   │   ├── mautrix-discord      (token from Discord)         │
   │   ├── mautrix-googlechat   (Google account)             │
   │   └── mautrix-imessage     ← bridges to Mac Studio relay│
   │                                                          │
   │   element-web              (Matrix web UI, optional)    │
   │     /chat.${WALTER_DOMAIN}                                │
   │                                                          │
   │   OpenClaw → reads ALL channels via Synapse             │
   └─────────────────────────────────────────────────────────┘
```

## Cost / resources

- Synapse: ~500 MB RAM, 5 GB disk
- Each mautrix bridge: ~100-200 MB
- 7 bridges total: ~1 GB RAM
- Element-web: ~50 MB
- **Total**: ~1.5 GB RAM, ~10 GB disk steady-state
- Cost: €0 marginal (Walter-VM CX53 has 32 GB RAM)

## Phase deployment (incremental)

Don't try to deploy all 7 bridges at once. Order:

```
Step 1: Synapse + element-web (base)              [30 min]
Step 2: mautrix-whatsapp                          [20 min — most useful]
Step 3: mautrix-telegram                          [20 min]
Step 4: mautrix-imessage on Mac Studio + bridge   [60 min — most complex]
Step 5: mautrix-signal                            [30 min]
Step 6: mautrix-instagram                         [30 min]
Step 7: mautrix-discord                           [20 min]
Step 8: mautrix-googlechat                        [20 min]
Step 9: Wire OpenClaw to Synapse                  [30 min]
```

Total: ~4-5 hours of operator time spread across days, with each step
verifiable in isolation.

## Step 1: Synapse + element-web (the base)

`setup/walter-host/services/beeper-self-hosted/synapse/` will be added in Phase K4.5
when operator is ready. It includes:

- `compose.yml` with Synapse + Postgres + element-web
- `homeserver.yaml.template`
- `signing.key` generated on first boot
- DNS: `matrix.${WALTER_DOMAIN}` (federation) + `chat.${WALTER_DOMAIN}` (Element)
- CF Tunnel + Access (Google IdP @${WALTER_DOMAIN})
- Restic backup target: `/var/lib/docker/volumes/synapse_*` (already covered)

## Step 2-8: Bridges via mautrix

Each bridge is its own container with:
- bridge config in `bridges/<name>/config.yaml`
- Postgres database in `bridges/<name>/db/` (or shared)
- Registration token registered with Synapse

Setup pattern (per bridge):

```bash
ssh walter-vm
cd /opt/walter-vm/services/beeper-self-hosted/bridges/whatsapp
docker compose up -d  # generates initial config
# Edit config.yaml with operator's Synapse domain
docker compose up -d
# In Element-web: start a chat with @whatsappbot:matrix.${WALTER_DOMAIN}
# Bot DMs you with a QR code
# Scan with phone WhatsApp → Linked Devices
# Bridge starts syncing chats
```

Same flow for Telegram, IG, Signal, Discord — different "login" mechanism
each (token vs QR vs OAuth).

## Step 4: iMessage on Mac Studio

The hardest one. Two paths:

**Option A: mautrix-imessage with `barcelona` backend** (newer, recommended)
- Runs on Mac Studio as macOS daemon
- Uses Apple ID's iMessage session via private framework
- Has been stable through 2025-2026 macOS releases

**Option B: mautrix-imessage with `bluebubbles` backend** (older)
- Runs as a macOS app (BlueBubbles Server)
- More mature but legacy

For both, the Mac Studio:
1. Logs into Apple ID
2. Runs the relay daemon (~50 MB RAM)
3. Joins Tailscale network → Walter-VM reachable at `100.x.x.x`
4. mautrix-imessage container on Walter-VM connects to relay over Tailscale

`setup/walter-host/services/beeper-self-hosted/imessage/` will include:
- Mac Studio side: `mac-studio-imessage-daemon.sh` (LaunchAgent install)
- Walter-VM side: `mautrix-imessage` compose

## Step 9: OpenClaw + Synapse

Once Synapse is up with bridges syncing, configure OpenClaw to read events:

```yaml
# /workspace/.openclaw/config.json (excerpt)
{
  "matrix": {
    "homeserver": "https://matrix.${WALTER_DOMAIN}",
    "user_id": "@${WALTER_MATRIX_USER:-operator}:${WALTER_DOMAIN}",
    "access_token": "..."  # from Element settings
  },
  "channels": {
    "telegram_bot": "@${WALTER_OPENCLAW_BOT_HANDLE}",
    "matrix_dm": "all",
    "matrix_groups": "muted_unless_tagged"
  }
}
```

Now OpenClaw sees:
- Telegram messages (direct bot interaction)
- WhatsApp / iMessage / IG / etc. (bridged into Matrix DMs)
- Slack / Discord (separate provider connectors via OpenClaw built-in)

All unified into one assistant inbox.

## Why not just use Beeper Cloud ($10/mo)?

- $120/year vs Walter-VM's existing capacity ($0 marginal)
- Operator data stays on operator infra (privacy posture)
- Mac Studio always-on removes the killer constraint
- Operator chose this explicitly

Trade-off accepted: ~4-5 hours setup + ~1 hour/quarter maintenance when
bridges break (WhatsApp protocol updates, etc.).

## Hard rules

- **Synapse public federation = OFF by default.** It's NOT a public
  Matrix server, only your bridges talk to it. `federation_domain_whitelist:
  []` in homeserver.yaml.
- **Element-web behind CF Access.** Don't expose without auth — bridges'
  bots are tempting targets for compromise.
- **PHI rule still applies**: don't bridge PHI/medical patient chats through
  any bridge. Those chats stay manual.
- **Backup the bridge tokens.** Each bridge generates a registration
  token Synapse uses to authorize it. Lose it, you re-pair the bridge
  from scratch (lose chat history).
- **Each bridge has its own DB.** Restic must back up
  `/var/lib/docker/volumes/beeper-*` — already covered by the wildcard.

## References

- https://developers.beeper.com/bridges/self-hosting/
- https://docs.mau.fi/bridges/
- https://element-hq.github.io/synapse/latest/
- skills/personal-assistant-stack/SKILL.md — overall strategy + LiteLLM routing
