---
name: decision-journal
description: Capture significant decisions in a structured format — decision journal, log this decision, important decision, decision review. Stores entries at ~/.config/walter-os/state/decisions/. Surfaces past-due revisit prompts via weekly-review-coach.
---

# decision-journal

Structured decision capture and retrospective review. For each significant
decision — hiring, pricing, technical architecture, partnerships, strategy pivots
— the skill walks through seven fields, writes a Markdown file to an
operator-private state directory, and surfaces past-due revisit prompts.

Entries are stored at `~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md`.
This directory is out-of-repo and operator-private. The state directory is
not committed to git.

## When to use this skill

- You are about to make a significant decision and want to think it through.
- You want to create an auditable record of why you made a decision.
- You are reviewing a past decision to assess the outcome.
- You want to surface which past decisions have reached their revisit date.
- You want to build a habit of systematic decision-making.

## When NOT to use this skill

- For trivial day-to-day decisions (what to build next sprint, which library
  to use). Reserve this skill for decisions with meaningful consequences.
- For team decisions that need a shared record — this skill writes to the
  operator's private state; use a shared doc for team-visible decisions.
- For decisions that need legal or financial advice — this is a thinking aid,
  not a professional service.

## Inputs

The skill prompts for these seven fields. All are required except revisit date,
which defaults to 90 days from today:

1. **Decision slug**: short kebab-case identifier, e.g., `switch-to-annual-pricing`.
2. **Context**: what situation prompted this decision? What constraints apply?
3. **Options considered**: list 2-5 alternatives that were seriously evaluated.
4. **Selected option**: which option was chosen.
5. **Rationale**: why this option over the others? What trade-offs were accepted?
6. **Expected outcome and success criteria**: what should be true in 30/60/90 days
   if this was the right call? Must be measurable.
7. **Confidence level**: 1-10, where 10 = certain and 1 = pure guess.
8. **Revisit date**: YYYY-MM-DD. Default: 90 days from today.

## Outputs

1. **Decision file**: written to
   `~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md` using the
   template at `references/decision-template.md`.

2. **Revisit prompt**: when invoked without a new decision, the skill reads all
   files in the state directory and lists entries where `revisit_date` is today
   or earlier. For each past-due entry, it walks through a retrospective:
   - What actually happened?
   - Did the outcome match the expected success criteria?
   - What was the confidence level vs actual outcome?
   - What would you do differently?
   - Should the revisit be extended, closed, or escalated?

3. **Confidence calibration**: over time, the skill can compute your calibration
   (confidence 8/10 decisions that turned out correct vs incorrect) if you have
   enough entries.

## Sample usage

**Capturing a new decision**:

```
Skill: decision-journal

I am deciding whether to switch from monthly to annual-only pricing.

Slug: annual-pricing-switch
Context: We have 80 monthly subscribers paying $49/month. Conversion to annual
  would improve cash flow and reduce churn. Risk: some price-sensitive customers
  might leave.
Options: (1) Keep monthly only. (2) Switch to annual only. (3) Offer both with
  annual discount.
Selected option: Option 3 — offer both, with 20% annual discount.
Rationale: Annual discount incentivizes commitment without forcing churn of
  monthly customers. Reduces risk vs option 2.
Expected outcome: 30% of existing customers convert to annual within 60 days.
  Monthly churn drops from 3% to < 2%.
Confidence: 6/10
Revisit date: 2025-08-01
```

**Reviewing past-due decisions**:

```
Skill: decision-journal

Please surface all past-due decision entries.
```

## How it composes with other Walter-OS skills

- `weekly-review-coach` — the weekly review should include a check of past-due
  decision entries. The coach skill can call decision-journal's revisit prompt
  as part of the Friday review agenda.
- `learn-by-mistake` — when a decision retrospective reveals a mistake, use
  learn-by-mistake to capture the pattern and avoid it in future decisions.

## Prompt for your AI

**To capture a new decision**:

```
I want to log a significant decision in my decision journal. Please walk me
through these seven fields:

1. Decision slug (kebab-case identifier)
2. Context (situation and constraints)
3. Options considered (2-5 alternatives)
4. Selected option
5. Rationale (why this option, what trade-offs were accepted)
6. Expected outcome and success criteria (measurable, with timeline)
7. Confidence level (1-10)
8. Revisit date (YYYY-MM-DD, default 90 days from today)

Once I answer all fields, produce the complete Markdown file content using the
decision-template format, ready to save to:
~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md
```

**To review past-due entries**:

```
List the decision journal entries in ~/.config/walter-os/state/decisions/ where
the revisit_date field is today or earlier. For each, display the slug, date,
selected option, and expected outcome, then ask me to complete the retrospective:
- What actually happened?
- Did outcomes match success criteria? (Yes / Partially / No)
- What would you do differently?
- Disposition: close | extend revisit | escalate
```
