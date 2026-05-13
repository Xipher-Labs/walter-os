# Survey Frameworks Reference

## Sean Ellis PMF Survey (Product-Market Fit)

**Core question**: "How would you feel if you could no longer use [product]?"

Response options:
- Very disappointed
- Somewhat disappointed
- Not disappointed (it isn't really that useful)
- N/A — I no longer use [product]

**Threshold**: 40% or more answering "Very disappointed" indicates strong PMF.
Below 40%: iterate on positioning or product before scaling.

**Recommended follow-up questions**:
1. "What type of people do you think would benefit most from [product]?"
2. "What is the main benefit you receive from [product]?"
3. "How can we improve [product] for you?"

Source: Sean Ellis, "Startup Growth Engines" and Superhuman case study (2019).

---

## Net Promoter Score (NPS)

**Core question**: "On a scale of 0-10, how likely are you to recommend
[product/company] to a friend or colleague?"

**Segments**:
- Promoters: 9-10
- Passives: 7-8
- Detractors: 0-6

**Formula**: NPS = % Promoters - % Detractors

**Range**: -100 (all detractors) to +100 (all promoters)

**Benchmarks by category** (Bain & Company, 2024):
- Software / SaaS: good > 30, excellent > 50
- Consumer tech: good > 40, excellent > 60
- Financial services: good > 20, excellent > 40

**Recommended follow-up**: Open-ended "What is the primary reason for your score?"

**Frequency**: Quarterly for transactional NPS; triggered after key events for
relational NPS (onboarding completion, first value moment, renewal).

---

## Customer Satisfaction Score (CSAT)

**Core question**: "How satisfied were you with [interaction/product/feature]?"

**Scale**: 1 (very unsatisfied) to 5 (very satisfied)

**Calculation**: CSAT % = (Number of 4s and 5s / Total responses) × 100

**Target**: > 80% CSAT is considered good across most B2B SaaS categories.

**When to use**: Post-support interaction, post-onboarding, feature-specific
satisfaction. Best for measuring a specific interaction, not overall loyalty.

**Avoid**: Using CSAT as a proxy for NPS or PMF — they measure different things.

---

## Customer Effort Score (CES)

**Core question**: "The company made it easy for me to handle my issue."

**Scale**: 1 (strongly disagree) to 7 (strongly agree)

**Interpretation**: Higher is better. Target > 5.5.

**When to use**: After a support interaction, onboarding completion, or any
workflow the user has to navigate. CES is the best predictor of churn for
support-heavy products.

**Formula**: CES = Average of all responses (mean, not %).

---

## Sample Size Formula (Cochran, 1977)

For estimating proportions in large populations:

```
n = (Z² × p × (1 - p)) / e²
```

Where:
- Z = Z-score for confidence level (1.96 for 95%, 2.576 for 99%)
- p = expected proportion (use 0.5 for maximum variance when unknown)
- e = margin of error (0.05 for ±5%)

**Standard table (95% confidence, p=0.5)**:

| Margin of error | Sample size |
|---|---|
| ±1% | 9,604 |
| ±2% | 2,401 |
| ±3% | 1,068 |
| ±4% | 601 |
| ±5% | 385 |
| ±7% | 196 |
| ±10% | 97 |

**Finite population correction** (when population N < 10,000):

```
n_adjusted = n / (1 + (n - 1) / N)
```

Example: population of 400, target ±5% → n=385, adjusted n = 385 / (1 + 384/400)
= 385 / 1.96 ≈ 196 responses needed.

---

## Likert Scale Best Practices

- **5-point vs 7-point**: Use 5-point for general satisfaction; 7-point for
  attitude or agreement statements where nuance matters.
- **Label all points**, not just endpoints — unlabeled middle points introduce
  response bias.
- **Avoid double-barreled questions**: "Was the product fast and reliable?" is
  two questions. Split them.
- **Order**: warm-up questions first, sensitive or demographic questions last.
- **Length**: keep surveys under 10 minutes (≈15-20 questions) to avoid
  abandonment. For pulse surveys, target under 3 minutes (5-7 questions).
