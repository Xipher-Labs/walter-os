---
name: pricing-experiment
description: >-
  Structure a pricing experiment for a B2B or B2C product. Outputs: competitor
  anchor analysis, 3-tier structure (Starter / Pro / Scale), value metric
  selection (per-seat, usage-based, outcome-based), A/B test design with sample
  size and duration, and discount policy. Triggers on: pricing strategy,
  pricing experiment, how to price, pricing tiers, value metric, anchor pricing.
triggers:
  - pricing strategy
  - pricing experiment
  - how to price
  - pricing tiers
  - value metric
  - anchor pricing
---

# pricing-experiment

Structured pricing design and experiment skill. Use it to move from
"we don't know what to charge" to a defensible tier structure with a
testable A/B experiment design.

## When to use this skill

- Pre-launch: deciding what to charge before going live.
- Post-discovery pivot: new ICP or problem framing demands a fresh pricing model.
- Competitor repricing event: a key competitor changed their pricing page.
- Preparing a fundraise deck: investors want to see pricing logic, not just the number.

## When NOT to use this skill

- Before any customer discovery: run `customer-interview-synthesizer` first.
  Pricing without WTP data is guessing.
- Enterprise deals where pricing is fully negotiated per contract: this skill
  targets self-serve or assisted sales models.
- Physical goods pricing: cost-plus margin models are out of scope here.

## Inputs

- **Product description**: what it does in 2–3 sentences.
- **ICP description**: role, company size, pain being solved, expected usage pattern.
- **Competitor names + pricing URLs** (up to 5): used to build the anchor analysis.
- **Current ARR** (optional): helps calibrate tier sizing (e.g., Starter plan
  should not cannibalize current revenue).

## Outputs

### 1. Anchor Analysis Table

| Competitor | Starter price | Pro price | Value metric | Notable |
|---|---|---|---|---|
| [Competitor A] | $X/mo | $Y/mo | per seat | [feature gap] |
| [Competitor B] | $X/mo | $Y/mo | usage | [feature gap] |

### 2. Tier Structure

| Tier | Target user | Monthly price | Key features | CTA |
|---|---|---|---|---|
| Starter | [persona] | $X | [3-5 features] | Start free |
| Pro | [persona] | $Y | [5-8 features] | Start trial |
| Scale | [persona] | $Z | [8+ features] | Talk to us |

Tier naming follows the good-better-best principle. See
`references/pricing-frameworks.md` for the tier design logic.

### 3. Value Metric Recommendation

The value metric is what you charge based on (seats, API calls, outcomes).
Output includes: recommended metric + rationale + how it aligns with ICP value.

Common options:
- **Per-seat**: predictable for buyer; scales naturally for vendor.
- **Usage-based**: aligns with value delivered; requires usage metering.
- **Outcome-based**: highest alignment but hardest to measure and sell.

### 4. A/B Test Design

| Variable | Control | Variant | Success metric | Min sample | Duration |
|---|---|---|---|---|---|
| Starter price | $49/mo | $69/mo | Conversion rate | 200 signups/arm | 4 weeks |

Sample size formula reference: n = 2 × (Z_α + Z_β)² × p(1-p) / δ² where
p = baseline conversion rate, δ = minimum detectable effect.
Use an online calculator (e.g., Evan Miller's) for the actual calculation.

### 5. Discount Policy

- **Founder discount**: [N]% for first [N] customers, time-limited.
- **Annual discount**: 20% off monthly rate (reduces churn, improves cash flow).
- **Nonprofit policy**: 50% off Pro tier on verified 501(c)(3) or equivalent.
- **Churn-prevention offer**: one-time 30% off next 3 months before cancel.

## Example

**Product:** Developer metrics Slack bot for engineering managers.
**ICP:** EM at Series B startup, 10–30 engineers, GitHub + Datadog stack.

**Tier structure:**

| Tier | Target | Price | Key features | CTA |
|---|---|---|---|---|
| Starter | Solo EM | $0/mo | Weekly digest, 1 repo | Start free |
| Pro | Small team | $49/mo | Daily digest, 10 repos, custom KPIs | 14-day trial |
| Scale | Platform team | $199/mo | Unlimited repos, DORA metrics, API | Talk to us |

**Value metric:** per-team (flat fee per engineering team, not per seat) —
aligns with how EMs buy tools (team budget, not headcount).

**A/B test:** $49 vs $79 for Pro tier. Success metric: Pro trial starts.
Minimum sample: 150/arm. Duration: 3 weeks.

## Frameworks used

See `references/pricing-frameworks.md` for:
- Van Westendorp Price Sensitivity Meter (4 questions to find WTP range)
- Anchor pricing mechanics (decoy effect, tier ordering)
- Good-better-best tier design principles

## How it composes with other Walter-OS skills

- **Downstream of `customer-interview-synthesizer`**: WTP signals from synthesis
  feed directly into the anchor analysis and tier price points.
- **Feeds into `landing-page-fast`**: the pricing section copy comes directly
  from the tier structure table output.
- **Feeds into `cold-outreach-sequencer`**: pricing positioning and value metric
  language appear in the value-add outreach touch (Day 3).
- **With `competitor-radar`**: significant pricing changes by competitors trigger
  a fresh `pricing-experiment` run to validate your tier structure is still
  competitive.
- **With `weekly-review-coach`**: pricing experiment results (conversion rate
  changes) tracked as a KR.
