---
name: legal-doc-review
description: Walk through a third-party contract (NDA / SaaS T&Cs / MSA / vendor agreement / DPA) and flag the clauses that matter for solo founders or small teams. Use when reviewing a NDA before signing, a SaaS vendor's terms before adopting their service, a customer's MSA before accepting, an investor's term sheet before responding, or any contract where you cannot afford a full lawyer review for every word. Produces a redline-shaped output: PROBLEM clauses (negotiate or walk), QUESTION clauses (ask the counterparty), and OK clauses (accept as-is).
---

# Legal-doc review (founder grade)

The reading guide for contracts you cannot afford to send to a
lawyer in full. Not a substitute for one — call a lawyer when the
deal is material — but a way to triage in under an hour.

## Disclaimer (read this once)

This skill produces **a triage**, not legal advice. It teaches you
which clauses to look at, what the standard ranges are, and which
deviations should make you ask for changes. It does not draft
language, it does not assess enforceability under your specific
jurisdiction, and it cannot replace counsel for material deals.

Material deals (anything where the downside cost could materially
hurt the business — $50k+ for a one-person shop, $250k+ for a small
team, anything in a regulated industry, anything with personal
liability) should still go to a lawyer.

## When to use this skill

| Document type | Use this skill | Send to a lawyer |
|---|---|---|
| Mutual NDA, off-the-shelf | ✅ | only if it has unusual clauses |
| One-way NDA you are signing | ✅ | only if it has unusual clauses |
| Vendor SaaS T&Cs (you are the customer) | ✅ | only if vendor handles money / regulated data |
| Customer MSA (you are the vendor, > $50k ARR deal) | ✅ first pass | yes, before signing |
| Customer MSA (small deal) | ✅ | only if customer red-pens it heavily |
| Investor term sheet | ✅ first pass | always — material |
| Employment agreement / contractor agreement (yours, with someone else) | ✅ first pass | yes, before signing the first one — then template-ize |
| Real estate / equity / acquisition documents | ❌ | always |

## The 12 clauses that actually matter

These are the clauses that most often hide real cost. Read these
first regardless of document type. Everything else is usually
boilerplate.

### 1. Term & termination

What to look for:
- **Auto-renewal**: is there one, and how many days notice to opt
  out? PROBLEM if > 60 days.
- **Termination for convenience**: can either party walk with N
  days notice? OK is 30-90 days mutual. PROBLEM if asymmetric
  (only the counterparty can walk).
- **Termination for cause**: what counts as cause? OK is material
  breach not cured within 30 days. PROBLEM if vague ("at the other
  party's discretion").

### 2. Payment terms

- **Net days**: net 30 is standard, net 45 acceptable, net 60+ is
  PROBLEM for a small vendor with cashflow constraints.
- **Late fees**: 1-1.5%/month is standard. Missing entirely is OK
  if you are the customer, PROBLEM if you are the vendor.
- **Price increases**: how much notice, what cap. OK is 60-90
  days notice with CPI or 5% cap. PROBLEM is "at our discretion".

### 3. Liability cap

The most important number in the contract. Standard caps:
- Mutual cap at 12-months-of-fees-paid. OK.
- Mutual cap at 1x annual contract value. OK.
- Asymmetric cap (your cap = fees, their cap = unlimited). PROBLEM.
- No cap at all. PROBLEM.
- Cap excludes specific categories (IP infringement, gross
  negligence, confidentiality breach). Usually OK; these are
  typically carved out from the cap on both sides.

For consumer-facing SaaS T&Cs you sign, cap is almost always
"$0 / max $100". That is the industry default. Don't try to
negotiate it for $20/mo services.

### 4. Indemnification

- **You indemnify them for your IP claims**: OK if mutual.
  PROBLEM if asymmetric.
- **You indemnify them for everything**: PROBLEM.
- **Mutual indemnification for IP infringement only**: OK.
- **Indemnification capped to liability cap**: OK.
- **Indemnification UNcapped**: PROBLEM. Indemnity should be inside
  the cap unless explicitly carved out.

### 5. Intellectual property

Read this slowly. Where is the IP boundary?

- **Pre-existing IP stays with the owner**: required. Missing is
  PROBLEM.
- **Work product**: who owns it? Default for a customer
  relationship is the customer owns the deliverables. For a SaaS
  T&Cs, the SaaS provider owns their platform; you own your data.
- **License back of customer data for service improvement**: OK if
  scoped narrowly (improving the service for you). PROBLEM if
  broad ("training AI models", "publishing aggregated data"
  without anonymization specifics).

### 6. Confidentiality

- **Term**: confidentiality survives termination for 2-5 years.
  Perpetual confidentiality is OK for trade secrets, PROBLEM if
  applied to everything.
- **Carve-outs**: information that becomes public, was already
  known, comes from a third party without an NDA. Standard. Missing
  = PROBLEM.
- **Permitted disclosures**: to lawyers, accountants, investors
  under their own NDA. Standard. Missing for an NDA you sign with
  a vendor is OK; missing for an NDA you sign with an investor
  is QUESTION.

### 7. Data protection / privacy

- **Sub-processor list + notification**: vendor must disclose
  sub-processors and notify of changes. OK. Missing entirely =
  PROBLEM if you process EU user data.
- **DPA included or attached**: vendor must offer a DPA for GDPR
  / CCPA compliance. PROBLEM if not.
- **Breach notification**: how many days to notify you of a
  breach. OK is 72 hours (GDPR requirement). PROBLEM is 30+ days
  or vague.
- **Data location**: where does data live? QUESTION if the doc
  doesn't say. PROBLEM if all data goes to a single country with
  weak privacy law.

### 8. Service levels (if SaaS T&Cs)

- **Uptime commitment**: 99.5%-99.9% is standard for B2B SaaS,
  99% is acceptable for low-cost tools. PROBLEM if no commitment
  or vague ("best efforts").
- **SLA credits**: how do you get compensated for downtime? OK is
  pro-rated service credits. PROBLEM if SLA is purely aspirational
  with no remedy.

### 9. Governing law & dispute resolution

- **Governing law**: usually the vendor's home state. OK for small
  deals, PROBLEM if you are the vendor and the customer puts
  their own jurisdiction without reciprocity.
- **Venue**: where would litigation happen? Reasonable for SaaS to
  pick their HQ city. PROBLEM if it requires you to travel to a
  remote jurisdiction.
- **Arbitration vs. court**: arbitration is faster + cheaper but
  caps damages and forecloses class actions. OK if mutual;
  PROBLEM if asymmetric or in a hostile forum.
- **Class action waiver**: standard in consumer T&Cs. OK.

### 10. Assignment

- **Change of control**: what happens if either party is acquired?
  OK is "may assign without consent in connection with merger / sale
  of substantially all assets". PROBLEM if vendor can assign to a
  competitor without your consent.

### 11. Modifications

- **Can the vendor change the terms unilaterally?** PROBLEM. OK is
  "with N days notice, you can terminate without penalty if you
  disagree".
- **Change history**: is there a changelog or version number on the
  terms? OK if yes. QUESTION if no (you cannot prove what you
  agreed to).

### 12. Force majeure

Usually boilerplate. Read for:
- **Pandemics / cyberattacks**: post-2020, these should be
  explicit. PROBLEM if they are not.
- **Both parties' obligations suspended**: standard. PROBLEM if
  only the counterparty's are.

## Output format

The skill produces a `legal/reviews/<doc-name>.review.md` file
with three sections:

```markdown
# Review: <document name>

**Source**: path/to/the/document
**Reviewed**: 2026-05-20
**Reviewer**: walter-os legal-doc-review skill (not legal advice)

---

## PROBLEM — negotiate or walk

- **§3.2 Auto-renewal**: 90-day notice window. Industry standard is
  30-60 days. Ask to reduce to 30.
- **§7.1 Liability cap**: vendor's cap is unlimited; your cap is
  fees paid in last 12 months. Ask for mutual cap or carve-out for
  gross negligence on their side.
- **§12 Modifications**: vendor can change terms unilaterally with
  no notice. Ask for 30-day notice + right to terminate without
  penalty.

## QUESTION — clarify with the counterparty

- **§5 Data location**: doc doesn't specify where customer data is
  stored. Ask which region(s) and whether it can be pinned.
- **§9 Sub-processors**: doc references sub-processors but doesn't
  list them. Ask for the current list and notification mechanism
  for changes.

## OK — accept as-is

- §1 Definitions — standard
- §2 Order of precedence — standard
- §4 Confidentiality — mutual 3-year survival, all carve-outs
  present
- §6 Force majeure — explicit on cyberattacks and pandemics
- §8 Governing law — vendor's HQ state, reciprocal venue
- §10 Assignment — change-of-control clause is mutual
- §11 Notices — email + certified mail, both parties

## What this review does NOT cover

- Jurisdiction-specific enforceability — counsel should review.
- Tax treatment of the deal — accountant should review.
- Industry-specific regulatory requirements (HIPAA, PCI-DSS,
  financial services) — relevant specialist should review.

## Next steps

1. Send PROBLEM and QUESTION items to the counterparty.
2. If counterparty refuses material PROBLEM items: counsel review
   before walking or signing.
3. If counterparty agrees: re-run this skill on the redlined
   version to verify.
```

## Anti-patterns (your behavior)

1. **Signing without reading clauses 1-12.** Every contract that
   has any of these is worth 30 minutes. Most boilerplate is
   boilerplate; these 12 are not.
2. **Treating this as a final review.** PROBLEM and QUESTION items
   above the operator's discretionary cost threshold still need
   counsel.
3. **Negotiating every PROBLEM at the same intensity.** Pick the
   top 3. Counterparties get fatigue too; spend your goodwill on
   the items that matter (liability, IP, termination usually).
4. **Skipping the QUESTION section.** Things you don't ask about
   often turn into the problems you can't fix later.

## Anti-patterns (vendor behavior to spot)

1. **Long terms that say nothing for many paragraphs and then drop
   a one-sentence asymmetric clause.** Section 12.4(b) is usually
   where the actual deal is.
2. **"Industry standard" pushback** on liability and indemnity. OK
   sometimes; usually a stall. Push back with the actual industry
   numbers.
3. **Promises to add a clause "in a future version".** If it's
   important, add it now. Future-version commitments are not
   enforceable.
4. **Mentioning a DPA but not attaching one.** If they cannot
   produce the DPA on request, they probably don't have one.

## Hard rules

- **Always output a review file**, even if PROBLEM is empty. Future
  re-reads need the audit trail.
- **Always flag the deal threshold** at the top of the review. If
  the financial exposure is over the operator's set threshold,
  emit the line "MATERIAL DEAL — counsel review required regardless
  of triage outcome".
- **Never copy contract text into the review verbatim if the
  document is marked confidential.** Reference clauses by section
  number; do not reproduce.

## Integration with other Walter-OS skills

- **`terms-policy-generator`** — the inverse: this skill REVIEWS
  contracts; that one DRAFTS them.
- **`oss-readiness`** — when prepping a public release, runs this
  skill on the OPEN-SOURCE LICENSE chosen for the project + any
  CLA template.
- **`regulatory-research-international`** — when a clause touches
  a jurisdiction-specific requirement (data residency, mandatory
  arbitration venue), this skill defers to that one for local-law
  research.

## References

- Walter-OS execution plan Phase 4.1.2.
- ABA model contract clauses (where they conflict with founder
  reality, founder reality wins — but knowing the model helps
  negotiate).
- `skills/terms-policy-generator/SKILL.md` — the drafting
  counterpart.
- `skills/track-pending/SKILL.md` — track follow-up items from a
  review (e.g., "ask for DPA in 30 days").
