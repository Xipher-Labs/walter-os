---
name: ui-ux-pro-max
description: Passive design-system reference corpus — look up color palettes, font pairings, product-to-style mappings, named visual styles, chart-type selection, icon libraries, landing-page patterns, app-interface and UX guidelines, React performance rules, UI reasoning, and per-stack UI rules by grep/Read over the vendored CSVs. Triggers on "what palette for a fintech app", "font pairing for healthcare", "chart type for time-series", "Next.js UI conventions", "landing page section order". NOT a review gate (use frontend-quality) and NOT the design-craft authority (use impeccable) — this is lookup data only.
license: MIT
---

# UI/UX Pro Max — Design-System Reference Corpus

This skill is a **passive reference corpus**: a body of structured design data
the agent consults by grep/Read over vendored CSV files. It is not a reviewer,
not a quality gate, and not a second design opinion. It is lookup data.

## What this is (and is not)

- **IS**: a queryable corpus of palettes, font pairings, product-to-style
  patterns, named visual styles, chart-type selection, icon libraries,
  landing-page patterns, app-interface and UX guidelines, React performance
  rules, UI reasoning, and per-framework UI rules. You grep it to ground
  design decisions in concrete prior art.
- **IS NOT** a review or quality gate — that is `frontend-quality`
  (WCAG 2.2 AA, Core Web Vitals).
- **IS NOT** the design-craft authority — that is `impeccable` (taste,
  anti-AI-slop principles, the working method).
- Think of it as the data layer that `impeccable` and `ui-ux-polish` consult
  while applying judgment.

## Tooling note (Walter-OS adaptation)

Upstream ships a Python CLI (`search.py` / `core.py` / `design_system.py`) and
a sync script (`_sync_all.py`). **None of the Python is vendored.** You consult
this corpus with plain `grep` and `Read` over the CSVs — no `python3
search.py`, no runtime dependency. The data is intentionally CSV so it is
greppable.

These CSVs are byte-exact upstream copies pinned to the commit below. Some rows
contain code-example fields with embedded commas and unescaped double quotes
(e.g. an HTML/JSX snippet), so a strict RFC-4180 CSV parser may reject or
mis-column them. That is expected: this corpus is meant for line-oriented
`grep`/`Read` lookup, NOT for parsing as structured CSV. Do not "repair" the
quoting — it would diverge from the pinned upstream source.

## The corpus

### `data/*.csv` — cross-cutting design data (11 files)

Every CSV has a header row; the column names below are the **real** headers
(line 1 of each file).

- `products.csv` — product type -> style and palette recommendations.
  Columns: `No,Product Type,Keywords,Primary Style Recommendation,Secondary Styles,Landing Page Pattern,Dashboard Style (if applicable),Color Palette Focus,Key Considerations`
- `colors.csv` — named palettes as full token sets (primary/secondary/accent,
  on-colors, background, card, muted, border, destructive, ring) per product
  type. Columns: `No,Product Type,Primary,On Primary,Secondary,On Secondary,Accent,On Accent,Background,Foreground,Card,Card Foreground,Muted,Muted Foreground,Border,Destructive,On Destructive,Ring,Notes`
- `typography.csv` — font pairings (heading + body) with mood, Google Fonts
  URL, CSS import, and Tailwind config. This is the **font-pairing** file.
  Columns: `No,Font Pairing Name,Category,Heading Font,Body Font,Mood/Style Keywords,Best For,Google Fonts URL,CSS Import,Tailwind Config,Notes`
- `styles.csv` — named visual styles with colors, effects, best-for, light/dark
  support, accessibility, framework compatibility, and AI-prompt keywords.
  Columns: `No,Style Category,Type,Keywords,Primary Colors,Secondary Colors,Effects & Animation,Best For,Do Not Use For,Light Mode ✓,Dark Mode ✓,Performance,Accessibility,Mobile-Friendly,Conversion-Focused,Framework Compatibility,Era/Origin,Complexity,AI Prompt Keywords,CSS/Technical Keywords,Implementation Checklist,Design System Variables`
- `charts.csv` — chart-type selection by data type, with secondary options,
  volume thresholds, color/a11y guidance, and library recommendations.
  Columns: `No,Data Type,Keywords,Best Chart Type,Secondary Options,When to Use,When NOT to Use,Data Volume Threshold,Color Guidance,Accessibility Grade,Accessibility Notes,A11y Fallback,Library Recommendation,Interactive Level`
- `icons.csv` — icon lookup by category/name with library, import code, and
  recommended usage. Columns: `No,Category,Icon Name,Keywords,Library,Import Code,Usage,Best For,Style`
- `landing.csv` — landing-page patterns: section order, CTA placement, color
  strategy, recommended effects, conversion notes.
  Columns: `No,Pattern Name,Keywords,Section Order,Primary CTA Placement,Color Strategy,Recommended Effects,Conversion Optimization`
- `app-interface.csv` — application-interface issues with do/don't and good/bad
  code examples, by severity. Columns: `No,Category,Issue,Keywords,Platform,Description,Do,Don't,Code Example Good,Code Example Bad,Severity`
- `ux-guidelines.csv` — UX rules with do/don't, good/bad code examples, and
  severity. Columns: `No,Category,Issue,Platform,Description,Do,Don't,Code Example Good,Code Example Bad,Severity`
- `react-performance.csv` — React performance issues with do/don't and
  good/bad code examples, by severity. Columns: `No,Category,Issue,Keywords,Platform,Description,Do,Don't,Code Example Good,Code Example Bad,Severity`
- `ui-reasoning.csv` — higher-level UI decision rules: recommended pattern,
  style/color/typography priorities, key effects, decision rules, anti-patterns.
  Columns: `No,UI_Category,Recommended_Pattern,Style_Priority,Color_Mood,Typography_Mood,Key_Effects,Decision_Rules,Anti_Patterns,Severity`

Note: upstream's large `google-fonts.csv` (~745KB) is intentionally **not**
vendored — use `typography.csv` for curated font pairings.

### `data/stacks/*.csv` — per-framework UI rules (16 files)

`angular`, `astro`, `flutter`, `html-tailwind`, `jetpack-compose`, `laravel`,
`nextjs`, `nuxt-ui`, `nuxtjs`, `react`, `react-native`, `shadcn`, `svelte`,
`swiftui`, `threejs`, `vue`.

Each per-stack file shares the same schema — framework-specific guidelines with
rationale and good/bad code examples. Columns: `No,Category,Guideline,Description,Do,Don't,Code Good,Code Bad,Severity,Docs URL`.

### `reference/quick-reference.md`

A compact, self-contained human-readable digest (the most useful single file
when you want orientation before diving into the CSVs).

## How to use it (concrete examples)

Look up the recommended styles and landing pattern for a product type
(matches the `Product Type` / `Keywords` columns of `products.csv`):

```bash
grep -i fintech skills/ui-ux-pro-max/data/products.csv
```

Pull a full palette token set for a product type from `colors.csv`:

```bash
grep -i "healthcare\|saas\|dashboard" skills/ui-ux-pro-max/data/colors.csv
```

Find a font pairing by mood or use case (`typography.csv` is the pairing
file — `Font Pairing Name` / `Mood/Style Keywords` / `Best For`):

```bash
grep -i "serif\|editorial\|elegant" skills/ui-ux-pro-max/data/typography.csv
```

Pick a chart type for a given data type from `charts.csv`:

```bash
grep -i "time-series\|comparison\|distribution" skills/ui-ux-pro-max/data/charts.csv
```

Look up a landing-page section order / CTA placement from `landing.csv`:

```bash
grep -i "hero\|pricing\|testimonial" skills/ui-ux-pro-max/data/landing.csv
```

Pull the UI conventions for a specific framework (per-stack files share the
`Category` / `Guideline` / `Severity` schema):

```bash
grep -i "form\|validation" skills/ui-ux-pro-max/data/stacks/nextjs.csv
```

Find high-severity UX rules with good/bad code examples (`Severity` column):

```bash
grep -i "critical\|high" skills/ui-ux-pro-max/data/ux-guidelines.csv
```

Look up React performance pitfalls from `react-performance.csv`:

```bash
grep -i "re-render\|memo\|effect" skills/ui-ux-pro-max/data/react-performance.csv
```

## Workflow positioning

1. Consult this corpus to ground a design choice in concrete prior art
   (palette, pairing, style, per-stack rule).
2. Apply taste and the working method via `impeccable`.
3. Refine to a professional standard via `ui-ux-polish`.
4. Gate the result on a11y + performance via `frontend-quality`; for native
   mobile, use `mobile-design-system`.

## Provenance

Vendored from `nextlevelbuilder/ui-ux-pro-max-skill` at commit
`b7e3af80f6e331f6fb456667b82b12cade7c9d35` (MIT, Copyright (c) 2024 Next Level
Builder). Only the CSV data, the quick-reference digest, and the LICENSE are
vendored; the upstream Python CLI is deliberately excluded. See `LICENSE` in
this directory.
