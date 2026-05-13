# Workflow: Hackathon Team Formation — Form Responses to Balanced Teams

## Use case

Collect skill and interest responses from hackathon participants via
Tally or Typeform. Send the responses to an LLM to group participants into
balanced teams based on complementary skills. Post the team assignments to
a Discord or Telegram channel.

Useful for: hackathon organizers who need to form balanced teams quickly
without manual sorting. The LLM balances skill distribution across teams
and provides a rationale for each grouping.

## Prerequisites

**n8n credentials required:**

- Tally webhook (or Typeform webhook) — no API key needed for webhooks
- LLM API key (Anthropic, OpenAI, or LiteLLM proxy)
- Discord Bot token and target channel ID (or Telegram bot token + chat ID)

**External services required:**

- Tally or Typeform form with participant registration questions
- Discord server or Telegram group for participant communication
- LLM API access

**Form questions recommended:**

- Full name
- Discord/Telegram handle
- Primary skills (checkboxes: Frontend / Backend / Blockchain / AI/ML / Design / PM)
- Secondary skills (free text)
- Project type preference (free text or checkboxes)
- Availability (hours per day during the event)

## Customization points

- `TEAM_SIZE`: target team size (default: 4)
- `MAX_TEAMS`: maximum number of teams to form
- `SKILL_WEIGHTS`: priority order for skill balancing
- `DISCORD_CHANNEL_ID`: target channel for posting team assignments
- `ANNOUNCEMENT_TEMPLATE`: message template for team announcements

## Env vars

| Variable | Description | Example value |
|---|---|---|
| `LLM_API_KEY` | LLM API key | `sk-ant-...` |
| `LLM_ENDPOINT` | LLM API endpoint | `http://localhost:4000/v1` |
| `DISCORD_BOT_TOKEN` | Discord bot token | `MTk...` |
| `DISCORD_CHANNEL_ID` | Target channel ID | `123456789012345678` |

## Walter-OS contexts

`hackathons`

## Node overview

```
[Webhook Trigger: Tally/Typeform]
    → Receives form submission payload
    → One trigger per submission; workflow accumulates responses

[Postgres/Google Sheets: Store Response]
    → Persist each participant response for later batch processing

[Schedule/Manual Trigger: Run Matching]
    → Triggered manually or at a set time (e.g., 1h before event starts)

[Postgres/Google Sheets: Fetch All Responses]
    → Read all stored participant responses

[HTTP Request: LLM Team Formation]
    → Prompt: "Given these participants and their skills, form balanced teams
      of TEAM_SIZE. Each team should have at least one frontend, one backend,
      and (if possible) one designer. Return JSON with team assignments and
      a one-sentence rationale for each team."
    → Input: all participant data as JSON

[Code: Parse + Format]
    → Parse LLM JSON output into team assignments
    → Format each team as a readable Discord message block

[Discord: Post Team Assignments]
    → POST each team assignment as a message to DISCORD_CHANNEL_ID
    → Mention each participant by their Discord handle
```

## Authoring steps

1. Create your Tally or Typeform registration form with the recommended questions.
2. In n8n, create a Webhook trigger. Copy the URL into your form's webhook settings.
3. Add a Postgres or Google Sheets node to store each submission.
4. Create a second workflow (or add a manual trigger) to run team matching.
5. Add a node to fetch all stored responses.
6. Add an HTTP Request node to call your LLM with the team formation prompt.
7. Add a Code node to parse the response and format Discord messages.
8. Add a Discord node to post team announcements.
9. Test with sample participant data before the live event.
10. Export and save as `workflow.json` in your private overlay repo.
