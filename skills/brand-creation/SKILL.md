---
name: brand-creation
description: Create a complete brand identity for a project — name, logo, color palette, typography, and voice/tone — using nanobanana for visual generation. Use this skill when starting a new project ([Project A], [Project B], hackathons), when the user asks to "create a brand", "design a logo", "make an identity", "moodboard for X", or wants to formalize the look and feel of a product. Produces deliverables to assets/brand/<project>/ ready for use in landing pages, decks, and social.
---

# Brand Creation

Pipeline that takes a brief and produces a usable brand kit in ~2 hours.
Combines `nanobanana` (image generation) with curated typography, palette
extraction, and voice-tone definition.

## Output structure

```
assets/brand/<project>/
├── brief.md              # the input that produced everything
├── moodboard/
│   ├── 01-{slug}.png
│   ├── 01-{slug}.prompt.txt
│   └── ...               # 6–10 images, sidecar prompts
├── logo/
│   ├── logo-mark.svg
│   ├── logo-mark.png         (1024px, transparent bg)
│   ├── logo-wordmark.svg
│   ├── logo-lockup.svg       (mark + wordmark)
│   └── iterations/           # all the rejected drafts, kept for trail
├── palette.json
├── palette-preview.png
├── typography.md
├── voice-tone.md
└── usage-guide.md            # do's and don'ts (1 page)
```

## Phase 1: Brief (10 min)

Capture:
- **Project name** (locked or candidates).
- **One-line description** of what it does.
- **Target audience** in concrete terms ("procurement officers in
  Argentine municipalities, age 35–55, low-tech but motivated by
  transparency").
- **Adjacent references** the operator likes ("the Stripe of X", "feels
  like Linear meets Notion"). Concrete brands beat abstract adjectives.
- **Forbidden territory** ("not corporate-bank", "not crypto-bro").

Save to `brief.md`. Everything downstream references this.

## Phase 2: Moodboard (20 min)

Generate 6–10 images via `nanobanana` exploring different directions.
Goal: explore divergent options before committing.

Prompt template:
```
Hero brand image for a [project type] called [name]. The product helps
[audience] [problem]. Visual direction [N]: [direction]. Style: [PBR
materials / flat illustration / editorial photo / isometric 3D / etc.].
Color emphasis: [warm earth / cool tech / monochrome / vibrant clash /
muted serious]. Composition: [hero subject centered / pattern / abstract
geometric / scene]. No text. Soft solid background.
```

Generate 2–3 images per direction across 3 directions = 6–9 images. Operator
picks the direction that resonates. Save sidecar prompts always.

## Phase 3: Logo (40 min)

Logo variations follow the chosen direction.

### Wordmark (text-only)
Try 3–5 typography pairings. Use `nanobanana` Pro tier for accurate text
rendering. Reference fonts by name when known ("Inter", "Söhne",
"Migra", "ABC Diatype").

### Mark (symbol-only)
Generate 6 symbol options that capture the project's metaphor. For [Project A],
metaphors might be: gavel + chain link, ballot + checkmark, tender envelope
sealed. For [Project B]: vault door + DNA helix, locked diary, encrypted heart.

Iterate the chosen mark 2–3 times via multi-turn editing in `nanobanana`
to refine. Each turn keeps the previous output as reference for identity
preservation.

### Lockup
Combine mark + wordmark in a horizontal arrangement. Define safe zone
(typically the height of the wordmark x-height around all sides).

### SVG conversion
The output of `nanobanana` is raster. For final logo, either:
- Trace to SVG using Penpot/Illustrator/Vectorizer.AI as the human step
- OR keep raster at 4K resolution and ship .png — acceptable for hackathons,
  not for production brands

For a production brand ([Project A], [Project B]), the SVG is non-optional. The
agent stops here and asks the operator to handle the trace step.

## Phase 4: Palette (15 min)

Extract dominant colors from the chosen moodboard images. Curate to:

- **Primary** — the brand's signature color. Used for CTAs, key UI accents.
- **Secondary** — complement, used for hovers/highlights.
- **Neutrals** — 4–6 grays from near-white to near-black, slightly tinted
  toward the primary for cohesion.
- **Semantic** — success (green), warning (amber), danger (red),
  info (blue). Use Radix Colors as a starting point if no strong brand
  pull.

`palette.json` format:

```json
{
  "primary": { "50": "#...", "100": "#...", ..., "900": "#..." },
  "secondary": { "50": "#...", ... },
  "neutral": { "50": "#...", ... },
  "success": { "500": "#..." },
  "warning": { "500": "#..." },
  "danger": { "500": "#..." },
  "info": { "500": "#..." }
}
```

Generates `palette-preview.png` showing all swatches with labels for
quick reference.

## Phase 5: Typography (10 min)

Pick a pairing:
- **Display** — for headers and hero. Often a distinctive serif or display
  sans (e.g., Migra, Tobias, ABC Diatype, GT Sectra).
- **Body** — readable, neutral. Inter, Söhne, Geist, IBM Plex Sans.
- **Mono** — for code, ticker-style data. JetBrains Mono, Geist Mono, IBM
  Plex Mono.

Constraints:
- Hackathons: Google Fonts only (free, easy to embed).
- Production brands: licensed fonts OK if budget allows.

`typography.md` documents the pairing with size scale, weight, line-height
recommendations.

## Phase 6: Voice and tone (15 min)

Define how the brand talks. Format:

```md
## Voice (consistent)

- **Direct** — short sentences, active verbs, no filler.
- **Honest** — admit limitations, no overclaiming.
- **Knowledgeable** — domain terminology when accurate, plain language
  when not.

## Tone (varies by context)

- **In docs/help**: warm, patient, examples-first.
- **In errors**: precise, blame-the-system-not-the-user.
- **In marketing**: confident, specific, anti-hype.

## Forbidden

- "Game-changing", "revolutionary", "innovative", "best-in-class".
- Corporate hedging: "leverage synergies", "robust solutions".
- Crypto bro: "WAGMI", "GM", "wen mainnet".
```

## Phase 7: Usage guide (10 min)

One-page do's-and-don'ts with example pairings:
- Logo on dark bg: ✅ light variant. ❌ original variant inverted.
- Palette: ✅ primary on neutral. ❌ primary on secondary (clash).
- Typography: ✅ display for headers, body everywhere else. ❌ display for
  body copy.
- Spacing: 8pt grid baseline.

## Integration with Google Drive

After operator confirmation, the kit auto-uploads to:
`Drive/Brands/<project>/<YYYY-MM-DD>/`. Provides shareable view-only link.

## What this skill does NOT do

- Trademark search. Operator does this manually before locking a name.
- Print specs (CMYK, paper stock). Out of scope; this is for digital.
- Animated/motion brand. Static identity only.
- Brand strategy/positioning. That's a separate exercise.
