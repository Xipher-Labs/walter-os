---
name: telegram-bot-cli
description: >-
  Send messages, files, and notifications via the Telegram Bot API using `curl`.
  Use this skill whenever the user asks to "send a Telegram notification",
  "alert me on Telegram", "post to my Telegram channel from a script". Replaces
  the dropped community telegram MCP. SECURITY KEY POINT — bots only see chats
  they have been added to, NOT all your personal chats. This is a feature:
  bounded blast radius.
---

# Telegram Bot API

Why this is a skill and not an MCP:

The community telegram MCPs (e.g. `@overpod/mcp-telegram`) ran in **MTProto
user-bot mode** — i.e., logged in as YOUR account. That gave the agent
read/write access to **all** your personal chats, contacts, files. Too
much surface for a single-maintainer community package.

The **Bot API**, by contrast:

- Bot only sees chats it has been **explicitly added to** or that the user
  has **started** with `/start`.
- Bot can read/post in those chats, send files, call inline keyboards.
- Bot **cannot** read your DMs with other people, your channels you only
  consume, your secret chats, or your private messages.

This is the right scope for an agent.

## Setup (one-time)

### 1. Create the bot

1. Telegram → message `@BotFather` → `/newbot`
2. Name it (e.g. "Walter Notifier") and pick a username (must end in
   `bot`, e.g. `walter_notifier_bot`).
3. BotFather returns a token like `8123456789:AAH...`. Save it as
   `WALTER_TELEGRAM_BOT_TOKEN` in your secrets store (Infisical workspace
   `walter-os`).

### 2. Get your chat ID

```bash
# Start a chat with your bot in the Telegram app, send any message.
# Then:
curl -s "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/getUpdates" | jq '.result[].message.chat'
```

Save the `id` field as `WALTER_TELEGRAM_CHAT_ID` in your secrets.

### 3. (Optional) Group / channel

To use the bot in a group: add bot to group → BotFather command
`/setprivacy` → `Disable` (so the bot can read messages in the group).

For channels: add the bot as admin → use the channel's `@channelname` or
its numeric `-100xxxxxxxxxx` ID.

## Common operations

### Send a text message

```bash
curl -s -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
  -d "text=Deploy completed: ${COMMIT_SHA}" \
  -d "parse_mode=Markdown"
```

### Send a file (up to 50 MB)

```bash
curl -s -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendDocument" \
  -F "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
  -F "document=@/tmp/deploy-report.txt" \
  -F "caption=Deploy report"
```

### Send a photo

```bash
curl -s -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendPhoto" \
  -F "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
  -F "photo=@/tmp/screenshot.png" \
  -F "caption=Lighthouse score"
```

### Wrapper function (drop in `~/.zsh.d/30-tools.zsh`)

```bash
walter_notify() {
  local msg="${1:-Walter ping}"
  curl -s -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$msg" \
    -d "parse_mode=Markdown" >/dev/null
}

# Usage anywhere:
walter_notify "Deploy of [project-a]-web@$(git rev-parse --short HEAD) succeeded ✅"
```

## Use cases for this operator

| When | What |
|---|---|
| CI / deploy pipeline finishes | Notify with commit SHA + Vercel/Railway URL |
| Walter-VM service down (uptime-kuma alert) | Push to bot, link to status.${WALTER_DOMAIN} |
| Daily supply-chain audit blocks session | Notify with audit summary |
| Hetzner spending threshold crossed | Alert with current spend |
| Long-running task (Maestro full suite) finishes | Ping when done |

Plane / Linear / n8n can all webhook into the same bot — Walter-VM gets
one unified notification surface.

## Hard rules

- **NEVER paste the bot token in chat / Slack / committed files.** Token
  in URL = token in server logs.
- **NEVER add the bot to chats containing third-party private content.**
  Your bot, your chats — keep it bounded.
- **Rate limit**: Telegram rate-limits bots at 30 messages/sec to
  different chats, 1/sec to the same chat. Don't spam in loops.
- **Token rotation**: BotFather → `/revoke` → `/newtoken` every 90 days.

## Receiving messages (webhook side, optional)

For a two-way flow (you message bot → automation responds), the bot
needs a public webhook. Two options:

1. **Polling** (simpler, works from anywhere): cron job that calls
   `getUpdates` every N seconds, processes new messages.
2. **Webhook** (lower latency, requires public HTTPS): set webhook to
   `https://walter-vm.${WALTER_DOMAIN}/telegram-hook` — but that's another
   surface to expose. Skip for now.

For our case (alerts only, one-way), polling/webhook isn't needed.

## What this skill does NOT cover

- Multi-user bot (forms, payments, login). That's a real product, not a
  skill.
- Reading group chats the bot wasn't added to. Not possible by design,
  and we don't want it.
- Telegram channels broadcast (one-way) — same `sendMessage` call,
  different chat_id format.

## Why CLI / curl instead of MCP

- The Bot API surface we use is 4 endpoints (`sendMessage`,
  `sendDocument`, `sendPhoto`, `getUpdates`). curl + jq is 5 lines.
- Adding an MCP layer adds dependency + supply-chain risk for ~zero
  capability gain.
- The MTProto MCP we considered would have given the agent access to
  ALL personal chats. Refused on principle — agent should access bounded
  bot scope only.

## References

- https://core.telegram.org/bots/api
- https://core.telegram.org/bots/features
