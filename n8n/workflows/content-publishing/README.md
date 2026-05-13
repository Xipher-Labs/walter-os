# Workflow: Content Publishing — Cross-Post Markdown to Social Platforms

## Use case

Cross-post a Markdown file to X/Twitter, LinkedIn, and Bluesky in one
operation. Triggered by a webhook or a file drop. Parses the Markdown into
plain text, extracts the first paragraph as the post body, and sends it to
each platform via their respective APIs.

Useful for: publishing blog posts, release announcements, and project
updates across social platforms without manual copy-paste.

## Prerequisites

**n8n credentials required:**

- X/Twitter Developer App credentials (OAuth 1.0a or OAuth 2.0, write scope)
- LinkedIn OAuth 2.0 app (w_member_social scope)
- Bluesky App Password (from bsky.app → Settings → App Passwords)

**External services required:**

- Active accounts on each target platform
- (Optional) A file storage location n8n can read from (local path or S3)

**Walter-OS services assumed:**

- n8n running and accessible
- No Postgres required for this workflow

## Customization points

- `WEBHOOK_PATH`: the URL path suffix for the webhook trigger (e.g., `/cross-post`)
- `MAX_CHAR_COUNT`: character limit to truncate the post body (default 280 for X)
- `INCLUDE_URL`: whether to append a canonical URL to each post (true/false)
- `PLATFORMS`: which platforms to post to (remove nodes for platforms you don't use)
- `HASHTAGS`: static hashtags to append to every post

## Env vars

| Variable | Description | Example value |
|---|---|---|
| `N8N_WEBHOOK_BASE_URL` | Public URL of your n8n instance | `https://n8n.example.com` |
| `TWITTER_API_KEY` | X/Twitter API key | `abc123...` |
| `TWITTER_API_SECRET` | X/Twitter API secret | `xyz789...` |
| `LINKEDIN_CLIENT_ID` | LinkedIn OAuth app client ID | `86abc...` |
| `BLUESKY_HANDLE` | Your Bluesky handle | `yourname.bsky.social` |

Store these in n8n's credential store, not as plain env vars.

## Walter-OS contexts

`projects-personal`, `work`

## Node overview

```
[Webhook Trigger]
    → Receives POST with { markdown: "...", url: "https://...", tags: [...] }

[Markdown Parser]
    → Converts Markdown to plain text
    → Extracts first paragraph as post body
    → Truncates to MAX_CHAR_COUNT

[IF: Include URL?]
    → Appends canonical URL if INCLUDE_URL=true

[X/Twitter HTTP Request]
    → POST https://api.twitter.com/2/tweets
    → Body: { text: "<post body>" }
    → Auth: OAuth 1.0a

[LinkedIn HTTP Request]
    → POST https://api.linkedin.com/v2/ugcPosts
    → Body: LinkedIn UGC post schema
    → Auth: OAuth 2.0 Bearer

[Bluesky HTTP Request]
    → POST https://bsky.social/xrpc/com.atproto.repo.createRecord
    → Body: Bluesky post record schema
    → Auth: App Password (Basic)

[Error Handler]
    → On failure: send Slack/Telegram notification with error details
```

## Authoring steps

1. In n8n, create a new workflow named "Content Publishing — Cross-Post".
2. Add a Webhook node. Set method to POST. Note the generated webhook URL.
3. Add a Code node to parse the Markdown payload and extract the post body.
4. Add an IF node to optionally append the URL.
5. Add three parallel HTTP Request nodes (one per platform) with the correct
   API endpoints and credentials.
6. Add an error handler node connected to each HTTP Request on failure.
7. Test with a sample payload via `curl -X POST <webhook-url> -d '{"markdown":"Test post."}'`.
8. Export and save as `workflow.json` in your private overlay repo.
