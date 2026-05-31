---
name: impeccable
description: Design-craft and anti-AI-slop authority for ANY user-facing interface (web, app, or component) — building, designing, refining, or reviewing UI to senior-product-designer quality. Covers color, typography, layout, spacing, motion, interaction, states, and UI copy. Triggers on "polish the UI", "make it pop", "feels generic", "clean it up", "more premium", "looks like AI slop", "fix this design". Defer to frontend-quality for WCAG/Core-Web-Vitals gating and mobile-design-system for native mobile.
license: Apache-2.0
---

# Impeccable

World-class design craft for AI agents. This skill makes the difference
between generic AI output and work that looks like a senior product designer
made it.

## When to use

Load this skill when building, designing, refining, or reviewing any
user-facing interface (web, app, or component) and the work should look
intentional rather than templated. Triggers include "polish the UI", "make it
pop", "feels generic", "clean it up", "more premium", "looks like AI slop", or
"fix this design". Covers color, typography, layout, spacing, motion,
interaction, states, and UI copy. Defer to `frontend-quality` for the WCAG /
Core-Web-Vitals gate and to `mobile-design-system` for native mobile.

## Where this sits in the Walter-OS design stack

- **impeccable** (this skill) is the design-CRAFT / anti-AI-slop layer: the
  taste, principles, and vocabulary that make UI feel intentional rather than
  templated.
- Defer to **frontend-quality** for the hard a11y (WCAG 2.2 AA) and Core Web
  Vitals (LCP/INP/CLS) gate on web PRs. impeccable raises the bar;
  frontend-quality enforces the floor.
- Defer to **mobile-design-system** for native mobile (React Native, touch
  targets, gestures, iOS/Android platform conventions).
- Consult **ui-ux-pro-max** (passive reference corpus) for concrete palettes,
  font pairings, product-to-style patterns, and per-stack rules; complements
  **ui-ux-polish** (refinement checklist).

## Tooling note (Walter-OS adaptation)

Upstream ships an optional Node detector / live-preview CLI — `context.mjs`
(project-context detection), `palette.mjs` (OKLCH brand-seed generation),
`detect.mjs` (deterministic anti-pattern detector), `pin.mjs` (command
shortcuts), and a loopback `live` server — all invoked via `node
scripts/*.mjs`. Those scripts are **not bundled** in this vendored copy. This
skill is the guidance + vocabulary layer: apply the principles, reference
files, and audits below directly. To gather the project's design context
(framework, styling system, design tokens, component library, whether a
DESIGN.md exists), read those by hand (grep/Read) instead of running the
upstream detector. The `live`, `detect`, and `pin` commands are unavailable
without the un-vendored scripts — apply the matching command's design judgment
manually; the reference flows still carry the substance.

## Design guidance

The full design system lives in the `reference/` files. Load them based on what
you're working on.

### General rules

Apply these to everything:

#### Color

- Verify contrast: 4.5:1 body text, 3:1 large text/UI
- Use OKLCH for color definitions
- Tinted neutrals (0.005-0.015 chroma toward brand hue)
- Commit to a strategy: Restrained, Committed, Full-palette, or Drenched

#### Typography

- Line length 65-75 characters
- Scale ratio >= 1.25
- Max 3 font families
- Hero clamp() max <= 6rem
- Display letter-spacing floor -0.04em
- text-wrap: balance for headings, pretty for body

#### Layout

- 8px grid system
- Consistent spacing scale
- Optical alignment over mathematical
- Clear visual hierarchy

#### Motion

- ease-out exponential curves
- Respect prefers-reduced-motion
- Don't gate content visibility on transitions
- 150-300ms for UI feedback

#### Interaction

- Design all 8 states (default, hover, active, focus, disabled, loading, empty, error)
- :focus-visible for keyboard rings
- Native <dialog>, popover, anchor positioning
- Undo > confirm for destructive actions

### Copy

- Sentence case everywhere
- Active voice, second person
- Verbs for buttons
- Explain what happened + how to fix

### New projects only

For brand-new projects with no existing tokens, establish an OKLCH brand seed
by hand: pick a base hue, derive tinted neutrals and accents in OKLCH, and
commit to one of the four color strategies above. (Upstream automates this via
`palette.mjs`, which is not bundled.)

### Absolute bans

NEVER produce these AI-slop signatures:

- Side-stripe borders
- Gradient text
- Default glassmorphism
- Hero-metric template
- Identical card grids
- Uppercase eyebrow on every section
- Numbered section markers (01/02/03)
- Text overflow

### The AI slop test

Before shipping, run two passes:

**First-order (obvious):** Does it have any banned patterns above?

**Second-order (category reflex):** Does it look like the default for this category?

## Commands (guidance vocabulary)

Impeccable defines a command vocabulary. When the operator uses one of these
words, apply the matching discipline. The full per-command flow lives in
`reference/<command>.md` — load that file for the specific flow.

### Build

- `craft` - shape then build a feature end-to-end
- `shape` - plan UX/UI before building
- `init` - write PRODUCT.md + DESIGN.md + live config
- `document` - generate DESIGN.md from existing code
- `extract` - pull reusable tokens/components from code

### Evaluate

- `critique` - UX review (Nielsen heuristics, scoring, red flags)
- `audit` - accessibility/performance/responsive audit

### Refine

- `polish` - detail pass
- `bolder` - increase visual confidence
- `quieter` - reduce visual noise
- `distill` - simplify to essentials
- `harden` - errors, i18n, edge cases
- `onboard` - first-run/empty states

### Enhance

- `animate` - add purposeful motion
- `colorize` - apply color strategy
- `typeset` - typography pass
- `layout` - restructure spatial composition
- `delight` - micro-interactions
- `overdrive` - maximum visual impact

### Fix

- `clarify` - UX copy, labels, errors
- `adapt` - responsive across breakpoints
- `optimize` - performance

### Iterate

- `live` - browser variant mode (upstream-only; requires the un-vendored live
  server, so unavailable here — fall back to generating variants inline and
  letting the operator pick)

### Routing rules

When the request is ambiguous, pick the command whose reference flow best
matches intent. For `critique` and `audit`, the upstream deterministic detector
(`detect.mjs`) is not bundled — substitute careful manual evidence-gathering:
read the code, check against the bans above, and run the WCAG/CWV gate via
`frontend-quality`.

### Pin / Unpin

Upstream's `pin`/`unpin` create `/<command>` shortcuts via `pin.mjs`, which is
not bundled. Invoke commands by name instead.

## Reference library

Detailed per-command flows and deep design knowledge live in the 27 files under
`reference/` (e.g. `typeset.md`, `colorize.md`, `critique.md`, `polish.md`,
`craft.md`, `interaction-design.md`). The `codex.md` and model-specific notes
carry refuse-and-rewrite anti-pattern bans. Load the file relevant to the
command or aspect you are working on.

## Credits

Built on Anthropic's frontend-design skill (Apache-2.0, Copyright 2025
Anthropic, PBC). Extended by Paul Bakaus (Copyright 2025-2026), incorporating
typography additions from ehmo's typecraft-guide-skill. Vendored into Walter-OS
at upstream commit `b913668ba4d25b95c4a62278d3637837e9d2c6d9`. See `LICENSE`
(Apache-2.0 full text) and `NOTICE.md` (required attribution) in this directory.
