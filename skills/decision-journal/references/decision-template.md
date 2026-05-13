# Decision Journal Entry Template

File path: `~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md`

---

```markdown
---
slug: <kebab-case-identifier>
date: YYYY-MM-DD
revisit_date: YYYY-MM-DD
confidence: <1-10>
status: open | closed | extended
---

# Decision: <Human-readable title>

## Context

<!-- What situation prompted this decision? What constraints apply? What is the
time pressure, if any? -->

[Your context here]

## Options Considered

<!-- List 2-5 alternatives that were seriously evaluated. For each, note the
main upside and downside. -->

| Option | Upside | Downside |
|---|---|---|
| Option 1: [name] | | |
| Option 2: [name] | | |
| Option 3: [name] | | |

## Selected Option

**[Name of option chosen]**

## Rationale

<!-- Why this option over the others? What trade-offs were consciously accepted?
What information was missing that would change the answer? -->

[Your rationale here]

## Expected Outcome and Success Criteria

<!-- What should be measurably true in 30/60/90 days if this was the right call?
Be specific — vague success criteria make retrospectives useless. -->

- In 30 days: [measurable outcome]
- In 60 days: [measurable outcome]
- In 90 days: [measurable outcome]

## Confidence Level

**[X]/10** — [One sentence explaining the main source of uncertainty]

## Revisit Date

**[YYYY-MM-DD]** — Set automatically to 90 days from decision date unless
overridden.

---

## Retrospective (fill in on revisit date)

**Retrospective date**: [YYYY-MM-DD]

**What actually happened**:

[Describe the actual outcome]

**Success criteria assessment**:

| Criterion | Met? | Notes |
|---|---|---|
| 30-day: [criterion] | Yes / Partially / No | |
| 60-day: [criterion] | Yes / Partially / No | |
| 90-day: [criterion] | Yes / Partially / No | |

**Was the confidence level calibrated correctly?**

Predicted confidence: [X]/10
Actual outcome: [Correct / Partially correct / Incorrect]

[Reflection on calibration]

**What would you do differently?**

[Your reflection here]

**Disposition**: [close | extend revisit to YYYY-MM-DD | escalate]
```

---

## Example Entry (filled in)

```markdown
---
slug: annual-pricing-switch
date: 2025-05-01
revisit_date: 2025-08-01
confidence: 6
status: open
---

# Decision: Switch to dual pricing — monthly + annual with 20% discount

## Context

We have 80 monthly subscribers at $49/month. Cash flow is tight; a lump-sum
annual payment from even 30% of users would fund the next quarter without
fundraising. Risk: forcing annual-only could trigger churn.

## Options Considered

| Option | Upside | Downside |
|---|---|---|
| Keep monthly only | No disruption | Cash flow problem persists |
| Annual only | Maximum cash flow | High churn risk |
| Both (annual discount) | Incentivize annual; keep flexible for monthly | Slightly complex pricing page |

## Selected Option

**Both pricing options, annual at 20% discount ($470/year vs $588/year)**

## Rationale

Option 3 captures most of the cash flow benefit (annual conversions) while
preserving the monthly option for price-sensitive or short-term users. The
downside of complexity on the pricing page is minor compared to the churn risk
of Option 2.

## Expected Outcome and Success Criteria

- In 30 days: pricing page live, no support complaints about the change.
- In 60 days: at least 20% of existing monthly subscribers have converted to annual.
- In 90 days: monthly churn rate drops from 3% to < 2%. Net MRR impact positive.

## Confidence Level

**6/10** — Main uncertainty: we do not know how price-sensitive our current
subscribers are. Could be higher than expected.

## Revisit Date

**2025-08-01**
```
