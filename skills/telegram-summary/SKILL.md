---
name: telegram-summary
description: Read your personal Telegram chats (DMs, groups, channels) for one-off operations like summarizing a conversation, finding messages, or exporting threads. Uses `tdl` (official Go CLI built on tdlib) invoked locally — NOT a long-running MCP. Complementary to skills/telegram-bot-cli/ which handles outbound notifications via the bounded Bot API.
---

# Telegram personal-chat summaries (`tdl`)

Two distinct Telegram skills, two distinct surfaces:

| Skill | Surface | Why |
|---|---|---|
| `telegram-bot-cli` | Bot API (sendMessage, etc.) | Outbound notifications. Bot can't see personal chats. Bounded by design. Used by Walter-VM alerts, OpenClaw notifier, n8n workflows. |
| `telegram-summary` | MTProto (your account) | Inbound — read YOUR personal chats for summary, search, export. **Operator-invoked, not autonomous**. Tooling that runs only when you explicitly ask. |

The split matters: an MTProto MCP loaded all the time is too much
authority. A `tdl` invocation when you say "summarize my chat with X
from this week" is a discrete, audited action.

## Setup (one-time)

### 1. Get Telegram API credentials

[my.telegram.org](https://my.telegram.org) → "API development tools" →
create a new application. You get:
- `api_id` (numeric)
- `api_hash` (string)

Save them to Infisical workspace `walter-os`:

```bash
infisical secrets set TELEGRAM_API_ID=12345678 --workspace-name=walter-os --env=dev
infisical secrets set TELEGRAM_API_HASH=abc123... --workspace-name=walter-os --env=dev
```

### 2. Install `tdl`

```bash
brew install iyear/tap/tdl
# Verify
tdl version
```

`tdl` is a Go CLI built on tdlib (the official Telegram client library).
Reasonably popular (~10k stars), single Go binary, easier to audit than
a full MCP.

### 3. Login (one-time per machine)

```bash
infisical run --workspace-name=walter-os --env=dev -- tdl login
# ↳ phone number → SMS code → 2FA password if enabled
# Session is stored encrypted at ~/.tdl/session/
```

The session file is the access token. **Treat it like a password** — its
in `~/.tdl/`, mode 600, gitignored everywhere. Rotate by `tdl logout`
+ login again every 90 days.

## Common operations

### List your chats

```bash
tdl chat ls
# Filter:
tdl chat ls -f 'json["Type"] == "private"'        # only DMs
tdl chat ls -f 'json["Type"] == "supergroup"'     # only groups
```

### Export a chat to JSON

```bash
# Last 30 days of messages from a chat
tdl chat export -c <chat_id_or_username> \
  -T time -i "$(date -v-30d +%s)" \
  -o /tmp/chat-export.json
```

### Summarize a conversation (the typical agent ask)

```bash
# 1. Export the chat
CHAT="@some_username"
tdl chat export -c "$CHAT" -T time -i "$(date -v-7d +%s)" -o /tmp/chat.json

# 2. Hand the JSON to the agent for summary
#    The JSON has structure: [{ "id", "from", "text", "date", ... }]
#    Agent reads it via Read tool, produces summary.
```

In agent flow: the agent runs the export command, reads the JSON, writes
the summary, and **deletes** `/tmp/chat.json` after (sensitive data
hygiene).

### Find messages

```bash
tdl chat export -c "@channel" -T msg-id -i 1000 -e 2000 -o /tmp/range.json
# Or via the API directly with custom filters via `tdl extension`
```

## Hard rules

- **Never run `tdl` in autonomous loops.** Operator-invoked only. The
  agent confirms the command (which chat, which time range) before
  executing.
- **Never export private chats containing third-party sensitive data
  without their knowledge.** Treat exported JSON as you would screenshots
  — applies the same social/legal norms.
- **Always delete /tmp exports after use.** They're plaintext.
- **Session file is bearer auth.** If `~/.tdl/session/` leaks, rotate
  immediately (`tdl logout` from web Telegram → "Active Sessions" →
  terminate).
- **NEVER feed exported chats to an external LLM API without
  consideration.** For [Project B]-style sensitivity, use local LLM only
  (Walter-VM Ollama or M2 Ultra). For everyday summaries, OK to send
  to Anthropic via LiteLLM gateway — but still preview before send.

## Why not the MCP?

The community telegram-mcp packages we evaluated:
- Run as long-lived servers reading your account 24/7.
- Single-maintainer trust scores.
- No granular permission gating — once loaded, any agent can call any
  Telegram method.

`tdl` invoked on-demand:
- Discrete operation per command, easy to audit in shell history.
- Mature CLI with active community (multiple contributors).
- Source code is one Go module, readable.
- Session file revocation is trivial.

This isn't a perfect solution (MTProto is intrinsically powerful), but
it's a much better trust model than a long-running MCP.

## Combining with `telegram-bot-cli`

Typical flow:

1. (Inbound) Operator: "Summarize my Telegram chat with @colleague from
   this week."
2. Agent: invokes `tdl chat export` (this skill).
3. Agent: produces summary, posts it to a Plane issue or Obsidian note.
4. (Outbound) Agent: pings via `telegram-bot-cli` to "Summary written
   here: <link>".

The bot doesn't see the chat being summarized. The summary lives in
your tooling. Clean separation.

## What this skill does NOT cover

- Continuously monitoring chats — that's intentionally not in scope.
- Sending messages from your account — use `telegram-bot-cli` (bot
  scope, bounded). If you absolutely need to send from your user
  account, add it explicitly with operator-confirmation in this skill.
- Archiving entire chat history regularly — use Telegram's official
  desktop export feature (Chat → ⋯ → Export chat history).

## References

- https://github.com/iyear/tdl
- https://core.telegram.org/api (MTProto reference)
- https://my.telegram.org
