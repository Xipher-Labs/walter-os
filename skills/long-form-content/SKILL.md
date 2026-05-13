---
name: long-form-content
description: "Long-form writing in three modes — essay (3500w default), podcast prep (8-12 question blocks), conference talk (three-act structure, slide outline, CFP abstract, speaker notes). Complements content-writer short-form. Keywords: essay, long-form, podcast prep, talk outline."
---

# long-form-content

Long-form writing in three distinct modes:

1. **Essay** — thesis-driven pieces between 3,000 and 8,000 words. Default
   length 3,500 words. Structured around a thesis, three to five pillar
   arguments, a counter-position, and a synthesis.
2. **Podcast prep** — episode outline with 8-12 question blocks, talking points,
   transitions, sound bites, and show notes structure.
3. **Conference talk** — three-act structure, slide deck outline, speaker notes,
   Q&A prep, and CFP abstract.

This skill produces the structure and first draft. For short-form content (blog
posts under 1,500 words, threads, newsletters), use `content-writer`.

## When to use this skill

- You are writing an essay, in-depth guide, or thought leadership piece.
- You are preparing to appear on a podcast as a guest or host.
- You are writing a conference talk and need the structure, slides outline,
  and CFP abstract.
- You want a speaker notes document alongside a slide outline.
- You are preparing for a long-form interview or panel.

## When NOT to use this skill

- You need short-form content: blog posts under 1,500 words, threads, or
  newsletters. Use `content-writer` instead.
- You need a product landing page. Use `landing-page-fast`.
- You need a business proposal. Use `proposal-writer`.
- You need marketing strategy. Use `marketing-strategist`.

## Inputs

**Common to all modes**:
- **Mode**: essay | podcast prep | conference talk
- **Topic**: what the piece is about (one paragraph)
- **Audience**: who will read or hear this
- **Tone**: authoritative, conversational, provocative, educational, etc.
- **Brand voice** (optional): load from `brand-creation` output if available

**Essay-specific**:
- **Target length**: default 3,500 words; range 3,000-8,000
- **Thesis**: the central claim you are making
- **Key evidence** (optional): data points, examples, or stories to include

**Podcast prep-specific**:
- **Episode premise**: 3-sentence description of the episode angle
- **Guest name and one-line bio** (or "host-only" for solo episodes)
- **Number of question blocks**: default 8-12

**Conference talk-specific**:
- **Talk duration**: 15, 30, or 45 minutes
- **Conference or venue**: helps calibrate audience sophistication
- **CFP deadline** (optional): if you need the abstract formatted for submission

## Outputs

**Essay mode**:
1. Full essay draft to target word count
2. Title options (3 alternatives)
3. Summary blurb (150 words) for sharing or cross-posting

**Podcast prep mode**:
1. Episode outline: title, premise, guest intro script
2. 8-12 question blocks, each with primary question + 2-3 follow-up probes +
   transition to next block
3. Sound bite targets (3-5 quotes to pull for clips)
4. Outro and call-to-action
5. Show notes structure

**Conference talk mode**:
1. Three-act narrative structure (hook, problem, solution, call-to-action)
2. Slide deck outline: slide title + one-sentence content per slide
3. Speaker notes for each slide
4. Q&A prep: 5-10 anticipated questions with suggested answers
5. CFP abstract (250-500 words depending on conference format)

## Sample usage

```
Skill: long-form-content

Mode: essay

Topic: Why most developer documentation fails and what to do about it.

Audience: Developer advocates and engineering leads at SaaS companies.

Tone: Authoritative but not academic. Uses examples from real products.

Thesis: Documentation fails because it is written for the author's mental
  model, not the reader's onboarding journey. The fix is not more content but
  better structure and progressive disclosure.

Target length: 3,500 words.
```

## How it composes with other Walter-OS skills

- `content-writer` — the short-form sibling. Use content-writer to repurpose
  an essay into a thread, a newsletter excerpt, or a LinkedIn post after this
  skill produces the long-form original.
- `brand-creation` — if your brand has a documented voice and tone, load it
  as input to this skill to ensure the essay matches your brand's style.
- `marketing-strategist` — the content calendar produced by marketing-strategist
  identifies which long-form pieces to produce each quarter. This skill
  executes those pieces.

## Prompt for your AI

**Essay mode**:

```
I need to write a long-form essay. Here is my context:

Mode: essay
Topic: [your topic]
Audience: [who will read this]
Tone: [authoritative | conversational | provocative | educational]
Thesis: [the central claim]
Target length: [3500 words default; range 3000-8000]
Key evidence or examples to include: [list or "none"]
Brand voice notes: [paste from brand-creation output or leave blank]

Please output:
1. Full essay draft to target word count using the structure in
   references/essay-structure.md
2. Three title alternatives
3. 150-word summary blurb
```

**Podcast prep mode**:

```
I need to prepare for a podcast episode. Here is my context:

Mode: podcast prep
Episode premise: [3-sentence description]
Guest name and bio: [one-liner or "host-only"]
Number of question blocks: [8-12]

Please output the full episode outline using the template in
references/podcast-prep-template.md.
```

**Conference talk mode**:

```
I need to prepare a conference talk. Here is my context:

Mode: conference talk
Topic: [your topic]
Talk duration: [15 | 30 | 45] minutes
Audience: [conference audience description]
CFP deadline: [date or "none"]

Please output:
1. Three-act narrative structure
2. Slide deck outline (title + one-sentence content per slide)
3. Speaker notes per slide
4. Q&A prep (5-10 anticipated questions + suggested answers)
5. CFP abstract (250-500 words)
Use the frameworks in references/talk-outline-framework.md.
```
