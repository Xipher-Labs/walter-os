---
name: personal-assistant-stack
description: How Walter-OS thinks about a personal AI assistant that handles inbound messages (WhatsApp/Telegram/iMessage/Instagram), can reply for you, surfaces the urgent stuff, creates calendar events from chat context, and uses your LLM subscription rather than per-token API spend. Use this skill when the user asks "what's my personal assistant strategy", "should I use OpenClaw vs a custom bot", "how do I let the AI reply to my messages", "how do I route AI cost via subscription". Decision tree below.
---

# Walter-OS personal assistant stack — the answer is one assistant, not three

## The core decision

Three Telegram bots is the wrong shape. The right shape:

| Bot | Role | Surface |
|---|---|---|
| `@${WALTER_TELEGRAM_BOT_HANDLE}` | Outbound alerts only | Walter-VM monitors → push to me |
| `@${WALTER_OPENCLAW_BOT_HANDLE}` | Personal assistant — bidirectional | I talk to it, it reads my messages, it replies for me |

**No third bot.** OpenClaw IS the personal assistant. Adding a third loses the
context boundary (the assistant can't see what the alerter sent without a
relay) and adds another auth surface to manage.

## What OpenClaw covers

OpenClaw (openclaw.ai, self-hosted, Node 24+) connects to ALL of:

- WhatsApp (via Beeper or direct WA Business API)
- Telegram (the bot for outbound, plus your user account for read-only inbox)
- Slack, Discord, Google Chat
- iMessage, Signal (via Beeper bridge)
- Microsoft Teams, Matrix, Mattermost
- Instagram DMs (via Beeper bridge)

It's **bidirectional**: you message it, it reads on your behalf, it replies
when you authorize, it summarizes when you ask, it pings you on what matters.

## How it answers your specific use cases

### "Reply to messages for me when I'm busy"

Pattern: **pairing + pre-approved auto-reply rules**.

- New WhatsApp arrives → OpenClaw scores priority (urgent / can-wait / ignore)
- For "can-wait": auto-reply "Hey, recibí tu mensaje, te respondo en X horas"
  using a template you defined (Spanish for AR contacts, English for work, etc.)
- For "urgent": ping you on Telegram with summary + suggested reply, you
  approve via inline button → assistant sends.
- For "ignore" (newsletters, chain forwards): silent, queued for end-of-day
  digest.

The pattern is **never autonomous send without approval** for new contacts /
unusual context. That's the safety bar.

### "Tell me what's important"

Daily digest format (you can ask anytime, or schedule):

```
Daily — May 4, 2026

🔥 Urgent (action needed today)
  • Maria (WhatsApp): asks for the licitación proposal by Friday 6pm
  • Marcos (Slack #[company]-eng): Geyser plugin crashed in mainnet, needs review

📬 Worth seeing (no action)
  • Telegram: 3 group messages in #buenos-aires-tech
  • Email: Stripe invoice PDF (auto-archived)
  • Discord: tagged in #anaconda-team about MVP review

🗓️ Scheduled today
  • 16:00 — call with potential investor (Alex C.)
  • 18:00 — gym

🌚 Quiet
  • 47 messages auto-handled (low-priority replies, newsletters, etc.)
```

### "Schedule a coffee at 5pm Thursday from my chat with X"

OpenClaw + Calendar API integration:

1. You: "OpenClaw, agendá café con Maria jueves 5pm"
2. OpenClaw extracts: title="Café con Maria", when="next Thursday 17:00 BA"
3. Confirms: "Agendo en tu Calendar 'Personal' jueves 8 may 17:00, ¿OK?"
4. You: 👍
5. Inserts event via Google Calendar API.

Or fully passive: OpenClaw watches your Telegram chat with Maria, sees
"dale, jueves 5pm en Lattente?" → drafts the event → asks you to approve.

The calendar integration uses a Google Service Account scoped to a single
calendar (Personal), not your full account. Limits blast radius.

## Beeper — the unified-message layer

Beeper is **NOT** the assistant — it's the **transport**. Beeper bridges
WhatsApp/iMessage/Instagram/Signal/etc. into a single Matrix-compatible
inbox. OpenClaw connects to Beeper's local Matrix endpoint (instead of
each individual service) and gets one unified stream.

Why this matters:
- WhatsApp alone has no public API for personal accounts. Beeper bridges it
  legitimately via your phone session.
- iMessage requires a Mac running Beeper Mini relay or similar.
- Instagram doesn't expose DMs to apps directly. Beeper bridges it.

So the actual stack is:

```
   ┌──────────────────────────────────────────┐
   │ Phone (your real WA/iMessage/IG sessions)│
   └──────────────────┬───────────────────────┘
                      │ bridges / relays
                      ▼
   ┌──────────────────────────────────────────┐
   │ Beeper Cloud (Matrix homeserver)         │
   │    https://beeper.com — paid $10/mo OR   │
   │    self-hosted (more work, free)          │
   └──────────────────┬───────────────────────┘
                      │ Matrix protocol
                      ▼
   ┌──────────────────────────────────────────┐
   │ OpenClaw on Walter-VM                    │
   │  - reads incoming Matrix events          │
   │  - LLM via LiteLLM (Sonnet by default)   │
   │  - actions: reply, summarize, tag, queue │
   └──────────────────┬───────────────────────┘
                      │
              ┌───────┴────────┐
              │                │
    @${WALTER_OPENCLAW_BOT_HANDLE}   Google Calendar API
    (your inbox to it)    (event creation)
```

**Beeper Mini** (the cheaper iOS app) was killed by Apple. Beeper Cloud
($10/mo) is the only viable path for iMessage. WhatsApp/IG bridges work
on either tier.

## Where the cost lives

### LLM cost — use Sonnet by default, Opus only when reasoning matters

**Critical principle**: don't burn your Opus quota on routine assistant tasks.

| Task | Model | Why |
|---|---|---|
| Auto-reply scoring (urgent/can-wait/ignore) | Sonnet | Pattern recognition, no deep reasoning |
| Summarize a chat | Sonnet | Compression, no deep reasoning |
| Draft a reply in Spanish casual | Sonnet | Style, no deep reasoning |
| Calendar event extraction | Sonnet | Structured extraction |
| Write a long-form blog draft | Opus | Long context, quality matters |
| Plan complex multi-step task | Opus / Opus-thinking | Reasoning |
| Code review across 3 files | Opus | Reasoning + context |

LiteLLM virtual keys per use case, each pinned to a specific model:

```yaml
# litellm config.yaml (illustrative)
virtual_keys:
  - key: openclaw-routine
    models: [claude-3-7-sonnet]    # cheap, fast
    budget_max: 30/mo              # USD, enforces cap
  - key: openclaw-reasoning
    models: [claude-opus-4]        # premium
    budget_max: 5/mo               # tighter cap
  - key: operator-cli-personal
    models: [*]                    # any
    budget_max: 50/mo
  - key: n8n-workflow-runner
    models: [claude-3-7-sonnet]
    budget_max: 20/mo
```

Total budget: $105/mo cap across all automation. You see the dashboard at
llm.${WALTER_DOMAIN}, can yank any key if it runs hot.

### Subscription proxy — the honest answer

**Anthropic does NOT support subscription-as-API.** Claude Pro / Max
subscriptions cover Claude.ai web + Claude Code OAuth + Claude Desktop
OAuth. They are NOT exposed as a generic OpenAI-compatible endpoint.
Workarounds exist (claude-code-router, anthropic-cookie-relay, etc.) but:

- They scrape session cookies from a logged-in Claude Code instance.
- They violate Anthropic ToS (subscriptions are explicitly per-user, not for
  programmatic 24/7 use).
- Anthropic actively rate-limits and bans accounts caught doing this.

Your subscription stays for **interactive personal use** (Claude Desktop,
Claude Code on your laptop). For automation (n8n, OpenClaw, scripts), use
the Anthropic API key with budget caps in LiteLLM. Total monthly bill:
~$15-50/mo depending on volume. Cheaper than paying $200/mo for Claude
Max if your automation isn't constant.

If you really want to keep subscription-only:
- Run OpenClaw on Walter-VM with **Claude Code OAuth**: technically possible
  (OpenClaw supports OAuth providers), but the OAuth session lives in
  Claude Code's sandbox and isn't a stable transport for a 24/7 daemon.
- ChatGPT subscription via OpenClaw: explicitly supported per OpenClaw
  README. You log in to ChatGPT once, OpenClaw reuses that session. Same
  caveats around ToS.

**Operator's pragmatic choice**: keep Anthropic API + LiteLLM caps for
automation. Use Claude Pro for personal CLI / Desktop work. They serve
different threat models.

## Trust + safety boundaries

| Action | Default | Override |
|---|---|---|
| Read your messages for summary | ✅ allowed (operator-explicit invocation) | n/a |
| Reply with auto-template | ⚠️ requires per-contact opt-in (`OpenClaw, allow auto-reply on this thread`) | n/a |
| Send a new message you didn't draft | ❌ never | one-shot inline button approval |
| Create a calendar event | ✅ with confirmation | always |
| Modify an existing event | ⚠️ confirm | always |
| Pay for something | ❌ never | not even with confirmation — out of scope |
| Log into a new account | ❌ never | not even with confirmation |
| Read messages in chats with sensitive third parties ([Project B] patients, etc.) | ❌ blocked | manual override + logged |

Keep this list short. The longer it gets, the more Stockholm-syndrome you get
into auto-overriding. Tight default = good asistente.

## Phase K4 deployment plan

```
1. Beeper Cloud account ($10/mo)
   - Add WhatsApp bridge (scan QR with phone)
   - Add iMessage bridge (Beeper Mac app installed)
   - Add Instagram bridge (login)
   - Add Telegram bridge (your user account, optional)

2. OpenClaw on Walter-VM
   setup/walter-host/services/openclaw/
     compose.yml         - Node 24+ container
     env.template        - LITELLM_BASE_URL, BEEPER_HOMESERVER_URL,
                          BEEPER_TOKEN, ANTHROPIC_API_KEY (via LiteLLM)
     deploy.sh           - idempotent
   URL: claw.${WALTER_DOMAIN} (CF Tunnel + Access)

3. LiteLLM virtual keys
   - Create openclaw-routine (Sonnet, $30/mo cap)
   - Create openclaw-reasoning (Opus, $5/mo cap)
   - Inject via Infisical to OpenClaw env

4. Pairing
   - Operator messages @${WALTER_OPENCLAW_BOT_HANDLE} from Telegram
     → bot replies with pairing code, links Telegram identity to OpenClaw
   - Same flow for Beeper bridge: OpenClaw asks "I see WhatsApp messages,
     authorize?" via Telegram bot; you approve once.

5. Calendar integration
   - Create Google Service Account in walter-os GCP project
   - Share "Personal" calendar with the SA's email
   - Save SA JSON to Infisical workspace=walter-os env=dev key=GOOGLE_SA_JSON
   - OpenClaw reads it for calendar.events.insert calls

6. Daily digest schedule
   - Cron in OpenClaw: 09:00 BA → assemble overnight digest → send to bot
   - Cron 22:00 BA → end-of-day summary
```

ETA when Walter-VM is ready: ~3-4 hours of operator time + ~2 hours of agent
time (configs + scripts).

## Failure modes to expect

1. **Beeper bridges break occasionally** (WhatsApp pushes new TLS pinning,
   iMessage Apple updates). Plan for ~1 outage/quarter.
2. **LLM hallucinates priority scoring** for messages from unfamiliar
   contacts. Tune the system prompt + add "low confidence → ask operator".
3. **Time zone confusion** — calendar event extraction with "next Thursday"
   when it's Sunday in Argentina but Saturday in operator's location after
   travel. Always confirm timezone in event description.
4. **Group chats** — auto-reply in groups is socially weird. Default: mute
   auto-reply for groups, only DMs.

## What this skill does NOT cover

- Voice / phone calls — out of scope. Use call screening apps if you need it.
- Email auto-reply — Gmail has its own; OpenClaw can read for digest, but
  reply-by-email is high-risk (one wrong "Reply All" can fire ruined careers).
- Meeting transcription — separate tool (Otter, Granola, Fathom).

## References

- https://github.com/openclaw/openclaw
- https://docs.openclaw.ai/
- https://www.beeper.com/pricing
- skills/telegram-bot-cli/ — outbound notifications (separate bot)
- skills/telegram-summary/ — discrete inbound chat summaries via tdl
