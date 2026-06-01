# UX Skills Adoption — impeccable + ui-ux-pro-max

- Status: adopted
- Date: 2026-05-31
- Closes: #220, #221

## Problem

- Walter-OS has design coverage (`ui-ux-polish`, `web-design-guidelines`,
  `mobile-design-system`, `frontend-quality`, `ios-glass-ui`) but two gaps
  remained.
- No explicit anti-AI-slop / design-craft authority with opinionated taste and
  a command vocabulary ("make it pop", "feels generic", "more premium").
- No structured, queryable corpus of concrete design data (palettes, font
  pairings, product-to-style mappings, per-framework UI rules) to ground design
  decisions in prior art instead of ad-hoc invention.

## Candidates

- impeccable — `pbakaus/impeccable`, Apache-2.0. An ACTIVE design-craft system:
  general rules, the AI-slop test, absolute bans, a command vocabulary, copy
  rules, and a ~347KB / 27-file `reference/` library. Built on Anthropic's
  frontend-design skill.
- ui-ux-pro-max — `nextlevelbuilder/ui-ux-pro-max-skill`, MIT. A data-driven
  design corpus: 11 structured cross-cutting CSVs plus 16 per-stack CSVs,
  originally fronted by a Python search CLI.

## Head-to-head

- Role overlap is minimal. impeccable is judgment and vocabulary; ui-ux-pro-max
  is lookup data. They are complementary layers, not competitors.
- Activation differs. impeccable is an ACTIVE craft skill the agent applies
  while designing/reviewing. ui-ux-pro-max is a PASSIVE corpus the agent greps
  when it needs concrete prior art.
- Both upstreams ship executable tooling we do not need (impeccable a Node CLI,
  ui-ux-pro-max a Python CLI). Neither is required for the value we want, so
  neither is vendored.

## Decision: adopt BOTH, in DISTINCT roles

- impeccable = the design-CRAFT / anti-AI-slop authority (active skill).
- ui-ux-pro-max = a PASSIVE design-system reference corpus (lookup data).
- Neither replaces `frontend-quality` (the WCAG 2.2 AA + Core Web Vitals gate)
  nor `mobile-design-system` (native mobile). Intended flow:
  - ui-ux-pro-max grounds the choice in prior art ->
  - impeccable applies taste and the working method ->
  - ui-ux-polish refines to a professional standard ->
  - frontend-quality gates a11y + performance.

## Pins

- impeccable: `b913668ba4d25b95c4a62278d3637837e9d2c6d9` (Apache-2.0).
- ui-ux-pro-max: `b7e3af80f6e331f6fb456667b82b12cade7c9d35` (MIT).
- Both recorded in the audit pinning manifest
  `skills/daily-supply-chain-audit/assets/pinned-refs.toml`. This manifest
  records the vendored upstream SHAs as provenance documentation; it is NOT
  enforced by `check-pinning.py`. `check-pinning.py` only parses a Claude Code
  `settings.json` and reports `mcpServers` entries that are not pinned to a
  version — it never reads `pinned-refs.toml` or any skill. So skills-drift
  detection is manual today. Skills-aware pin enforcement (teaching the audit
  to read `pinned-refs.toml` and flag vendored-skill drift) is future work
  tracked in issue #255. The manifest did not previously exist on main; it is
  created here, seeded with these two skills.

## Adaptations on vendoring

- impeccable — replaced upstream frontmatter with the Walter-OS schema
  (name/description/license). Neutralized the `## Setup` step and the
  `live`/`detect`/`pin` commands that shell out to un-vendored `node
  scripts/*.mjs` (context.mjs, palette.mjs, detect.mjs, pin.mjs), replacing
  them with a note that the optional detector/live-preview CLI is not bundled
  and this is the guidance + vocabulary layer. Kept all design guidance, the
  AI-slop test, absolute bans, the command vocabulary, copy rules, and the full
  27-file `reference/` library (adapted from `skill/SKILL.src.md` and
  `skill/reference/*.md`). Carried upstream `LICENSE` and `NOTICE.md`
  (Apache-2.0 requires preserving NOTICE).
- ui-ux-pro-max — wrote a NEW Walter-OS-authored `SKILL.md` framing it as a
  passive corpus consulted by grep/Read; did NOT copy upstream's SKILL.md
  (which hardcodes `python3 search.py`). Vendored 11 structured top-level CSVs
  (app-interface, charts, colors, icons, landing, products, react-performance,
  styles, typography, ui-reasoning, ux-guidelines), excluding the 745KB
  `google-fonts.csv`; all 16 per-stack CSVs; and `quick-reference.md`. Upstream
  `draft.csv` and `design.csv` were deliberately NOT kept: both are
  unstructured (no CSV header), upstream excludes `draft.csv` from search, and
  both contained non-English (Chinese) content — they are not cleanly
  greppable data and violate the English-only repo rule. Stray Chinese keyword
  cells in `icons.csv` and `styles.csv` were translated to English; the
  `quick-reference.md` activation section was translated to English; and
  `data/stacks/threejs.csv` was normalized by adding the missing `No` column so
  it matches the shared per-stack schema documented in `SKILL.md`. A full-tree
  scan confirms no CJK remains. Did NOT vendor any Python
  (`search.py`/`core.py`/`design_system.py`/`_sync_all.py`) or the CLI. Carried
  upstream `LICENSE` (MIT).

## Security verdict

- Both skills were security-vetted and APPROVED prior to vendoring: clean — no
  data exfiltration, no telemetry, no install hooks. Licenses confirmed
  Apache-2.0 (impeccable) and MIT (ui-ux-pro-max). The full vetting scratch
  reports were temporary local artifacts at adoption time and are not repository
  evidence; this spec records the durable summarized verdict.
- The vet reports placed all risk surface (impeccable: a version phone-home,
  loopback live server, credential forwarding, CSP patching; ui-ux-pro-max: the
  Python search engine) entirely in the executable tooling that is EXCLUDED
  from this vendoring. What is vendored is markdown guidance, CSV data, and
  license/notice text only — no executable third-party code. Vendored files
  were re-scanned for null/zero-width/bidi bytes and prompt-injection patterns:
  clean.

## Acceptance criteria

- impeccable vendored under `skills/impeccable/` with adapted SKILL.md, the
  27-file reference library, LICENSE, and NOTICE.md.
- ui-ux-pro-max vendored under `skills/ui-ux-pro-max/` with a new SKILL.md, the
  11 + 16 CSV corpus (no google-fonts, no Python), quick-reference, and LICENSE.
- Both indexed in `skills/INDEX.md` under Product and Design.
- Both pinned to their upstream SHAs in the audit pinning manifest.
- Both attributed in the repo-root `NOTICE`.
- No executable third-party code introduced.

## Non-goals

- Wiring either skill into context-level `SKILLS.md` auto-trigger tables (can
  follow once usage settles).
- Vendoring the upstream Node or Python tooling.
- Tracking upstream automatically; updates are manual, re-vetted, re-pinned.
