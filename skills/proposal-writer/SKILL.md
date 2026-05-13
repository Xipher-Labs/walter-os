---
name: proposal-writer
description: Generate B2B proposals for consulting, SaaS, or agency engagements. Outputs executive summary, statement of work, pricing breakdown (fixed/T&M/retainer), terms summary, and appendix. Covers RFP response, SOW, B2B proposal writing.
---

# proposal-writer

Structured B2B proposal generation for consulting, SaaS, and agency engagements.
Produces a complete proposal document with five sections: executive summary,
statement of work with deliverables and milestones, pricing breakdown, terms
summary, and a case study appendix. Not a fundraising tool — use `vc-evaluator`
for investor pitches.

## When to use this skill

- You are responding to an RFP or informal client request.
- You need to write a statement of work (SOW) for a new client engagement.
- You want to structure your pricing and present it professionally.
- You are writing a proposal for consulting, software development, or agency work.
- You want to standardize your proposal process across multiple clients.

## When NOT to use this skill

- You are raising funding from investors (use `vc-evaluator` instead).
- You need a pitch deck rather than a written proposal.
- You are writing a product roadmap or internal specification document.
- The engagement is internal (use the `architect` skill for internal specs).

## Inputs

- **Engagement type**: consulting, SaaS subscription, agency retainer, or
  software development project.
- **Client brief**: what the client asked for (paste the email, RFP excerpt, or
  your notes from the discovery call).
- **Your solution**: what you are proposing to deliver.
- **Timeline**: project start date, duration, and key milestones.
- **Pricing model**: fixed-price, T&M, retainer, or value-based (see
  `references/pricing-models.md` for guidance).
- **Case studies** (optional): past work to include in the appendix.
- **IP and payment terms** (optional): any non-standard terms you want to apply.

## Outputs

1. **Executive summary**: 2-3 paragraphs. Problem statement, proposed solution,
   why you (differentiation), and expected outcome for the client. No jargon.
2. **Statement of work**: deliverables table, milestones, in-scope / out-of-scope
   list, assumptions and dependencies, change management process.
   Template at `references/sow-template.md`.
3. **Pricing breakdown**: line-item pricing in the selected model with totals.
   Includes payment schedule (e.g., 50% on signing, 50% on delivery).
4. **Terms summary**: IP ownership, payment terms, exit clause, liability cap.
   Plain language, not legal boilerplate.
5. **Appendix**: case study placeholders with structure for the operator to fill.
   Optional references section.

## Sample usage

```
Skill: proposal-writer

Engagement type: Consulting — data infrastructure audit and roadmap.

Client brief: "We need someone to audit our Postgres setup and give us a 90-day
  roadmap for scaling from 50k to 500k daily active users. Budget is around $15k."

Solution: 3-week audit (architecture review, load testing, bottleneck report)
  + 2-week roadmap document with prioritized recommendations.

Timeline: Start next Monday, done in 5 weeks.

Pricing model: Fixed-price, $14,500.

Case studies: Two previous database audit engagements (anonymized).
```

Expected output: A complete proposal document with executive summary framing the
scaling risk, SOW with three deliverables (audit report, load test results,
roadmap document), fixed-price breakdown ($14,500 split 50/50), standard IP
and payment terms, and two anonymized case study stubs.

## How it composes with other Walter-OS skills

- `cold-outreach-sequencer` — use cold-outreach-sequencer to get the discovery
  call, then feed the call notes into this skill to generate the proposal.
- `pricing-experiment` — if you are unsure of your pricing model or tier
  structure, run pricing-experiment first to validate willingness to pay before
  committing to a price in the proposal.
- `vc-evaluator` — for investor materials (not client proposals).

## Prompt for your AI

```
I need to write a B2B proposal. Here is my context:

Engagement type: [consulting | SaaS | agency | software development]
Client brief: [paste the brief, RFP, or call notes]
My solution: [what you propose to deliver]
Timeline: [start date, duration, milestones]
Pricing model: [fixed | T&M | retainer | value-based]
Pricing amount: [your number or range]
Case studies: [describe 1-2 past engagements or leave blank]
Special terms: [any non-standard IP, payment, or exit terms]

Please output the full proposal with these five sections:
1. Executive summary (2-3 paragraphs, no jargon)
2. Statement of work (deliverables table, in/out-of-scope, milestones,
   assumptions, change management)
3. Pricing breakdown (line items, totals, payment schedule)
4. Terms summary (IP, payment terms, exit clause, liability cap)
5. Appendix (case study stubs for me to fill in)
```
