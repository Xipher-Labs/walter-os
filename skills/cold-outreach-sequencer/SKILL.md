---
name: cold-outreach-sequencer
description: >-
  Draft a personalized 5-touch cold outreach sequence for email, LinkedIn, or
  Twitter/X DM. Each touch includes personalization variables, subject line A/B
  options, and reply-trigger templates. Triggers on: cold outreach, email
  sequence, LinkedIn outreach, DM sequence, founder outreach.
triggers:
  - cold outreach
  - email sequence
  - LinkedIn outreach
  - DM sequence
  - founder outreach
---

# cold-outreach-sequencer

Draft a personalized multi-touch outreach sequence across email, LinkedIn,
or Twitter/X DM. Produces five touches calibrated for a solo founder doing
early sales — not a bulk-send tool.

## When to use this skill

- Early sales (pre-CRM): reaching out to first 50–100 prospects manually.
- Partnership outreach: approaching potential integration partners or co-marketing.
- Investor outreach: seed-round cold intros to angels or pre-seed VCs.
- Conference follow-up: converting "nice to meet you" into a real conversation.

## When NOT to use this skill

- Warm intros exist: if you have a mutual connection, use the intro. Cold
  outreach is a fallback, not a preference.
- Existing customer expansion: use a customer success playbook, not a cold sequence.
- Mass blasts over 500 recipients: this skill produces personalized sequences.
  For bulk send, use a dedicated email platform with merge fields.

## Inputs

- **ICP description**: target role, company size, industry, specific pain point.
- **Value proposition**: 1–2 sentences on what you solve and for whom.
- **Sender bio**: your role and a one-line credibility hook (e.g., "founder,
  ex-Stripe eng, shipped X to 1000 companies").
- **Channel**: email / LinkedIn / Twitter DM (affects tone and length).

## Outputs

The skill emits a per-channel sequence. Default contract:

| Channel | Default touch count | Touches used | Channel notes |
|---|---|---|---|
| Email | 5 | 1–5 | Full sequence (intro → value-add → social proof → break-up → long-tail) |
| LinkedIn (connect + InMail) | 5 | 1–5 | Same cadence as email; connection note replaces Touch 1 subject line |
| Twitter / X DM | 2 | 1 + 4 | Norm of the channel — only intro + break-up; skip touches 2-3 + 5 |
| Cold call follow-up | 3 | 1 + 4 + 5 | Phone-call touch 0 → email intro → break-up → long-tail re-engage |

The 5-touch sequence below is the **default for email and LinkedIn**.
For Twitter/X DM, the implementer omits touches 2, 3, and 5. For cold-call
follow-up, the implementer renders touches 1, 4, and 5 only.

Five-touch sequence table (email/LinkedIn — base contract):

| Touch | Day | Subject / Opening | Body | Personalization variables | Reply trigger |
|---|---|---|---|---|---|
| 1 | 0 | [subject A / B] | [intro body] | {{first_name}}, {{company}}, {{recent_trigger}} | "Does this resonate?" |
| 2 | 3 | [subject A / B] | [value-add body] | {{pain_point}}, {{data_point}} | "Curious if you've seen this" |
| 3 | 7 | [subject A / B] | [social proof body] | {{mutual_connection}}, {{case_study}} | "Would this be useful?" |
| 4 | 14 | — | [break-up body] | {{first_name}} | "Worth a conversation?" |
| 5 | 30 | [subject A / B] | [long-tail re-engage] | {{trigger_event}} | "Thought of you when I saw this" |

See `references/sequence-templates.md` for full body templates with
`{{variable}}` placeholders per touch.

### Channel notes

- **Day 30 re-engage (Touch 5)**: email-only. LinkedIn and Twitter/X have
  lower tolerance for follow-ups beyond 14 days.
- **LinkedIn**: skip formal subject lines; use a one-line opening hook.
  Keep body under 150 words per message.
- **Twitter/X DM**: 250 chars per message. Tone: conversational, not sales-y.
  Touches 1 and 4 only; do not run a 5-touch DM sequence.

## Personalization Variables

| Variable | Description | How to source |
|---|---|---|
| `{{first_name}}` | Prospect's first name | LinkedIn / email signature |
| `{{company}}` | Their company name | LinkedIn / website |
| `{{recent_trigger}}` | A recent event (funding, launch, job posting) | Crunchbase / LinkedIn / Google alerts |
| `{{mutual_connection}}` | A shared connection | LinkedIn 2nd-degree / Twitter follows |
| `{{pain_point}}` | Specific pain inferred from their role/company | ICP research + interview synthesis |
| `{{data_point}}` | An industry stat or benchmark relevant to them | Public research, your product data |
| `{{case_study}}` | A brief result from a similar customer | Your own case study or a public benchmark |
| `{{trigger_event}}` | An event that makes re-engagement natural (new role, funding) | LinkedIn alerts |

## Example

**ICP:** Engineering managers at Series A startups.
**Value proposition:** Automated weekly engineering digest delivered in Slack.
**Sender:** Founder, ex-Stripe, shipped developer tools to 800 companies.
**Channel:** Email.

**Touch 1 (Day 0) — Intro:**
> Subject A: "Your deployment metrics — quick question"
> Subject B: "EMs at [Company size]-person startups"
>
> Hi {{first_name}},
>
> I saw {{company}} just raised a Series A — congrats. Curious: how does your
> team currently track deployment frequency for your Friday leadership update?
>
> We built a Slack bot that automates that digest. Happy to share what we've
> learned. Worth 15 minutes?
>
> [Name]

**Touch 4 (Day 14) — Break-up:**
> Hi {{first_name}}, not getting a response usually means bad timing or
> not the right fit. Either is fine. If deployment metrics ever become a
> priority, I'm happy to reconnect.

## References

See `references/sequence-templates.md` for all five touch body templates
with full `{{variable}}` markup.

## How it composes with other Walter-OS skills

- **Downstream of `customer-interview-synthesizer`**: ICP description and pain
  point language come directly from interview synthesis output.
- **With `pricing-experiment`**: the Day 3 value-add touch can reference a
  pricing page or benchmark that comes from the pricing experiment output.
- **With `content-writer`**: the Day 3 touch references a blog post or case
  study; `content-writer` drafts that asset.
- **With `weekly-review-coach`**: outreach metrics (reply rates, meetings booked)
  tracked as a sales KR in the weekly check-in.
