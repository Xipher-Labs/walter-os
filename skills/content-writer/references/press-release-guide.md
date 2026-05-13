# Press Release Guide

Structural reference for the `content-writer` press release mode.
Follows AP (Associated Press) style conventions.

## Structure

```
FOR IMMEDIATE RELEASE
— or —
EMBARGOED UNTIL: [Date, Time, Timezone]

[HEADLINE — active verb, no jargon, ≤10 words]
[SUBHEADLINE — optional, one sentence expanding on the headline]

[DATELINE]: CITY, Month DD, YYYY — [Lede paragraph]

[Body paragraph 1 — expand on the lede; who, what, why it matters]

[Body paragraph 2 — supporting details, context, market data if relevant]

[Quote block]
  "[Quote from executive]," said [Name], [Title], [Company].

[Optional: third-party quote]
  "[Quote from partner/customer/analyst]," said [Name], [Title], [Organization].

[Body paragraph 3 — additional product or company details if needed]

### About [Company]
[Boilerplate: 2-3 sentences. Company description, founding date, what it
does, notable stats. Identical across all releases.]

###
(three hashes = end of release in AP style)

Media Contact:
[Name]
[Title]
[Email]
[Phone]
[Website]
```

## Headline Rules (AP Style)

- Active voice: "Company Launches X" not "X Is Launched by Company."
- No jargon: write for a general reporter, not your engineering team.
- No buzzwords: "revolutionary," "disruptive," "game-changing" — cut them.
- Title case for the headline.
- 10 words or fewer.

Examples:
- Good: "Acme Analytics Raises $4M to Automate Engineering Metrics Reporting"
- Bad: "Acme Analytics Disrupts the Developer Observability Space with Revolutionary Platform"

## Lede Paragraph

Answers who, what, when, where, why in 25 words or fewer. Journalists
decide in the first sentence whether to keep reading.

Example:
> Acme Analytics today announced a $4M seed round led by Example Ventures
> to expand its Slack-native engineering metrics platform to 500 additional
> teams by Q4.

## Quote Guidelines

- One executive quote maximum from the company.
- The quote should add perspective, not restate the lede.
- One third-party quote (customer, investor, or analyst) adds credibility.
- Both quotes should sound like real speech, not marketing copy.

Good quote: "We were spending every Friday manually pulling deployment data.
Acme cut that to zero." — Maria Chen, Engineering Manager, ExampleCorp.

Bad quote: "We are thrilled to be part of this revolutionary journey as we
disrupt the metrics space." — no one talks like this.

## Boilerplate

Write once. Reuse verbatim on every release. Include:
- What the company does (one sentence)
- Who it serves
- One notable metric or milestone (customer count, ARR, notable customer)
- Founding year and location

Example:
> About Acme Analytics: Acme Analytics provides engineering managers with
> automated metrics digests in Slack. Founded in 2024 and based in San
> Francisco, Acme serves over 300 engineering teams at Series A–C startups.
> Learn more at acmeanalytics.com.

## Common Errors

- Embargo broken: if embargoed, include the date in the header AND in
  the email subject when distributing.
- Missing contact info: journalists need a reply-to, not just a website.
- Too long: ideal release is 400–600 words. Longer = less likely to be read.
- Passive voice throughout: reads as corporate-speak; use active verbs.
