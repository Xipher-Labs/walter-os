---
name: knowledge-extraction
description: "Extract structured knowledge from books, papers, articles — key claims, frameworks, Anki cards, spaced repetition. Two phases: Phase A extracts, Phase B converts to Anki/Mochi cards. State at ~/.config/walter-os/state/knowledge/. Keywords: extract knowledge, summarize paper, book notes, Anki cards, learning from."
---

# knowledge-extraction

Structured knowledge extraction from any long-form source: books, papers,
articles, or Markdown documents. Two-phase approach:

- **Phase A (Extract)**: key claims with citations, named frameworks and mental
  models, actionable takeaways, open questions, and follow-up reads.
- **Phase B (Spaced Repetition)**: converts Phase A claims into Anki/Mochi-
  compatible flashcards (Q/A format with tags and review interval hints).

Cards are stored at `~/.config/walter-os/state/knowledge/YYYY-MM/<source-slug>.md`
(out-of-repo, operator-private). No actual Anki or Mochi sync — the operator
imports the file manually.

## When to use this skill

- You have finished a book or paper and want to extract and retain the key ideas.
- You are reading a long article and want to convert it into a structured
  knowledge document.
- You want to build Anki/Mochi flashcards from your reading notes.
- You want to surface past extractions for review via `weekly-review-coach`.
- You are doing research and want a structured output before synthesizing across
  multiple sources.

## When NOT to use this skill

- You need to synthesize multiple interview transcripts (use
  `customer-interview-synthesizer`).
- You need a market research report or competitive analysis (use
  `competitor-radar`).
- You need to write an essay or long-form piece from your notes (use
  `long-form-content`).
- You are extracting technical API documentation (use the relevant
  infrastructure skill or `postgres-cli`).

## Inputs

**Common to both phases**:
- **Source**: the text to extract from. Paste directly, or provide a file path
  if the source is in the operator's filesystem.
- **Source metadata**: title, author, publication year, URL or ISBN.
- **Source slug**: short kebab-case identifier for the output file name,
  e.g., `thinking-fast-and-slow` or `zero-to-one-thiel`.

**Phase A additional inputs**:
- **Focus area** (optional): if you want extraction focused on a specific topic
  within the source (e.g., "only extract claims about pricing strategy").

**Phase B additional inputs**:
- **Phase A output**: the extracted claims from Phase A.
- **Card format**: Anki or Mochi (default: Anki).

## Outputs

**Phase A output** (stored in knowledge file):

1. **Source metadata block**: title, author, year, URL/ISBN, date extracted.
2. **Key claims table**: claim / citation / confidence (H/M/L).
3. **Frameworks and mental models**: named frameworks introduced or described,
   with a one-paragraph explanation of each.
4. **Actionable takeaways**: 3-10 specific actions the operator can take,
   derived from the source.
5. **Open questions**: questions the source raised but did not answer; questions
   for follow-up research.
6. **Follow-up reads**: 3-5 books, papers, or articles the source cited or that
   would deepen understanding.

**Phase B output** (appended to knowledge file):

1. **Anki/Mochi cards**: Q/A pairs for each key claim. One fact per card.
   Format follows `references/anki-format.md`.
2. **Tags**: 3-5 tags per card for deck organization.
3. **Review interval hint**: suggested initial interval (1d, 3d, 7d) based on
   claim complexity.

## Sample usage

```
Skill: knowledge-extraction

Phase: A (extraction only; I'll run Phase B separately)

Source slug: zero-to-one-thiel

Source metadata:
  Title: Zero to One
  Author: Peter Thiel with Blake Masters
  Year: 2014
  ISBN: 9780804139021

Source: [paste chapter or full book text here, or describe the key chapters]

Focus area: Claims about competition, monopoly, and startup strategy.
```

Expected output: A structured extraction document with 15-20 key claims,
3-5 frameworks (monopoly vs competition framework, the last mover advantage
concept, secrets framework), 8 actionable takeaways, and 5 open questions
about applying Thiel's framework to regulated markets.

## How it composes with other Walter-OS skills

- `weekly-review-coach` — surface past extractions due for review. The coach
  can scan the `~/.config/walter-os/state/knowledge/` directory and list files
  not reviewed in the past 30 days.
- `long-form-content` — use knowledge-extraction output as the research
  foundation for an essay. The key claims and frameworks feed directly into the
  pillar arguments.
- `customer-interview-synthesizer` — for sources that are interview transcripts
  or qualitative research, use synthesizer instead; it is optimized for that
  source type.

## Prompt for your AI

**Phase A (extraction)**:

```
I want to extract structured knowledge from a source. Here is my context:

Phase: A
Source slug: [kebab-case-identifier]
Source metadata:
  Title: [title]
  Author: [author]
  Year: [year]
  URL or ISBN: [identifier]
Focus area: [specific topic, or "all"]

Source text: [paste text here]

Please output the extraction document using the template at
references/extraction-template.md:
1. Source metadata block
2. Key claims table (claim | citation | confidence H/M/L)
3. Frameworks and mental models (named, with one-paragraph explanation)
4. Actionable takeaways (3-10 specific actions)
5. Open questions (what the source raised but did not answer)
6. Follow-up reads (3-5 related works)
```

**Phase B (card generation)**:

```
I want to convert Phase A extraction into flashcards. Here is the Phase A output:

[paste Phase A document]

Card format: [Anki | Mochi]

Please output Anki/Mochi cards following the format at
references/anki-format.md. One fact per card. Include:
- Front (question)
- Back (answer, maximum 3 sentences)
- Tags (3-5 per card)
- Review interval hint (1d | 3d | 7d)
```
