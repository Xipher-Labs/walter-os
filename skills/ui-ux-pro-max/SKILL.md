---
name: ui-ux-pro-max
description: Passive design-system reference corpus — look up color palettes, font pairings, product-to-style mappings, named visual styles, component/pattern/layout/spacing/chart conventions, design-system presets, anti-patterns, WCAG-cited UX guidelines, and per-stack UI rules by grep/Read over the vendored CSVs. Triggers on "what palette for a fintech app", "font pairing for healthcare", "design patterns for developer tools", "Next.js UI conventions", "look up a design system". NOT a review gate (use frontend-quality) and NOT the design-craft authority (use impeccable) — this is lookup data only.
license: MIT
---

# UI/UX Pro Max — Design-System Reference Corpus

This skill is a **passive reference corpus**: a body of structured design data
the agent consults by grep/Read over vendored CSV files. It is not a reviewer,
not a quality gate, and not a second design opinion. It is lookup data.

## What this is (and is not)

- **IS**: a queryable corpus of palettes, font pairings, product-to-style
  patterns, named visual styles, components/patterns/layouts, anti-patterns,
  WCAG-cited UX guidelines, and per-framework UI rules. You grep it to ground
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

## The corpus

### `data/*.csv` — cross-cutting design data (13 files)

- `products.csv` — product type -> recommended styles, color approach,
  typography, key features, UX priorities, reference apps. Columns:
  `id,product_type,category,recommended_styles,color_approach,typography,key_features,ux_priorities,reference_apps`
- `colors.csv` — named palettes with hex sets, mood, use cases, pairing notes,
  accessibility. Columns: `id,name,type,hex_codes,mood,use_cases,pairing_notes,accessibility`
- `fonts.csv` — font families with pairings, use cases, weights, fallback,
  performance notes. Columns: `id,name,category,pairing,use_cases,weights,fallback,performance_notes`
- `typography.csv` — type-scale presets. Columns:
  `id,scale_name,base_size,scale_ratio,headings,body,use_case`
- `styles.csv` — named visual styles with characteristics, best-for, color
  tendency, examples.
- `components.csv` — component variants, states, accessibility, best practices.
- `patterns.csv` — UX/interaction patterns with when-to-use and implementation.
- `layouts.csv` — layout structures with responsive notes and examples.
- `spacing.csv` — spacing-scale presets.
- `charts.csv` — chart-type selection by data type, with libraries and a11y.
- `design-systems.csv` — named design-system presets (principles, color, type,
  components, spacing).
- `anti-patterns.csv` — what to avoid, why, what to do instead, severity.
- `ux-guidelines.csv` — UX rules with priority, rationale, implementation, and
  `wcag_reference`.

Note: upstream's large `google-fonts.csv` (~745KB) is intentionally **not**
vendored — use `fonts.csv` for curated pairings.

### `data/stacks/*.csv` — per-framework UI rules (16 files)

`angular`, `astro`, `flutter`, `htmx`, `laravel`, `nextjs`, `nuxt`, `react`,
`remix`, `solid`, `svelte`, `sveltekit`, `swiftui`, `tanstack`, `vue`, `wxt`.
Each carries framework-specific UI/UX conventions with rationale and examples.

### `reference/quick-reference.md`

A compact, self-contained human-readable digest (the most useful single file
when you want orientation before diving into the CSVs).

## How to use it (concrete examples)

Look up the recommended styles and palette approach for a product type:

```bash
grep -i fintech skills/ui-ux-pro-max/data/products.csv
```

Find palettes by mood / use case:

```bash
grep -i "healthcare\|clinical\|calm" skills/ui-ux-pro-max/data/colors.csv
```

Pull the UI conventions for a specific framework:

```bash
grep -i "form\|validation" skills/ui-ux-pro-max/data/stacks/nextjs.csv
```

Find high-priority, WCAG-cited UX rules:

```bash
grep -i "critical\|high" skills/ui-ux-pro-max/data/ux-guidelines.csv
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
