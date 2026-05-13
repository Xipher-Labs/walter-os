# Anki and Mochi Card Format Guide

## Core Principle: Minimum Information Principle

One fact per card. Each card should test exactly one thing. If a card requires
the learner to remember two independent facts to answer, split it into two cards.

**Bad** (two facts): "What is the PMF threshold and who coined it?"
**Good** (one fact each):
- "What percentage of users saying 'very disappointed' indicates PMF?" → 40%
- "Who created the 'very disappointed' PMF survey?" → Sean Ellis

---

## Anki Card Format

### Basic (front/back)

```
Front: [Question — specific, not vague]
Back: [Answer — maximum 3 sentences; include the "why" or context if short]
Tags: [tag1 tag2 tag3]
Interval hint: [1d | 3d | 7d]
```

**Interval guidance**:
- `1d`: fundamental concept you are encountering for the first time.
- `3d`: concept you half-knew; this sharpens it.
- `7d`: reinforcement of something you already know reasonably well.

### Cloze (fill-in-the-blank)

```
Text: {{c1::PMF threshold}} is the percentage of users who say they would be
  "very disappointed" without the product, above which indicates product-market
  fit.
Tags: [tags]
Interval hint: [1d | 3d | 7d]
```

Use Cloze when the concept is best learned by completing a statement, rather than
recalling from a question.

---

## Mochi Card Format

```
---
Front: [Question]
Back: [Answer]
Tags: [tag1, tag2, tag3]
---
```

Mochi uses Markdown on both front and back. Code blocks, lists, and bold/italic
are supported.

---

## Card Granularity Guide

| Too broad (bad) | Appropriately granular (good) |
|---|---|
| "Summarize Zero to One" | "What does Thiel mean by 'last mover advantage'?" |
| "What is GDPR?" | "What is the maximum fine for a Tier 2 GDPR violation?" |
| "Explain LTV:CAC" | "What LTV:CAC ratio is considered healthy for a $1-10M ARR SaaS?" |

---

## Example Cards (from a fictional source "The Decision Trap")

**Card 1 (Basic)**

```
Front: What cognitive bias causes people to value avoiding a loss more than
  achieving an equivalent gain?
Back: Loss aversion (Kahneman & Tversky, Prospect Theory). The pain of losing
  $100 feels roughly twice as intense as the pleasure of gaining $100.
Tags: cognitive-bias decision-making psychology
Interval hint: 3d
```

**Card 2 (Cloze)**

```
Text: According to Kahneman, System {{c1::1}} thinking is fast, automatic, and
  emotional, while System {{c2::2}} thinking is slow, deliberate, and logical.
Tags: kahneman thinking systems cognitive-psychology
Interval hint: 3d
```

**Card 3 (Basic)**

```
Front: What is the "planning fallacy" and how do you counteract it?
Back: The planning fallacy is the tendency to underestimate time, costs, and
  risks of future actions. Counteract with "reference class forecasting":
  look at how long similar projects actually took, then adjust.
Tags: planning-fallacy cognitive-bias project-management
Interval hint: 7d
```

---

## Tag Taxonomy Suggestions

Organize tags by domain, not by source. This lets you surface cards across
multiple books on the same topic:

- Domain: `strategy`, `marketing`, `finance`, `psychology`, `product`
- Sub-domain: `pricing`, `saas-metrics`, `decision-making`, `growth`
- Difficulty: `foundational`, `advanced`
- Source (optional): `zero-to-one`, `thinking-fast-slow`

---

## Import Instructions

**Anki**: Export cards as a `.txt` file with tab-separated Front/Back/Tags.
Import via File → Import → select the file. Map columns to the correct fields.

**Mochi**: Export cards as a `.mochi` file (JSON). Import via the Mochi
desktop app → File → Import → Mochi file.

The `knowledge-extraction` skill writes to:
`~/.config/walter-os/state/knowledge/YYYY-MM/<source-slug>.md`

Copy the cards section into your import file and follow the import instructions
above. No sync automation is provided — operator imports manually.
