# Workflow: Daily Standup Summarizer — Slack Threads to Standup Format

## Use case

Every morning, pull yesterday's messages from a designated Slack channel,
send them to an LLM with a standup summary prompt, and post the formatted
summary back to the same channel (or a dedicated `#standups` channel).

Useful for: async teams and remote workers who want a structured daily
briefing of what happened yesterday without reading through entire Slack
threads. Saves 5–10 minutes of reading per standup.

## Prerequisites

**n8n credentials required:**

- Slack Bot Token (OAuth 2.0) with scopes:
  - `channels:history` — to read messages
  - `chat:write` — to post the summary
  - `channels:read` — to resolve channel IDs

**External services required:**

- Slack workspace with the bot installed to the source and target channels
- LLM API access (Anthropic, OpenAI, or LiteLLM proxy)

## Customization points

- `SOURCE_CHANNEL_ID`: Slack channel to pull messages from
- `TARGET_CHANNEL_ID`: channel to post the summary to (can be the same)
- `LOOKBACK_HOURS`: how many hours back to look for messages (default: 24)
- `STANDUP_FORMAT`: the output format — you can ask the LLM for YESTERDAY /
  TODAY / BLOCKERS format, or a plain bullet list, or a thread-by-thread summary
- `POST_TIME`: when to run the workflow (default: 09:00 local time)
- `EXCLUDE_BOT_MESSAGES`: whether to skip messages from bots (default: true)

## Env vars

| Variable | Description | Example value |
|---|---|---|
| `SLACK_BOT_TOKEN` | Slack bot OAuth token | `xoxb-...` |
| `LLM_API_KEY` | LLM API key | `sk-ant-...` |
| `LLM_ENDPOINT` | LLM API endpoint | `http://localhost:4000/v1` |
| `SOURCE_CHANNEL_ID` | Slack channel to summarize | `C0123456789` |
| `TARGET_CHANNEL_ID` | Channel to post summary to | `C0123456789` |

Store Slack credentials in n8n's OAuth credential store.

## Walter-OS contexts

`work`

## Node overview

```
[Schedule Trigger]
    → Runs at 09:00 every weekday (Mon–Fri)

[Slack: Get Channel Messages]
    → POST https://slack.com/api/conversations.history
    → Channel: SOURCE_CHANNEL_ID
    → Oldest: now() - LOOKBACK_HOURS

[Code: Filter and Format Messages]
    → Remove bot messages if EXCLUDE_BOT_MESSAGES=true
    → Format: "User: message text" per message
    → Concatenate into a single string

[HTTP Request: LLM Summarize]
    → Prompt: "Summarize these Slack messages into a daily standup format.
      Use YESTERDAY / TODAY / BLOCKERS sections. Be concise. Messages:
      {concatenated_messages}"

[Code: Format Summary]
    → Add header with date and channel name
    → Append "Source: {channel}" footer

[Slack: Post Summary]
    → POST https://slack.com/api/chat.postMessage
    → Channel: TARGET_CHANNEL_ID
    → Text: formatted summary
```

## Authoring steps

1. Create a Slack app at api.slack.com. Add the required OAuth scopes.
2. Install the app to your workspace. Note the Bot Token.
3. Invite the bot to both the source and target channels.
4. In n8n, add Slack credentials with the bot token.
5. Create a Schedule Trigger (09:00 weekdays).
6. Add a Slack HTTP Request node to fetch yesterday's messages.
7. Add a Code node to filter bots and format messages for the LLM.
8. Add an HTTP Request node to call your LLM with the standup prompt.
9. Add a Code node to add headers and footers to the summary.
10. Add a Slack HTTP Request node to post the summary.
11. Test by running manually and checking the output in your target channel.
12. Export and save as `workflow.json` in your private overlay repo.
