---
name: survey-design
description: Design quantitative surveys (NPS survey, CSAT, CES, PMF survey, satisfaction survey, Likert scale) to complement qualitative interviews. Outputs question battery, sample size guidance, distribution channels, and response-rate techniques.
---

# survey-design

Quantitative survey design for founders. Converts qualitative signals from user
interviews into validated, statistically grounded survey instruments. Covers NPS,
CSAT, CES, and PMF fit measurement using the Sean Ellis method.

## When to use this skill

- You have qualitative interview findings and want to validate them at scale.
- You need to measure customer satisfaction (CSAT), loyalty (NPS), or effort (CES).
- You want to assess product-market fit with the Sean Ellis 40% threshold test.
- You are designing a new survey from scratch and want question-battery guidance.
- You need to determine how many responses you need for statistically valid results.

## When NOT to use this skill

- You need qualitative research (use `customer-interview-synthesizer` instead).
- You want to run a pricing experiment (use `pricing-experiment`).
- You are looking for competitor intelligence (use `competitor-radar`).
- Your audience is under 30 people — qualitative interviews give more signal at
  that scale.

## Inputs

- **Research objective**: what hypothesis or question you are testing.
- **Target population**: who will receive the survey (customers, prospects, churned
  users, etc.).
- **Survey type**: NPS, CSAT, CES, PMF fit, or custom.
- **Existing qualitative data** (optional): interview transcripts or synthesis from
  `customer-interview-synthesizer` to inform question framing.
- **Distribution channel**: email, in-app, SMS, or link.
- **Acceptable margin of error**: default ±5% at 95% confidence if not specified.

## Outputs

1. **Question battery**: 5-15 questions in the correct order (warm-up, core metric,
   follow-up, demographic). Includes Likert scale anchoring and phrasing guidance.
2. **Sample size recommendation**: calculated using the Cochran formula
   `n = Z² × p × (1-p) / e²` where Z=1.96 (95% confidence), p=0.5
   (maximum variance), and e is your margin of error. Default: e=0.05 → n=385.
   Table for common margins of error:

   | Margin of error | Min sample |
   |---|---|
   | ±3% | 1,068 |
   | ±5% | 385 |
   | ±7% | 196 |
   | ±10% | 97 |

3. **Distribution channel playbook**: recommended channels with expected response
   rates and timing.
4. **Response-rate boost techniques**: subject line patterns, incentive options,
   reminder cadence, survey length guidance (keep under 5 minutes).
5. **Scoring rubric**: how to interpret results once collected.

## Sample usage

```
Skill: survey-design

Research objective: Validate that our top interview finding — customers switch
  from us due to lack of API documentation — is representative across the user base.

Target population: Active customers who signed up in the last 6 months (approx 400).

Survey type: Custom (PMF fit + one focused CSAT question on docs).

Distribution: Email. We have their addresses in our CRM.

Acceptable margin of error: ±7% (we only have 400 users so can't hit 385).
```

Expected output: a question battery with PMF fit question (Sean Ellis), a CSAT
question on documentation quality, and a follow-up open-ended question. Sample
size note: with 400 users and ±7% margin, you need 196 responses (49% response
rate required — recommend in-app placement to hit this).

## How it composes with other Walter-OS skills

- `customer-interview-synthesizer` — run qualitative interviews first, then use
  this skill to design a survey that validates findings at scale. The themes from
  synthesis feed directly into the question battery.
- `weekly-review-coach` — surface survey results in the Friday review to track
  metric trends week-over-week.
- `competitor-radar` — if a competitor launches a feature, a CSAT pulse survey
  can measure whether your users notice the gap.

## Prompt for your AI

```
I need to design a quantitative survey. Here is my context:

Research objective: [what hypothesis you are testing]
Target population: [who receives the survey, approximate size]
Survey type: [NPS | CSAT | CES | PMF fit | custom]
Existing qualitative data: [paste interview themes or leave blank]
Distribution channel: [email | in-app | SMS | public link]
Acceptable margin of error: [default ±5%]

Please output:
1. A question battery (5-15 questions) with scale anchoring
2. Sample size calculation using Cochran formula at 95% confidence
3. Distribution channel recommendation with expected response rates
4. Three response-rate boost techniques for this channel
5. Scoring rubric for interpreting results
```
