# Workflow: GitHub Issue Triage — LLM Classification + Plane Routing

## Use case

When a new GitHub issue is created, call an LLM to classify its severity
(P0/P1/P2/P3), type (bug/feature/question/docs), and suggested labels.
Apply labels via the GitHub API, post a triage comment on the issue, and
create a corresponding task in Plane (or Linear/Jira) with the severity and
type pre-filled.

Useful for: high-volume repos where manual triage is a bottleneck. The LLM
classification handles the first pass; humans confirm before escalation.

## Prerequisites

**n8n credentials required:**

- GitHub Personal Access Token (repo scope, or fine-grained with issues:write)
- LLM API key (Anthropic, OpenAI, or local LiteLLM proxy endpoint)
- Plane API key (if routing to Plane) or Linear API key (if routing to Linear)

**External services required:**

- GitHub repository (public or private)
- Plane or Linear workspace
- LLM API access (or LiteLLM proxy running locally)

## Customization points

- `REPO_OWNER`: GitHub organization or user
- `REPO_NAME`: repository name
- `LABEL_PREFIX`: prefix to apply to auto-triage labels (e.g., `triage:`)
- `SEVERITY_LABELS`: the four severity label names you use (P0/P1/P2/P3 or S1/S2/S3/S4)
- `LLM_MODEL`: which model to call for classification
- `PLANE_PROJECT_ID`: target Plane project for new tasks
- `TRIAGE_COMMENT_TEMPLATE`: the comment template the bot posts on each issue

## Env vars

| Variable | Description | Example value |
|---|---|---|
| `GITHUB_TOKEN` | GitHub PAT with repo scope | `ghp_...` |
| `LLM_API_KEY` | API key for LLM provider | `sk-ant-...` |
| `LLM_ENDPOINT` | LLM API endpoint (use LiteLLM proxy URL for local models) | `http://localhost:4000/v1` |
| `PLANE_API_KEY` | Plane API key | `plane_api_...` |
| `PLANE_WORKSPACE_SLUG` | Your Plane workspace slug | `my-workspace` |

Store these in n8n's credential store.

## Walter-OS contexts

`projects-personal`, `work`

## Node overview

```
[Webhook Trigger: GitHub Issue Opened]
    → Listens for issues.opened event
    → Configure in GitHub repo Settings → Webhooks

[HTTP Request: LLM Classification]
    → POST /v1/messages (Anthropic) or /v1/chat/completions (OpenAI)
    → Prompt: "Classify this GitHub issue by severity (P0/P1/P2/P3) and
      type (bug/feature/question/docs). Return JSON."
    → Input: issue.title + issue.body

[Code: Parse LLM Response]
    → Extract { severity, type, labels, summary } from LLM JSON output
    → Validate severity is one of P0/P1/P2/P3

[GitHub: Add Labels]
    → PATCH /repos/{owner}/{repo}/issues/{number}/labels
    → Add: [severity label, type label, "auto-triaged"]

[GitHub: Post Triage Comment]
    → POST /repos/{owner}/{repo}/issues/{number}/comments
    → Body: triage summary + classification rationale

[Plane: Create Task]
    → POST /api/v1/workspaces/{slug}/projects/{id}/issues/
    → Title: "[TRIAGE] " + issue title
    → Priority mapped from severity (P0 → urgent, P1 → high, etc.)
    → Link back to GitHub issue URL
```

## Authoring steps

1. In your GitHub repo, go to Settings → Webhooks → Add webhook.
2. Set the payload URL to your n8n webhook URL.
3. Set Content type to `application/json`.
4. Select event: `Issues`.
5. In n8n, create a workflow with a Webhook trigger.
6. Add an HTTP Request node to call your LLM with the classification prompt.
7. Add a Code node to parse the JSON response.
8. Add a GitHub HTTP Request node to apply labels.
9. Add a GitHub HTTP Request node to post a triage comment.
10. Add a Plane HTTP Request node to create the linked task.
11. Test by creating a test issue in your repo.
12. Export and save as `workflow.json` in your private overlay repo.
