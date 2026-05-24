# n8n workflows

Walter-OS ships **six curated n8n workflow suggestions** in
`n8n/workflows/`. Each workflow is a JSON export from n8n plus a
`README.md` explaining credentials, triggers, and expected output.

> The `n8n/workflows/` directory is part of the operator-contexts PR and
> is delivered as a starter catalogue; operators are expected to fork +
> customize for their stack.

## Importing a workflow

1. Open n8n at `https://n8n.your-domain`.
2. Go to **Integrations → Import Workflow**.
3. Select the JSON file from `n8n/workflows/<workflow>/workflow.json`.
4. Configure the credentials and trigger settings per the workflow's
   `README.md`.

## Bundled workflows

| Workflow | What it does |
|---|---|
| `content-publishing` | Cross-posts approved content to Twitter/X, LinkedIn, Mastodon on a schedule |
| `ai-cost-tracking` | Ingests LiteLLM spend logs, categorizes by project, posts weekly digest to Telegram |
| `github-triage` | Labels new GitHub issues, assigns to Plane, pings relevant channel |
| `expense-categorization` | Reads bank export CSVs, classifies transactions, writes to Metabase |
| `hackathon-team-formation` | Matches available skills to project requirements, notifies team channel |
| `customer-interview-synthesis` | Ingests interview transcripts, extracts themes, drafts summary doc |

Each workflow `README.md` documents:

- **Required credentials** — what n8n credentials to configure
- **Trigger configuration** — webhook vs scheduled vs manual
- **Expected output format** — Metabase row / Slack message / Markdown file
- **Cost estimate** — rough per-execution LLM cost via Walter-Bridge

## Authoring a new workflow

1. Build + test the workflow in the n8n UI.
2. Export via **Workflows → … → Download** → save as
   `n8n/workflows/<slug>/workflow.json`.
3. Write a `README.md` documenting the four bullets above.
4. If the workflow uses LLM calls, route them through Walter-Bridge so
   they show up in the spend dashboard.
5. Commit + PR.

## Related

- [`walter-bridge.md`](walter-bridge.md) — route LLM calls through LiteLLM
  for cost tracking
- `skills/ai-spend-tripwire/SKILL.md` — circuit-breaker for runaway LLM spend
  triggered by misconfigured n8n workflows
