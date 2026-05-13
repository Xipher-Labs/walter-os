---
name: customer-interview-synthesizer
description: >-
  Two-phase customer discovery tool. Phase A: generate a Mom Test-compliant
  interview script from a hypothesis and target persona. Phase B: synthesize
  1-N interview transcripts into pain points, JTBD, recurring quotes, and
  recommended pivots. Triggers on: interview script, customer discovery,
  synthesize interviews, jobs to be done, JTBD, user research, validate
  hypothesis.
triggers:
  - interview script
  - customer discovery
  - synthesize interviews
  - jobs to be done
  - JTBD
  - user research
  - validate hypothesis
---

# customer-interview-synthesizer

Two-phase customer discovery skill. Use it before building any feature,
after forming a hypothesis, or when you need to understand why customers
behave the way they do.

## When to use this skill

- Pre-PMF: before committing engineering time to a feature.
- After any pivot hypothesis — validate the new direction cheaply.
- When onboarding a new target persona you haven't interviewed before.
- After reading a batch of support tickets and wanting to find the JTBD underneath.

## When NOT to use this skill

- Post-PMF scaling: at scale, surveys and product analytics give faster signal.
- Quantitative research with N > 100: use structured surveys (Typeform, Qualtrics).
- B2B enterprise deals: use SPIN Selling or Challenger Sale methodology instead —
  those prospects expect a different interaction style.

## Phase A — Interview Guide Generator

**Inputs:**
- `hypothesis`: one-sentence belief you're testing (e.g., "Engineering managers at
  Series A startups spend >4h/week manually aggregating deployment metrics").
- `persona`: role, company stage, industry, typical daily workflow.

**Outputs:** 5–15 interview questions following Mom Test rules:
- Focus on past behavior, not future intent.
- Ask about specific incidents, not generalities.
- Never pitch your solution; probe the problem.

**Question quality heuristics:**

| Bad question | Why bad | Good alternative |
|---|---|---|
| "Would you use a product that…?" | Asks about future intent | "Tell me about the last time you…" |
| "Don't you think X is a problem?" | Leading | "How do you currently handle X?" |
| "How much would you pay for…?" | Premature pricing | "What do you currently spend on this?" |
| "Is this a big pain for you?" | Invites validation bias | "Walk me through last week's X workflow" |

See `references/mom-test-rules.md` for the full six-rule reference.

## Example

### Phase A — Sample Output

**Hypothesis:** Engineering managers spend >4h/week manually aggregating
deployment metrics.

**Persona:** EM at a Series A startup, 5–15 engineers, using GitHub + Datadog.

Generated questions:
1. Walk me through how you prepared your last engineering update for leadership.
2. What data did you need that you couldn't get in under 5 minutes?
3. How long did that process take? What was the biggest time sink?
4. What would have happened if you'd skipped that update?
5. Have you tried to automate any part of it? What happened?

## Phase B — Transcript Synthesis

**Inputs:** 1–N interview transcript blobs (freeform text, any format).

**Outputs:** Structured synthesis report using `references/synthesis-template.md`:

- **Pain Points** (ranked by frequency across transcripts)
- **JTBD Statements** in the format: "When I [situation], I want to [motivation],
  so I can [outcome]."
- **Recurring Quotes** (verbatim — the exact words that capture a pattern)
- **Recommended Pivots** (one per major theme: what to build, cut, or change)
- **Persona Refinement** (how the real respondents differed from the target persona)

### Phase B — Sample Output

Input: 3 interview transcripts with engineering managers.

**Pain Points (by frequency):**
1. Manual Slack export + spreadsheet aggregation — mentioned in 3/3 interviews
2. No single source of truth for deployment frequency — 2/3
3. Metrics definitions differ between engineering and product — 2/3

**JTBD Statements:**
- When I prepare a weekly engineering update, I want reliable deployment metrics
  in under 10 minutes, so I can spend the meeting on decisions, not data gathering.

**Recurring Quotes:**
- "I copy-paste from three tabs every Friday. It's embarrassing."
- "The dashboard exists but nobody trusts the numbers."

**Recommended Pivots:**
- Build the Friday digest as a Slack bot, not a dashboard — EMs already live in Slack.

**Persona Refinement:**
- Target persona said "Series A." Reality: all three were Series B. Adjust ICP.

## Outputs

Files written to `docs/discovery/<project>/` when `WALTER_CURRENT_PROJECT` is set:

- `interview-guide.md` — Phase A output
- `synthesis-report.md` — Phase B output

If the project variable is not set, output is written to the chat only.

## How it composes with other Walter-OS skills

- **Upstream of `pricing-experiment`**: synthesis reveals willingness-to-pay signals;
  hand the synthesis report to `pricing-experiment` as the ICP input.
- **Upstream of `vc-evaluator`**: a completed synthesis report strengthens the
  customer evidence section of a pitch deck.
- **With `weekly-review-coach`**: each synthesis session counts as a KR checkpoint
  ("completed N customer interviews this week").
- **With `architect`**: use the synthesis output to evaluate whether a proposed
  feature addresses a real, frequent pain point before committing to a spec.
