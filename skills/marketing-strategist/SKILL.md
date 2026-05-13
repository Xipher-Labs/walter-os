---
name: marketing-strategist
description: Marketing strategy layer for founders — SEO audit, content calendar, social strategy with platform KPIs, and distribution playbook covering HN, Reddit, LinkedIn, X, and niche communities. Strategy only; content production is content-writer.
---

# marketing-strategist

Strategy-level marketing for early-stage founders. Produces four interconnected
artifacts: SEO audit with keyword gap analysis, a 12-week rolling content calendar,
platform-specific social strategy with cadence and KPIs, and a distribution playbook.
This skill does NOT produce content — use `content-writer` for that.

## When to use this skill

- You are building or refreshing your go-to-market plan.
- You want to audit your current SEO posture and identify keyword gaps.
- You need a structured content calendar to coordinate across channels.
- You want a social media strategy with measurable KPIs per platform.
- You are launching a product and need a distribution playbook.

## When NOT to use this skill

- You need to write the actual content (use `content-writer`).
- You want competitive intelligence signals (use `competitor-radar` first, then
  feed findings into this skill).
- You are looking for a landing page copy or page structure (use `landing-page-fast`).
- You already have a marketing strategy and just need execution support.

## Inputs

- **Product description**: one paragraph describing what you sell, who buys it,
  and what problem it solves.
- **Current channels**: which channels you are active on (or none).
- **Existing content**: URLs of top-performing content, if any.
- **Target ICP** (Ideal Customer Profile): job title, company size, pain points.
- **Competitors**: 2-5 competitors to benchmark against.
- **Time horizon**: number of weeks to plan for (default 12).
- **Budget** (optional): monthly marketing budget for paid amplification.

## Outputs

1. **SEO audit**: keyword gap analysis (20-30 keywords), technical SEO checklist
   against the reference at `references/seo-checklist.md`, and a prioritized
   action list (P1/P2/P3).
2. **12-week content calendar**: rolling table with columns Week / Theme /
   Content type / Target keyword / Distribution channels / Owner / Status.
   Template at `references/content-calendar-template.md`.
3. **Social strategy**: per-platform plan covering posting cadence, content
   format mix, KPI targets, and engagement tactics for the channels relevant
   to your ICP.
4. **Distribution playbook**: tiered channel list with posting format, best
   time-of-day, community rules to observe, and launch sequencing. Full channel
   guide at `references/distribution-channels.md`.

## Sample usage

```
Skill: marketing-strategist

Product: B2B SaaS for construction project management. Helps PMs track budgets
  and subcontractor schedules. Target customer: construction PM at firms with
  10-100 employees.

Current channels: LinkedIn (500 followers, irregular posts). No SEO.

Competitors: Procore, Buildertrend, CoConstruct.

Time horizon: 12 weeks.

Budget: $500/month.
```

Expected output: SEO audit flagging 20 keywords Procore ranks for that we do not,
a 12-week content calendar with 3 posts/week, a LinkedIn-first social strategy
(ICP is on LinkedIn, not X), and a distribution playbook prioritizing LinkedIn
newsletter + targeted Reddit communities (r/construction, r/projectmanagement).

## How it composes with other Walter-OS skills

- `competitor-radar` — run competitor-radar weekly to feed fresh signals into
  the content calendar themes and SEO keyword gaps.
- `content-writer` — this skill produces the strategy; content-writer executes
  each piece in the calendar. Pass the calendar row to content-writer as context.
- `landing-page-fast` — the SEO keyword list from this skill feeds into
  landing-page-fast for on-page optimization and page architecture.
- `customer-interview-synthesizer` — interview themes should inform the content
  calendar themes. Run synthesizer first if you have raw interview data.

## Prompt for your AI

```
I need a marketing strategy. Here is my context:

Product: [one paragraph]
Current channels: [list or "none"]
Existing content URLs: [list or "none"]
Target ICP: [job title, company size, pain points]
Competitors: [2-5 names]
Time horizon: [weeks, default 12]
Budget: [monthly USD or "none"]

Please output:
1. SEO audit: keyword gap analysis (20-30 keywords ranked by search volume and
   difficulty), technical SEO priority list (P1/P2/P3)
2. 12-week content calendar table: Week | Theme | Content type | Keyword |
   Channels | Owner | Status
3. Social strategy: per-platform (limit to channels where my ICP is active),
   with weekly cadence, format mix, and 3 KPIs per platform
4. Distribution playbook: Tier 1/2/3 channels with posting format and cadence
```
