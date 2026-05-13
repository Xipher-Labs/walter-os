---
name: competitor-radar
description: >-
  Track competitor moves across changelog, pricing, hiring, and blog. Three
  phases: Setup (define competitors.yml), Snapshot (fetch and diff current
  state), Synthesis (emit weekly change report). Uses WebFetch only, no
  external dependencies. Triggers on: competitor radar, track competitors,
  competitor changes, what changed at.
triggers:
  - competitor radar
  - track competitors
  - competitor changes
  - what changed at
---

# competitor-radar

Weekly competitive intelligence skill. Batch operation: define competitors
once, run a snapshot weekly, read the synthesis report. No external
subscriptions or monitoring services required.

## When to use this skill

- Weekly competitive intelligence sweep: run on Mondays or before the
  Friday `weekly-review-coach` session.
- Before a pricing change: verify your anchor analysis is still current.
- Before a fundraise: investors will ask "who else is doing this?"
- When a prospect mentions a competitor you haven't tracked before: add
  it to the config and run a fresh snapshot.

## When NOT to use this skill

- Real-time monitoring: this is a batch skill. For real-time alerts, use
  Google Alerts or a dedicated monitoring service.
- Legal intelligence (M&A signals, patent filings): use a proper CI firm.
- Login-gated pages: WebFetch cannot authenticate. Public pages only.

## Phase A — Setup

Define your competitor list in:

```
~/.config/walter-os/state/competitors.yml
```

**This file is operator-private and must never be committed to any repo.**

Schema:

```yaml
competitors:
  - name: Competitor Name
    changelog_url: https://competitor.com/changelog
    pricing_url: https://competitor.com/pricing
    careers_url: https://competitor.com/jobs
    blog_url: https://competitor.com/blog
```

See `references/sample-competitors.yml` for a filled example with three
fictional companies.

**All four URL fields are optional**: include only pages that exist and are
publicly accessible. Omit fields where the competitor has no public page.

## Phase B — Snapshot

For each URL in `competitors.yml`, the skill:

1. Calls `WebFetch` to retrieve the current page content.
2. Stores the result at:
   ```
   ~/.config/walter-os/state/competitor-snapshots/YYYY-MM-DD/<competitor-name>/<page>.txt
   ```
   Where `<page>` is one of: `changelog`, `pricing`, `careers`, `blog`.
3. Computes a line-level diff against the previous snapshot for the same
   URL using Python's `difflib.unified_diff` (no system dependencies).
4. Emits the raw diff per page — additions (+) and removals (-).

**If no previous snapshot exists** for a URL (first run), the skill logs
"baseline captured" and skips the diff. The diff will be available on the
next run.

### Snapshot storage structure

```
~/.config/walter-os/state/
  competitor-snapshots/
    2026-05-12/
      acme-analytics/
        changelog.txt
        pricing.txt
        careers.txt
        blog.txt
    2026-05-05/
      acme-analytics/
        changelog.txt
        ...
```

## Phase C — Synthesis

After Phase B, the skill reads all diffs and produces a structured weekly
report:

```
~/.config/walter-os/state/competitor-snapshots/YYYY-MM-DD/report.md
```

**Report structure:**

```markdown
# Competitor Intelligence Report: YYYY-MM-DD

## New Features

[Inferred from changelog diffs. One bullet per inferred feature.]
- **Competitor A**: Added [feature description] (inferred from: "+New: Export to CSV")
  Significance: medium — closes a gap with our roadmap Q3 item.

## Pricing Changes

[Inferred from pricing page diffs.]
- **Competitor B**: Removed free tier (inferred from: pricing page no longer
  mentions "free forever")
  Significance: high — opportunity to capture their churning free users.

## Hiring Signals

[New job titles appearing on careers page diffs.]
- **Competitor C**: Posted 2 new roles: "ML Engineer" and "Data Platform Lead"
  Significance: low — suggests investment in ML features, 6-12 month horizon.

## New Content

[Blog post titles that appeared since last snapshot.]
- **Competitor A**: "How We Scaled to 10,000 Customers" — likely a growth
  announcement or case study signal.
  Significance: low — monitor for customer references.

---

## Summary

[2-3 sentence overall assessment of the week's competitive movements.]

**Recommended actions:**
- [ ] Run `pricing-experiment` in response to Competitor B's free tier removal.
- [ ] Add Competitor A's new CSV export to next sprint's feature backlog discussion.
```

**Significance ratings:** high / medium / low with reasoning. These are
inferences, not facts. The operator should verify significant findings before
acting on them.

## Outputs

Per weekly run, the skill writes:

- **Snapshot files** at `~/.config/walter-os/state/competitor-snapshots/YYYY-MM-DD/<competitor>/<page>.txt`
  (one file per tracked URL, per competitor).
- **Weekly report** at `~/.config/walter-os/state/competitor-snapshots/YYYY-MM-DD/report.md`
  (structured synthesis: new features, pricing changes, hiring signals, new content).

All output is operator-private and out-of-repo. Files persist until
manually deleted — they form a historical record of competitor changes.

## Limitations

- **JavaScript-rendered pages**: WebFetch retrieves raw HTML/text. Pages
  that load content dynamically via JavaScript may not capture all visible
  content. If a competitor's pricing page shows blank diffs, it is likely
  JS-rendered.
- **Login-gated content**: pricing tiers behind a login, private changelogs,
  and internal job boards are out of scope.
- **Synthesis is inference**: the skill infers meaning from text changes.
  A line removed from the pricing page may be a redesign, not a price drop.
  Verify significant findings directly on the competitor's website.
- **Rate limiting**: if running snapshots for many competitors on the same
  day, WebFetch may be throttled. Space requests if needed.

## Example

**Three fictional competitors configured:** Acme Analytics, BetaCorp, GammaTools.

**Sample diff snippet (Acme Analytics, pricing.txt):**

```diff
--- 2026-05-05/acme-analytics/pricing.txt
+++ 2026-05-12/acme-analytics/pricing.txt
@@ -12,6 +12,8 @@ Pro Plan: $49/month
-  - Up to 10 repositories
+  - Up to 25 repositories
+  - DORA metrics included
   - Slack integration
   - Email support
```

**Corresponding synthesis report entry:**

> **Acme Analytics** (pricing): Expanded Pro plan limit from 10 to 25
> repositories and added DORA metrics to the Pro tier.
> Significance: **high** — if our Pro plan has a lower repo limit, prospects
> comparing the two will see a feature gap. Recommend checking our tier limits.
> Recommended action: run `pricing-experiment` to evaluate tier rebalancing.

## How it composes with other Walter-OS skills

- **Feeds into `weekly-review-coach`**: run the radar before Friday's
  review session; significant findings belong in "what surprised you."
- **Feeds into `pricing-experiment`**: a significant competitor pricing
  change is a trigger to re-run the anchor analysis and possibly rebalance
  tiers.
- **With `content-writer`**: a competitor's new content announcement can
  be a prompt for a response blog post (counterpoint or differentiation angle).
