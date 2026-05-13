---
name: ai-spend-tripwire
description: Track LLM API spend across Anthropic, OpenAI, and Google providers, project daily and monthly cost, alert when burn rate exceeds threshold, and circuit-break agent loops before they cost serious money. Use this skill when starting a long agentic session, when the user asks "how much have I spent on AI", "what's my Claude/GPT cost this month", "any unusual spend", or proactively before any task expected to take >30 minutes of agent time. Refuses to launch new agent loops if monthly budget projection exceeds limit.
---

# AI Spend Tripwire

Cost guardrail for the agentic stack. Reads usage data from each provider,
projects spend, alerts on anomalies, and can hard-stop runaway loops.

## What it tracks

**Anthropic (Claude API + Claude Code):**
- `ANTHROPIC_ADMIN_API_KEY` → `/v1/organizations/usage_report/messages` and
  cost endpoint, polled hourly.
- Claude Code local logs at `~/.claude/projects/*/conversations/*.jsonl`
  parsed via `ccusage` (or its equivalent) for per-session cost breakdown.

**OpenAI (Codex CLI + direct):**
- Codex JSONL logs at `~/.codex/sessions/*.jsonl` parsed by `ccusage`
  (which supports both Claude Code and Codex).
- `OPENAI_API_KEY` doesn't have a great cost API; rely on session logs +
  monthly dashboard scrape.

**Google (Gemini for nanobanana, etc.):**
- Session files at `~/.gemini/tmp/*/chats/session-YYYY-MM-DD.json`
- Free tier: 1,000 req/day. Paid: tracked via Google AI Studio dashboard
  (no public usage API as of May 2026).

**OpenRouter (if used as a gateway):**
- Native usage endpoint, polled hourly.

## Output and alerts

The skill maintains a status JSON at `~/.config/walter-os/spend-status.json`:

```json
{
  "updated_at": "2026-05-03T12:00:00Z",
  "today_usd": 4.32,
  "this_month_usd": 71.50,
  "projected_month_usd": 220.00,
  "monthly_budget_usd": 250.00,
  "burn_rate_per_hour": 0.18,
  "by_provider": {
    "anthropic": 52.00,
    "openai": 14.00,
    "google": 5.50
  },
  "alerts": []
}
```

Alert tiers:

- **Notice** — daily spend > 1.5x trailing-7-day average. Logs to file.
- **Warn** — projected monthly > 80% of budget. Telegram notification.
- **Critical** — projected monthly > 100% of budget OR single hour > $20.
  Slack + Telegram + the skill **refuses to launch new agent loops**
  until acknowledged with `walter-os ack-spend`.

## Circuit breakers

When a Claude Code or Codex session runs:

1. The skill checks current spend before allowing the session to start.
   If we're already in critical territory, it blocks.
2. During the session, every ~5 minutes the skill polls cost API. If burn
   rate doubles unexpectedly (typical of an agent looping on tool errors),
   it sends SIGTERM to the long-running process and notifies.

This is the protection against the classic "left Claude running overnight,
woke up to a $300 bill" scenario.

## Budgets

Defaults in `~/.config/walter-os/budget.json`:

```json
{
  "monthly_budget_usd": 250.00,
  "daily_soft_cap_usd": 15.00,
  "single_session_hard_cap_usd": 25.00,
  "burn_rate_alert_per_hour_usd": 5.00
}
```

Edit to taste. Budgets are soft (warning) except `single_session_hard_cap_usd`
which is enforced.

## Cost-saving recommendations

When spend is high, the skill proposes optimizations rather than just
alerting:

- **Prompt caching** — if you're calling Claude with the same system prompt
  repeatedly, enable cache (90% reduction on repeat input).
- **Batch API** — for non-realtime tasks (audit, periodic summarization),
  switch to Batch API (50% off).
- **Model routing** — if Sonnet/Opus is being used for tasks Haiku could
  handle, suggest the swap. The skill keeps a heuristic per task type.
- **Local model fallback** — when M2 Ultra/local LLM node has Ollama running,
  route low-stakes drafting to it.

## Integration with other skills

- `daily-supply-chain-audit` runs first thing each morning and notes
  current spend at the top of the report.
- `pr-review` includes spend status in the review summary if monthly
  spend > 50% of budget (so you're aware of cost when deciding to merge
  expensive AI-generated work).

## Limits

- Real-time accuracy depends on each provider's billing latency. Anthropic
  is fast (~hour), OpenAI moderate, Google Gemini lags up to 24h.
- The skill doesn't prevent spend retroactively — once tokens are sent,
  they're billed. The circuit breakers reduce *future* loss, not past.
- Free-tier usage doesn't show in $ figures but is tracked separately as
  "requests vs quota".

## References

- ccusage: parses Claude Code + Codex JSONL logs for per-model cost
- Anthropic Usage and Cost API: `/v1/organizations/usage_report/messages`
- ianlpaterson collector script: pattern for cross-CLI quota tracking
