---
name: weekly-review-coach
description: >-
  Friday weekly retrospective coach and OKR check-in. Three sections: retro
  (what went well / what didn't / surprises), OKR check-in (red/yellow/green
  per KR with blockers), next-week plan (top 3 priorities + reasoning). Loads
  last week's review for continuity. Triggers on: weekly review, friday retro,
  OKR check-in, weekly planning.
triggers:
  - weekly review
  - friday retro
  - OKR check-in
  - weekly planning
---

# weekly-review-coach

Solo founder weekly retrospective and planning skill. Three structured
sections: retro, OKR check-in, and next-week plan. Designed for a 20–30
minute Friday session.

## When to use this skill

- Friday (or any end-of-week session): structured retrospective before the
  weekend.
- Quarterly OKR reviews: deeper check-in when a quarter ends.
- When feeling stuck or unfocused: surfaces what is actually happening
  versus what was planned.

## When NOT to use this skill

- Mid-week project postmortems: use a focused incident retro instead.
- Team retrospectives with multiple participants: this is a solo tool.
  For team retros, use a dedicated retrospective format (Start/Stop/Continue).
- Replacing project planning: future project specs go in `docs/specs/`.

## State Loading

The skill uses the file convention:

```
~/.config/walter-os/state/weekly-reviews/YYYY-Www.md
```

For example: `~/.config/walter-os/state/weekly-reviews/2026-W19.md`

**If the previous week's file exists**, the skill reads it and uses:
- Last week's "top 3 priorities" as continuity prompts ("Last week you
  committed to X — did that happen?")
- KR status from last week as a baseline for this week's check-in.

**If no prior file exists**, the skill starts fresh with no continuity prompts.

**File is never committed to the repo.** It is operator-private state.
Add `~/.config/walter-os/state/` to your global gitignore if not already
present.

## Section 1: Retro

Three sub-sections. The agent asks one question at a time, records the
answer, and asks a follow-up. It does NOT evaluate or score — the operator
owns the narrative.

### What went well

Prompts:
1. "What went well this week?"
2. "Why did it work? (What conditions allowed it?)"
3. "What would you repeat or build on next week?"

### What didn't go as planned

Prompts:
1. "What didn't go the way you expected?"
2. "What's the root cause? (One level deeper — why did that happen?)"
3. "What's one concrete change you'd make if this situation repeats?"

### What surprised you

Prompts:
1. "What surprised you this week — positive or negative?"
2. "What does that imply for next week or the next quarter?"

## Section 2: OKR Check-In

The operator provides their active KRs in free text. The skill prompts for
each KR:

1. "Current value vs. target?" (operator provides the numbers)
2. "Status: red / yellow / green?" (operator provides the judgment —
   the skill does not set thresholds automatically)
3. "Top blocker for this KR?"

**Output format — KR status table:**

| KR | Current | Target | Status | Blocker |
|---|---|---|---|---|
| [KR text] | [value] | [target] | [R/Y/G] | [blocker or "none"] |

The skill flags conflicts between KRs (e.g., two KRs both at red with the
same root cause), but does not override the operator's status judgment.

## Section 3: Next-Week Plan

Three priority slots. For each priority, the operator answers:
1. "What is the priority?"
2. "Why is this #1 / #2 / #3 — not just what it is, but why this rank?"
3. "What does done look like by Friday?"

The skill confirms the three priorities are coherent with the OKR status
table (e.g., flags if no priority maps to a red KR). It does not override
the operator's ranking.

## Outputs

A completed `YYYY-Www.md` file written to
`~/.config/walter-os/state/weekly-reviews/`.

**File format:**

```markdown
---
week: YYYY-Www
date: YYYY-MM-DD
---

## Retro

### What went well
[Operator's answer + why + what to repeat]

### What didn't go as planned
[Operator's answer + root cause + concrete change]

### What surprised me
[Operator's answer + implications]

## OKR Check-In

| KR | Current | Target | Status | Blocker |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

## Next-Week Priorities

1. **[Priority 1]** — Done when: [definition]. Why #1: [reasoning].
2. **[Priority 2]** — Done when: [definition]. Why #2: [reasoning].
3. **[Priority 3]** — Done when: [definition]. Why #3: [reasoning].
```

## Example

**Condensed session transcript (15 exchanges):**

---

**Skill:** Let's start the weekly review. First, what went well this week?

**Operator:** We closed two enterprise pilots. Both signed LOIs.

**Skill:** Nice — why did that close now? What changed or worked?

**Operator:** We had the competitor's pricing as an anchor. Made our value
proposition easier to explain.

**Skill:** Good data point. Would you repeat that approach — leading with
the competitor anchor — in future calls?

**Operator:** Yes. Add it to the standard sales deck.

**Skill:** Noted. What didn't go as planned?

**Operator:** The integration with the third-party API took 3x longer than
estimated. Blocked the demo we promised for Friday.

**Skill:** One level deeper — why did it take 3x? What was the root cause?

**Operator:** We didn't read their changelog before starting. There was a
breaking change from 3 months ago.

**Skill:** Concrete change: what would you do differently next time?

**Operator:** Check the changelog before any integration sprint starts.

**Skill:** Got it. What surprised you this week?

**Operator:** Competitor A dropped their enterprise pricing by 30%.

**Skill:** What does that imply for next week?

**Operator:** I need to run a pricing experiment to check if our anchor
is still valid.

**Skill:** Understood. Now let's check OKRs. What are your active KRs?

**Operator:** KR1: 5 enterprise pilots by end of quarter. KR2: reduce
integration time to under 2 days. KR3: publish 4 blog posts.

**Skill:** KR1 — pilots. Current vs. target?

**Operator:** 2 signed this week. 3 total. Target is 5. Status: yellow.
Blocker: one pilot stalled pending legal review.

**Skill:** KR2 — integration time?

**Operator:** Still measuring. Last integration took 6 days (the one that
slipped this week). Status: red. Blocker: no formal pre-integration checklist.

**Skill:** KR3 — blog posts?

**Operator:** 1 published. 3 to go. Status: red. Blocker: no drafts started.

**Skill:** Two KRs at red. I notice both have blockers that are process
gaps (checklist, drafts). Worth addressing this in your Week 1 priorities?

**Operator:** Yes — priority 1 is writing the integration checklist.

**Skill:** What does done look like by Friday?

**Operator:** A one-page checklist merged to the repo. Used on the next
integration before we start.

**Skill:** Priority 2?

**Operator:** Draft two blog posts. Done when two drafts exist in the
content/ folder, even if unpolished.

**Skill:** Priority 3?

**Operator:** Follow up on the stalled legal review. Done when I have a
clear timeline from their legal team by end of Wednesday.

**Skill:** Summary written to `~/.config/walter-os/state/weekly-reviews/2026-W20.md`.

---

## How it composes with other Walter-OS skills

- **With `competitor-radar`**: the weekly radar report feeds into "what
  surprised you" — run `competitor-radar` before the weekly review.
- **With `customer-interview-synthesizer`**: synthesis sessions count as
  KR checkpoints ("completed N customer interviews this week").
- **With `pricing-experiment`**: a red KR on revenue or conversion can
  trigger a `pricing-experiment` session to retest assumptions.
- **With `cold-outreach-sequencer`**: outreach reply rates and meetings
  booked are natural KR candidates for early-stage sales OKRs.
