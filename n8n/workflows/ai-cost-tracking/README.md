# Workflow: AI Cost Tracking — LiteLLM Usage to Postgres

## Use case

Poll the LiteLLM `/usage` endpoint on a schedule, normalize the response
into structured rows (model, tokens, cost, timestamp), and insert them into
a Postgres table for analysis in Metabase or another BI tool.

Useful for: monitoring LLM API spend across all Walter-OS agents and tools,
triggering spend alerts, and generating weekly cost reports.

Complements the `ai-spend-tripwire` Walter-OS skill with persistent storage.

## Prerequisites

**n8n credentials required:**

- Postgres connection (local LLM node Postgres or managed Postgres)
- LiteLLM API key (if your LiteLLM instance requires auth)

**External services required:**

- LiteLLM running (Walter-OS installs it as part of the AI stack)
- Postgres database with a `llm_usage` table (schema below)

**Postgres table schema:**

```sql
CREATE TABLE llm_usage (
  id          SERIAL PRIMARY KEY,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  model       TEXT NOT NULL,
  provider    TEXT,
  input_tokens  INTEGER,
  output_tokens INTEGER,
  total_tokens  INTEGER,
  cost_usd    NUMERIC(12, 6),
  request_id  TEXT,
  tags        JSONB
);
```

## Customization points

- `POLL_INTERVAL`: how often to fetch usage (default: every 15 minutes)
- `LITELLM_HOST`: hostname of your LiteLLM instance
- `COST_ALERT_THRESHOLD_USD`: daily spend threshold to trigger an alert
- `LOOKBACK_MINUTES`: how many minutes back each poll fetches (overlap is safe)

## Env vars

| Variable | Description | Example value |
|---|---|---|
| `LITELLM_HOST` | LiteLLM API base URL | `http://localhost:4000` |
| `LITELLM_API_KEY` | LiteLLM API key (if auth enabled) | `sk-...` |
| `POSTGRES_HOST` | Postgres host | `localhost` |
| `POSTGRES_DB` | Database name | `walteros` |
| `POSTGRES_USER` | Database user | `walter` |

Store these in n8n's credential store.

## Walter-OS contexts

All contexts (work, projects-personal, personal, hackathons)

## Node overview

```
[Schedule Trigger]
    → Runs every 15 minutes (configurable)

[HTTP Request: LiteLLM Usage]
    → GET http://LITELLM_HOST/usage?start_time=REPLACE&end_time=REPLACE
    → Auth: Bearer LITELLM_API_KEY

[Code: Normalize]
    → Flatten response into rows: { model, provider, input_tokens,
      output_tokens, total_tokens, cost_usd, request_id, tags }
    → One item per usage record

[Postgres Insert]
    → INSERT INTO llm_usage (...) VALUES (...)
    → Operation: Insert
    → Table: llm_usage

[IF: Cost Threshold Exceeded?]
    → Compare daily total from Postgres against COST_ALERT_THRESHOLD_USD

[HTTP Request: Alert]
    → POST to Slack/Telegram with spend summary (conditional)
```

## Authoring steps

1. Create the `llm_usage` table in your Postgres instance using the schema above.
2. In n8n, create a new workflow named "AI Cost Tracking".
3. Add a Schedule Trigger node (every 15 minutes).
4. Add an HTTP Request node to call LiteLLM `/usage`.
5. Add a Code node to normalize the response into individual rows.
6. Add a Postgres node to insert rows into `llm_usage`.
7. Add an IF node to check if today's total exceeds the threshold.
8. Add an HTTP Request node for Slack/Telegram alert (connected to IF true branch).
9. Test with a manual trigger. Verify rows appear in the database.
10. Export and save as `workflow.json` in your private overlay repo.
