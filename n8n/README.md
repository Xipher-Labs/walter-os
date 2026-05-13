# n8n Workflow Suggestions for Walter-OS

This directory contains curated n8n workflow suggestions for Walter-OS
operators. Each subdirectory documents one workflow that complements a
Walter-OS context.

## What you will find here

Each workflow directory contains:

- `README.md` — use case, prerequisites, customization points, env vars,
  and a node overview describing the expected flow.
- `workflow.json.template` — documentation-first placeholder showing the
  expected n8n node structure. This is **not** directly importable into n8n.
  Placeholder values are marked with `REPLACE_WITH_*` conventions.

## Authoring approach

These templates are **documentation-first**. The real workflow JSON is
tightly coupled to your n8n version and credential IDs on your specific
instance. Shipping pre-authored JSON would create more problems than it
solves.

**The recommended flow:**

1. Read the workflow `README.md` to understand what to build.
2. Open your n8n instance and build the workflow using the node overview as
   a guide.
3. Test and tune the workflow in your n8n UI.
4. Export the finished workflow (n8n UI → Workflows → Export) and save the
   real JSON alongside the template.
5. Commit your `workflow.json` to your private `walter-personal` repo (not
   this public repo — it will contain your credential IDs and webhook URLs).

## How to import a workflow into n8n

**Via the n8n UI:**

1. Go to Workflows in the sidebar.
2. Click the `+` button → Import from File.
3. Select your exported `workflow.json`.

**Via the n8n CLI:**

```bash
n8n import:workflow --input=workflow.json
```

**Via the n8n API:**

```bash
curl -X POST https://<your-n8n-host>/api/v1/workflows \
  -H "X-N8N-API-KEY: <your-api-key>" \
  -H "Content-Type: application/json" \
  -d @workflow.json
```

## How to contribute a workflow

If you have built a workflow from one of these templates and want to share it:

1. Export the workflow from your n8n instance.
2. Replace all personal values (webhook URLs, credential IDs, channel IDs,
   spreadsheet IDs) with `REPLACE_WITH_*` placeholders.
3. Rename the file from `workflow.json` to `workflow.json.template`.
4. Update the workflow's `README.md` with actual node names from your export.
5. Open a PR against `v0.2.0-walter-oss` or later branch.

## Context mapping

| Workflow | Relevant Walter-OS contexts |
|---|---|
| `content-publishing` | projects-personal, work |
| `ai-cost-tracking` | all |
| `github-issue-triage` | projects-personal, work |
| `expense-categorization` | personal |
| `hackathon-team-formation` | hackathons |
| `daily-standup-summarizer` | work |

## Walter-OS services assumed

Most workflows assume a Walter-OS installation with:

- n8n running (via `docker-compose` or as a standalone service)
- Postgres available (local LLM node or managed)
- Credentials configured in n8n for the services used

See `setup/walter-host/services/n8n/` for the n8n service configuration.
