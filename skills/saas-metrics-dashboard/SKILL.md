---
name: saas-metrics-dashboard
description: Calculate and interpret SaaS metrics — MRR calculation, ARR, churn rate, LTV CAC ratio, Quick Ratio, Magic Number, Rule of 40, unit economics. Accepts CSV or YAML input; benchmarks against per-stage norms and produces a diagnosis.
---

# saas-metrics-dashboard

SaaS metrics calculation and interpretation. Accepts operator-provided revenue
and cost data in CSV or YAML format, computes the full standard metric set, and
benchmarks results against per-ARR-stage norms from Bessemer, OpenView, and SaaStr.
Produces a diagnosis identifying where to focus. No DB writes; no live data
pipeline connections.

## When to use this skill

- You want to know your current MRR, ARR, churn, LTV, and CAC from raw data.
- You need to benchmark your metrics against stage-appropriate norms.
- You are preparing for an investor meeting and need clean metric outputs.
- You want a diagnosis of where your unit economics are healthy or broken.
- You have a CSV or YAML export from your billing system and want to interpret it.

## When NOT to use this skill

- You need a live dashboard with auto-refresh (this is a Control Tower feature,
  not a skill).
- You want to write data to a database — this skill is read-only.
- You need cohort analysis or complex SQL queries (use `postgres-cli` directly).
- Your data is in a format other than CSV or YAML (convert it first).

## Inputs

**CSV format** (one row per month):

```csv
month,new_mrr,expansion_mrr,churned_mrr,new_customers,churned_customers,cac_spend
2025-01,12000,2000,1500,15,2,8000
2025-02,14000,1800,1200,18,1,9000
```

**YAML format** (equivalent):

```yaml
months:
  - month: "2025-01"
    new_mrr: 12000
    expansion_mrr: 2000
    churned_mrr: 1500
    new_customers: 15
    churned_customers: 2
    cac_spend: 8000
  - month: "2025-02"
    new_mrr: 14000
    expansion_mrr: 1800
    churned_mrr: 1200
    new_customers: 18
    churned_customers: 1
    cac_spend: 9000
```

The skill will ask which format you have before proceeding.

## Outputs

1. **Computed metrics** with formulas:

   | Metric | Formula |
   |---|---|
   | MRR | Sum of all active monthly recurring revenue |
   | ARR | MRR × 12 |
   | MRR growth rate | (MRR_this - MRR_prev) / MRR_prev |
   | Gross revenue churn | churned_mrr / MRR_prior_month |
   | Net revenue retention (NRR) | (MRR_prior + expansion - churn) / MRR_prior |
   | LTV | ARPU / gross_churn_rate (simplified; assumes constant churn) |
   | CAC | cac_spend / new_customers |
   | LTV:CAC ratio | LTV / CAC |
   | Quick Ratio | (new_mrr + expansion_mrr) / churned_mrr |
   | Magic Number | Net new ARR / S&M spend in prior quarter |
   | Rule of 40 | MRR growth rate (%) + profit margin (%) |

2. **Stage benchmark comparison**: each metric is compared against the relevant
   ARR stage from `references/saas-benchmarks.md`.

3. **Diagnosis**: 3-5 bullet points identifying where metrics are above, at, or
   below benchmark, with the single highest-leverage area to focus on.

## Sample usage

```
Skill: saas-metrics-dashboard

I have a CSV file with 6 months of data. Paste it below:

month,new_mrr,expansion_mrr,churned_mrr,new_customers,churned_customers,cac_spend
2024-09,8000,1000,2000,10,3,6000
2024-10,9000,1200,2500,12,4,7000
2024-11,10000,1500,3000,14,5,8000
2024-12,11000,1800,3500,15,6,9000
2025-01,12000,2000,4000,16,7,10000
2025-02,13000,2200,4500,17,8,11000
```

Expected output: Computed metrics table showing declining Quick Ratio (from 1.5
to 1.2 over 6 months) indicating churn acceleration outpacing new acquisition.
LTV:CAC ratio of 1.8 is below the 3:1 target for the $0-1M ARR stage. Diagnosis:
fix churn before increasing acquisition spend — current Quick Ratio trajectory
will make growth unsustainable within 3 months.

## How it composes with other Walter-OS skills

- `postgres-cli` — if your analytics DB is queryable, use postgres-cli to
  extract the raw data in the CSV or YAML format this skill expects, then pass
  the output directly.
- `weekly-review-coach` — include a monthly metrics snapshot as a standing
  agenda item in the weekly review. Pull from this skill's output.
- `pricing-experiment` — if LTV:CAC is below target, pricing-experiment can
  help design experiments to increase ARPU before optimizing acquisition cost.

## Prompt for your AI

```
I need to calculate and interpret my SaaS metrics. I have data in [CSV | YAML]
format. Here is my data:

[paste CSV or YAML]

Please:
1. Compute MRR, ARR, MRR growth rate, gross revenue churn, NRR, LTV, CAC,
   LTV:CAC, Quick Ratio, and Rule of 40 for each month
2. Show the formulas used
3. Benchmark each metric against the appropriate ARR-stage norms
4. Provide a 3-5 bullet diagnosis identifying the highest-leverage focus area
```
