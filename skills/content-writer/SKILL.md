---
name: content-writer
description: >-
  Brand-voice-aware content writer. Five modes: blog post (800-2000 words,
  TL;DR + CTA), Twitter thread (8-15 tweets, hook-driven), YouTube script
  (intro hook + 3-act + outro CTA), newsletter issue (300-700 words), press
  release (AP-style). Reads assets/brand/<project>/voice.md when present.
  Triggers on: blog post, twitter thread, youtube script, newsletter, press release.
triggers:
  - blog post
  - twitter thread
  - youtube script
  - newsletter
  - press release
  - content writer
---

# content-writer

Brand-voice-aware content drafting skill. Five output modes, each with its
own structural guide. Reads a voice file when available; falls back to
generic professional SaaS voice.

## Model Routing

Use the long-form route for model selection:

```bash
source "$WALTER_OS_HOME/scripts/walter/lib/model-router.sh"
writing_model="$(walter_model_for longform)"
```

Default preference is Claude for voice, narrative structure, and nuanced prose.
Operators can override the alias in `~/.config/walter-os/overlay/personal.env`.

## When to use this skill

- Any structured content production: operator says "write a post about X."
- Generating content to support a launch, product update, or campaign.
- Drafting assets referenced in `cold-outreach-sequencer` (e.g., Day 3
  value-add blog post).

## When NOT to use this skill

- Real-time social media management: this produces drafts, not published posts.
- Video editing or production: this skill writes scripts only.
- Marketing strategy or channel selection: use `idea-lab` first to decide
  where to invest content effort.

## Outputs

Per-mode content artifact, brand-voice-aligned, ready-to-publish-after-review:

| Mode | Length | Sections | Use for |
|---|---|---|---|
| Blog post | 800-2000 words | TL;DR · body · CTA | Launches, product updates, technical explainers |
| Twitter thread | 8-15 tweets | Hook · payload · summary | Distribution + thought-leadership |
| YouTube script | 4-8 min spoken | Hook (8s) · 3-act · outro CTA | Demo videos, explainers, founder updates |
| Newsletter issue | 300-700 words | Subject A/B · body · 1 CTA | Recurring audience touchpoints |
| Press release | 400-600 words | AP-style headline · dateline · body · boilerplate | Funding, partnerships, milestones |

Each mode's structural guide lives in `references/<mode>-guide.md` (e.g.,
`references/blog-post-guide.md`, `references/twitter-thread-guide.md`).
See the per-mode sections below for content-shaping rules and the matching
reference file for full structural templates.

## Brand Voice Loading

The skill follows this fallback chain for voice:

1. If `WALTER_CURRENT_PROJECT` is set and
   `assets/brand/<project>/voice.md` exists, read it and apply the voice
   guidelines to every output.
2. If the file does not exist, warn once: "No voice.md found for
   [project]. Using generic professional SaaS voice." Do not block.
3. Use `brand-creation` skill to generate a `voice.md` for a new project.

## Mode: Blog Post

**Inputs:** topic + angle + target reader + CTA.

**Outputs:**
- TL;DR (40 words or fewer)
- H1 title (clear, specific, includes the target keyword)
- Intro: hook (1 sentence) + problem (2–3 sentences) + promise (1 sentence)
- 3–5 body sections, each with an H2 heading
- Conclusion + CTA (1 paragraph)
- Word count: 800–2000 words

See `references/blog-post-guide.md` for headline formulas, anti-patterns,
and a structural annotated example.

## Mode: Twitter Thread

**Inputs:** core insight + hook angle.

**Outputs:**
- Tweet 1: hook (provokes curiosity or makes a bold claim)
- Tweets 2–N: body (one idea per tweet; no filler; each tweet stands alone)
- Final tweet: CTA + thread summary in 1–2 sentences
- Length: 8–15 tweets; each tweet 280 characters or fewer

See `references/twitter-thread-guide.md` for hook formulas and anti-patterns.

## Mode: YouTube Script

**Inputs:** topic + target viewer + key takeaways + CTA.

**Outputs:**
- Intro hook (8 seconds or fewer when spoken at 150 wpm)
- 3-act body: setup, conflict, resolution
- Outro CTA (subscribe / link / offer)
- Annotated with `[VISUAL]` cues for b-roll or graphics

See `references/youtube-script-guide.md` for the 3-act structure template.

## Mode: Newsletter

**Inputs:** subject + body topic + CTA.

**Outputs:**
- Subject line A/B pair
- Preview text (90 chars max)
- Body: 300–700 words, single narrative thread
- CTA block (one action, not three)

See `references/newsletter-guide.md` for subject line formulas and
single-story structure.

## Mode: Press Release

**Inputs:** announcement + quotes + boilerplate.

**Outputs:**
- Headline (AP style: active verb, no jargon)
- Dateline: CITY, Month DD, YYYY
- Lede: who, what, when, where, why in 25 words or fewer
- Body: 2–3 paragraphs expanding on the lede
- Quote block (one executive quote + one third-party quote if available)
- Boilerplate: company description paragraph
- Contact block: name, email, phone

See `references/press-release-guide.md` for AP style rules and common errors.

## Example

**Mode:** Twitter thread
**Topic:** Why most dev tools companies underprice their product
**Hook angle:** Counterintuitive claim

> Tweet 1: Most dev tools companies are leaving 40% of revenue on the table.
> Not because of the product. Because of one pricing mistake. A thread.
>
> Tweet 2: The mistake: pricing to the feature, not to the outcome.
> Customers don't pay for API calls. They pay for the time they save and
> the incidents they avoid.
>
> Tweet 3: Example: a monitoring tool charges $0.01/metric. Their users
> think in terms of alerts and SLA breaches. The mental model mismatch
> means every invoice feels random.
>
> Tweet 4: Fix: find the outcome your best customers describe when they
> talk to their boss about your tool. That outcome = your value metric.
>
> Tweet 5: "We've had zero missed deployments since switching" → price on
> deployment risk. "We cut on-call hours by half" → price on engineer time.
>
> Tweet 6: How to find yours: ask 5 customers "what would you tell your
> boss this tool does?" in one sentence. The repeating phrase is your
> value metric.
>
> Tweet 7: Once you have it, test: raise your price 30%, reframe the
> pitch around the outcome, track conversion. Most find it holds or
> improves.
>
> Tweet 8: Your pricing page should answer "what's the cost of NOT having
> this?" — not "what features do you get?" Rewrite it around outcomes.
>
> Tweet 9 (CTA): If you're building a dev tool and want to test this
> framework: DM me your pricing page. Happy to share what I've seen work
> in the first 200 replies.

## How it composes with other Walter-OS skills

- **With `brand-creation`**: generates `voice.md` that this skill reads as
  its primary voice input.
- **With `landing-page-fast`**: blog posts drive SEO traffic back to the
  landing page; use consistent CTA language across both.
- **With `cold-outreach-sequencer`**: Day 3 value-add touch links to a blog
  post; draft the post here first, then embed the link.
- **With `nanobanana`**: generate hero images for blog posts or social
  assets to accompany Twitter threads.
