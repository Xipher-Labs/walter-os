---
name: financial-plan-builder
description: Build a 12-month cash projection from a YAML config (starting balance, revenue assumptions, fixed costs, variable costs, hiring plan). Outputs a monthly cash table, runway in months, break-even month, and a simple sensitivity analysis. Use when planning runway, deciding to raise / not raise, modeling a hire, or producing a board-update spreadsheet. NOT financial advice. Numbers, not opinions.
---

# Financial-plan-builder

A spreadsheet that lives in version control. Reads a YAML config,
emits a monthly cash projection with the numbers you actually need
to make funding-vs-runway decisions.

## Disclaimer

This skill produces numbers from a YAML config. It does not:

- Advise on whether to raise capital.
- Predict revenue.
- Account for taxes (the skill emits a `[TAX]` flag wherever tax
  treatment matters; the operator/accountant fills in).
- Model complex equity, debt, or warrant structures.
- Replace an accountant or financial controller for material
  decisions (audited reports, tax filings, due diligence).

If the YAML inputs are wrong, the output is wrong. The skill's
value is consistency — the same config produces the same projection
every time, so the operator can iterate on the inputs (what if I
hire one engineer in month 4 instead of month 2?) without rebuilding
the spreadsheet.

## Input — `finances/plan.yml`

The skill reads `finances/plan.yml` at the repo root (or a path the
operator passes). Example:

```yaml
plan:
  name: 2026 H1 projection
  starting_balance_usd: 180000        # cash in bank on day 1
  start_date: 2026-01-01
  horizon_months: 12

revenue:
  # MRR streams. The skill compounds growth at the configured rate.
  - name: self-serve-saas
    starting_mrr_usd: 4500            # MRR at start_date
    monthly_growth_rate: 0.08         # 8% MoM
    cap_mrr_usd: 30000                # plateau cap

  - name: enterprise-contracts
    starting_mrr_usd: 0
    contracts:                        # discrete deals, not MoM growth
      - start_month: 3
        monthly_value_usd: 8000
        term_months: 12
      - start_month: 7
        monthly_value_usd: 12000
        term_months: 6

  - name: consulting
    starting_mrr_usd: 0
    one_off_payments:                 # non-recurring lumps
      - month: 2
        usd: 15000
      - month: 5
        usd: 10000

fixed_costs:
  # Costs that don't scale with revenue — paid every month.
  rent: 0                              # remote-first
  software_subscriptions: 850          # Notion, Linear, Vercel, etc.
  hosting: 320                         # AWS / Hetzner / Cloudflare
  legal_accounting_fixed: 400          # retainer or monthly accountant
  insurance: 200
  other: 100

variable_costs:
  # Costs that scale with usage or revenue. Skill computes from
  # configured percentages.
  payment_processing_pct: 0.029        # Stripe-shape
  llm_api_pct_of_mrr: 0.04             # AI API as % of MRR (operator estimates)
  cogs_pct_of_revenue: 0.10            # other variable costs

hiring_plan:
  # Each entry adds to monthly burn at the start_month.
  - role: founder
    start_month: 0
    monthly_total_usd: 6000            # salary + benefits + employer-side tax
    notes: operator self-pay

  - role: engineer
    start_month: 4
    monthly_total_usd: 11000

  - role: marketing
    start_month: 8
    monthly_total_usd: 6500
    notes: contractor, half-time

one_off_costs:
  # Lumpy expenses outside the recurring categories.
  - description: trademark filing
    month: 3
    usd: 2200

  - description: conference + travel
    month: 6
    usd: 4800

sensitivity:
  # The skill runs three additional scenarios besides the base case.
  - name: bull
    revenue_multiplier: 1.30           # all revenue lines * 1.30
    cost_multiplier: 1.00

  - name: bear
    revenue_multiplier: 0.70
    cost_multiplier: 1.15               # costs run hot

  - name: bear-and-hire-paused
    revenue_multiplier: 0.70
    cost_multiplier: 1.15
    skip_hires: [engineer, marketing]   # postpone these
```

## Output

Writes to `finances/<plan-name>/`:

```
finances/<plan-name>/
├── plan.yml                       (the input — kept for traceability)
├── projection.md                  (human-readable monthly table)
├── projection.csv                 (importable into a spreadsheet)
└── summary.md                     (the 1-page board update)
```

### `projection.md` shape

```markdown
# Projection: 2026 H1

| Month | Date | Revenue | Costs | Net | Cash balance | Runway |
|---|---|---|---|---|---|---|
| 0 | 2026-01 | $4,500 | $14,000 | -$9,500 | $170,500 | 18 mo |
| 1 | 2026-02 | $4,860 | $14,200 | -$9,340 | $161,160 | 17 mo |
| 2 | 2026-03 | $20,249 | $14,500 | $5,749 | $166,909 | n/a |
...
| 11 | 2026-12 | $42,650 | $28,800 | $13,850 | $228,150 | n/a |

**Starting balance**: $180,000
**Ending balance (month 11)**: $228,150
**Cumulative net**: +$48,150
**Break-even month**: 2 (2026-03)
**Lowest cash point**: month 1 ($161,160)
**Runway from month 0 (cost-only)**: 19 months
**Runway from lowest point (cost-only)**: 17 months
```

### `summary.md` (board-update grade)

```markdown
# Q1 2026 — financial summary

**Starting cash**: $180,000
**Plan horizon**: 12 months

## Headline numbers

- Ending cash (month 11): **$228,150**
- Break-even: **month 2** (2026-03)
- Lowest cash point: **$161,160** (month 1)
- Monthly burn at month 0: **$9,500**
- Monthly contribution at month 11: **+$13,850**

## Sensitivity

| Scenario | Ending cash | Lowest point | Break-even |
|---|---|---|---|
| Base | $228,150 | $161,160 | month 2 |
| Bull (rev × 1.30) | $341,000 | $164,200 | month 1 |
| Bear (rev × 0.70, costs × 1.15) | $32,400 | $32,400 | month 11 |
| Bear + hire pause | $98,600 | $73,200 | month 10 |

## Key risks (operator review required)

- Bear scenario ends with $32k cash — below 3-month buffer.
- Engineer hire in month 4 is the single largest cost commit.
- Self-serve growth assumes 8% MoM; historical was 5%. [REVIEW]

## What this projection does NOT include

- Taxes (federal, state, sales). See `[TAX]` markers in `projection.md`.
- Equity dilution from a future raise.
- Variability in payment processing rate.
- Bad-debt allowance.
```

## What the skill actually computes

For each month `m` from 0 to `horizon_months - 1`:

1. **Revenue**:
   - For each MRR line: starting MRR × (1 + growth_rate) ^ m, capped
     at `cap_mrr_usd`.
   - Plus contracts active in month m (start_month ≤ m < start_month + term).
   - Plus one-off payments scheduled for month m.

2. **Fixed costs**: sum of `fixed_costs.*` (constant per month).

3. **Variable costs**: `revenue × (payment_processing_pct +
   llm_api_pct_of_mrr × MRR/revenue + cogs_pct_of_revenue)`.
   The LLM term is treated as a function of MRR specifically; one-off
   payments don't trigger LLM cost.

4. **Hiring costs**: sum of `hiring_plan[i].monthly_total_usd` for
   each role with `start_month ≤ m`.

5. **One-off costs**: cost from `one_off_costs[i]` if `i.month == m`,
   else 0.

6. **Net**: revenue - (fixed + variable + hiring + one_off).
7. **Cash balance**: cumulative sum of net + starting_balance.
8. **Runway**: if monthly net < 0, runway = current_balance / |net|.
   Else "n/a".

For sensitivity scenarios: multiply revenue / cost streams by the
configured multipliers, then re-run the computation. `skip_hires`
removes those roles entirely from the plan.

## What this skill is NOT

- A forecasting tool. The skill projects the YAML inputs; it does
  not predict revenue from anything other than what the operator
  configures. If the operator's assumptions are wrong, the
  projection is wrong.
- A bookkeeping tool. The skill does not reconcile against actual
  bank statements. Bookkeeping happens in QuickBooks / Xero / a
  spreadsheet; this skill answers "what does the next 12 months
  look like if we keep going".
- A tax planning tool. `[TAX]` markers flag where the operator's
  accountant needs to weigh in.
- An ERP / billing system. The skill does not invoice, dunning,
  reconcile, or collect.

## Operator workflow

1. **First run**: scaffold `finances/plan.yml` from the template
   above. Adjust starting balance + revenue lines + hiring plan to
   match reality.
2. **Re-run any time** an assumption changes (close a deal, hire,
   raise prices). Commit the new `plan.yml` so the projection
   history is version-controlled.
3. **Monthly cadence**: open `summary.md`, compare projected vs.
   actual, adjust assumptions for any line that drifted by > 10%.
4. **Board update**: paste `summary.md` content into the board email
   / deck. Highlight the sensitivity row that aligns with this
   month's experience.

## Anti-patterns

1. **Treating the bull case as the plan.** Plan against base or
   bear; if bull happens, you have more options. Planning against
   bull and getting base = layoffs.
2. **Ignoring [TAX] markers.** US LLCs pass through to operator
   income; C-corps pay corporate; international LLCs vary widely.
   Talk to an accountant.
3. **Hiring on the assumption next month's revenue clears the
   payroll commitment.** Hire when you have 6+ months of runway
   AFTER the salary commitment is added.
4. **Updating the YAML retroactively to match what actually
   happened.** That makes the historical projections look prescient
   when they weren't. Keep an "actuals" alongside the projection
   for honest comparison.

## Hard rules

- **Always emit `[TAX]` markers** where taxes apply but aren't
  modeled.
- **Always show the lowest cash point**, not just the ending
  balance. A plan that ends at $500k but dips to $5k in month 7
  is not a safe plan.
- **Never assume revenue growth above 15% MoM** without an explicit
  `[REVIEW]` marker. Sustained 15%+ MoM is exceptional; the skill
  warns when configured.
- **The output is a Markdown table + CSV**, not a chart. Charts
  belong in a separate visualization layer. Numbers first.

## Integration with other Walter-OS skills

- **`hiring-toolkit`** — when planning a new hire, this skill models
  the cost impact; that skill produces the JD / interview rubric /
  offer letter for the same role.
- **`pricing-experiment`** — when changing prices, this skill models
  the revenue impact under different MRR growth assumptions.
- **`vc-evaluator`** — when prepping for a raise, this skill
  produces the projection that goes into the deck; that skill
  helps anticipate investor pushback on the numbers.
- **`saas-metrics-dashboard`** — for the metrics layer (MRR, ARR,
  churn, LTV/CAC); this skill projects forward, that skill
  measures backward.

## References

- Walter-OS execution plan Phase 4.1.4.
- `skills/saas-metrics-dashboard/SKILL.md` — backward-looking
  metrics; this skill is the forward-looking complement.
- `skills/hiring-toolkit/SKILL.md` — JD/rubric/offer-letter for the
  roles in the hiring plan.
