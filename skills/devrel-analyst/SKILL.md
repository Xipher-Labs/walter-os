---
name: devrel-analyst
description: Query the walter_devrel_analytics Postgres database to surface DevRel content performance insights (top threads, optimal posting hours, hook pattern analysis, ROI per content piece, weekly digest). Use before drafting new content on a topic, when the user asks about engagement trends, or for the weekly digest workflow. Work/ context only — requires ANALYTICS_DB_URL. Supports --dry-run for CI. Read-only.
---

# devrel-analyst

> Skill: DevRel Analytics Querier
> Context: work/ only ([Company] DevRel)
> Phase V — Part D (AC-13, AC-16)
>
> Refs: docs/specs/devrel-analytics-stack.md

## What this skill does

Queries the `walter_devrel_analytics` Postgres database and returns structured
insights about DevRel content performance. Used:

1. Directly from CLI: `walter-os analyst <query> [args]`
2. By the `devrel-writer` agent before drafting content (AC-16 feedback loop)
3. By the weekly digest workflow (AC-14)
4. By the anomaly detection workflow (AC-15)

It reads only — never writes to the analytics DB.

## Supported queries

### `top_threads(since, limit)`

Returns the top N content pieces by total engagement since a given date.

```
$ python3 skills/devrel-analyst/scripts/query.py top_threads --since 30d --limit 5
```

Output (markdown):

```markdown
## Top 5 Threads — Last 30 Days

| Rank | Title | Platform | Engagement | Has Code | Has Image |
|------|-------|----------|------------|----------|-----------|
| 1 | How we cut RPC latency by 40%... | twitter | 2847 | yes | no |
| 2 | Yellowstone gRPC streaming guide | youtube | 1203 | yes | yes |
...
```

### `optimal_hours(platform)`

Returns the hour-of-day × day-of-week heatmap with best engagement windows.

```
$ python3 skills/devrel-analyst/scripts/query.py optimal_hours --platform twitter
```

### `pattern_match(topic)`

Finds what hooks, formats, and attributes correlated with high engagement
for content about a given topic.

```
$ python3 skills/devrel-analyst/scripts/query.py pattern_match --topic "solana-rpc"
```

Used by `devrel-writer` before drafting new content on a topic.

### `roi_per_content_piece(since)`

Compares ad spend vs engagement for each promoted content piece.

```
$ python3 skills/devrel-analyst/scripts/query.py roi_per_content_piece --since 90d
```

### `weekly_digest()`

Produces a full weekly Markdown digest for `~/sync/wiki/devrel/insights/`.

```
$ python3 skills/devrel-analyst/scripts/query.py weekly_digest
```

## Invocation from other agents

```python
# In devrel-writer agent context
import subprocess, json

result = subprocess.run(
    ["python3", "skills/devrel-analyst/scripts/query.py",
     "pattern_match", "--topic", topic, "--dry-run"],
    capture_output=True, text=True, timeout=30
)
insights = result.stdout
```

Or via skill invocation pattern:

```
skills/devrel-analyst/scripts/query.py pattern_match --topic "solana-rpc" --since 30d
```

## Security notes

- All topic/platform strings passed as arguments are sanitized before
  being interpolated into SQL (parameterized queries via psycopg2).
- Any content inserted into LLM prompts (e.g., hook text, titles) is
  sanitized via `sanitize_for_prompt()` before injection.
- Skill is read-only — no INSERT/UPDATE/DELETE.
- DB credentials from `ANALYTICS_DB_URL` env var or Infisical.

## Dry-run mode

All queries support `--dry-run`. In dry-run mode, the skill returns a
mock/template result without connecting to Postgres. Useful for:
- Testing agent pipelines without a live DB
- CI validation of the skill's output format

## Context loading

Auto-loaded only in work/ context ([Company] DevRel). Not loaded in
projects-personal/ or personal/.

```yaml
# contexts/work/AGENTS.md references this skill
skills:
  - devrel-analyst
```
