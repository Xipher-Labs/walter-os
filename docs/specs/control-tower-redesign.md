# Control Tower UX/UI redesign

- Status: in progress
- Issue: #181
- ADR: docs/decisions/0008-control-tower-stack.md (Next.js 16 stack)
- Methodology: impeccable (craft) + frontend-quality (WCAG 2.2 AA / CWV) + ui-ux-polish

## Problem

The Control Tower is the operator's night-time cockpit for the Walter Council
multi-agent system. The current UI is functional but generic: a light-default
theme that flips via `prefers-color-scheme`, four-plus stacked rows that force
scrolling to see all surfaces, ad-hoc per-component color maps, uppercase
eyebrow headings on every section, and a `border-left` accent stripe on the
timeline. It reads like default AI output, not an intentional operations
console. The operator runs it at night and wants every signal visible at a
glance, with status as the primary visual language.

## Current architecture survey

- Next.js 16 (App Router, React 19, standalone output), Tailwind v4 via
  `@tailwindcss/postcss`, Geist Sans + Geist Mono. No shadcn/ui present; no
  `components/ui/` primitives; `app/globals.css` is the minimal create-next-app
  default (two CSS vars + a `prefers-color-scheme` block).
- Pages (`app/`): `page.tsx` (overview), `council/`, `ideation/`, `history/`,
  `content/`, `login/`. Each page re-declares its own top nav inline.
- Surfaces (`app/components/`): `AgentStatusBoard` (SSE, idle/working/blocked),
  `DecisionTimeline` (REST 30s, tier info/warn/critical/panic),
  `CostDashboard` (REST, per-agent spend + budget bar), `HAStatus`
  (REST 60s, primary/standby health), `AlertFeed` (REST 30s, tiers),
  `ModeIndicator` (REST 60s, consensus toggle), `MetricsDashboard` +
  `ContentDashboard` (Grafana iframes), `CouncilChat` (3-phase deliberation),
  `VersionBadge` (server, version env).
- Data routes (no changes): `/api/sse`, `/api/timeline`, `/api/spend`,
  `/api/ha-status`, `/api/alerts`, `/api/mode`, `/api/consensus-status`,
  plus `/api/history`, `/api/council-chat/*`, `/api/health`, `/api/login`,
  `/api/ideation/spin-spec`.
- Status concept is duplicated: three separate inline tier/state color maps
  (`AgentStatusBoard`, `DecisionTimeline`/`AlertFeed`, `HAStatus`) with no
  shared primitive.
- Tests: Vitest unit suite (`tests/unit/`, run via `pnpm test:unit`) plus
  Playwright E2E smoke (`tests/e2e/`, run via `pnpm test`). Two static-analysis
  unit tests assert source invariants (no `/3` denominator in `ModeIndicator`,
  no `auth_token` in `MetricsDashboard` URL) — the redesign must preserve both.

## Decisions

| ID  | Decision | Rationale |
|-----|----------|-----------|
| D-1 | Dark-mode-first: `.dark` is the default applied class on `<html>` in `layout.tsx`; light is opt-out. Tailwind v4 `dark:` switched from media to class via `@custom-variant`. | Operator runs it at night; dark is the primary experience, not a fallback. |
| D-2 | Token layer in `globals.css`: 4px-base spacing scale, fixed rem type ramp, and semantic STATUS tokens (idle/working/blocked/ok/warn/critical/info) in OKLCH for both themes, plus a committed teal accent and brand-tinted neutrals. | impeccable color-commitment + tinted-neutrals; one source of truth for status. |
| D-3 | Replace stacked rows with a dense responsive overview grid: all surfaces visible at once on desktop (>=1280px), 2-col on tablet (768-1279px). Card weight varies by information priority (no identical grid). | impeccable layout: hierarchy through space and span, not repetition. |
| D-4 | Single `StatusDot` + `StatusBadge` primitive consuming D-2 tokens, reused across Council agent state, HA service health, and Alert/Timeline tiers. | One status vocabulary; kills the three duplicate color maps. |
| D-5 | Every async surface uses a shared `AsyncSurface` wrapper providing the loading / empty / error+retry triad (skeleton, empty-state, retry). | impeccable interaction states; consistent arrival behavior. |
| D-6 | Responsive floor is tablet (768px). No dedicated phone layout. | Cockpit is a desk tool; the brief sets tablet as the floor. |
| D-7 | No backend changes. Consume the existing SSE + REST routes exactly as-is. | Redesign is presentation-only; API contracts are frozen. |
| D-8 | Verify status-token contrast meets WCAG 2.2 AA in dark mode (table below). | frontend-quality floor; status must be legible and not color-only. |

## Status token contrast (dark mode, foreground on surface oklch(0.21 0.012 220) ~= #2b2f33)

- Ratios computed against the elevated card surface used behind badges.
- Targets: >= 4.5:1 for badge text, >= 3:1 for the standalone dot/UI mark.

| Token | Role | Foreground hex (approx) | Contrast vs card | Pass |
|-------|------|-------------------------|------------------|------|
| status-idle | idle agent | #9aa4ad | 4.9:1 | AA text |
| status-working | working agent | #4ed8b0 | 7.4:1 | AA text |
| status-blocked | blocked agent | #f0b75a | 7.8:1 | AA text |
| status-ok | healthy service | #4ed8b0 | 7.4:1 | AA text |
| status-warn | warn tier | #f0b75a | 7.8:1 | AA text |
| status-critical | critical tier | #f87171 | 5.2:1 | AA text |
| status-info | info tier | #9aa4ad | 4.9:1 | AA text |
| accent | links / primary | #38c2c9 | 6.3:1 | AA text |

Dots also carry a shape/label (not color alone): every status is paired with a
text label or an aria-label so color is never the sole signal (WCAG 1.4.1).

## Acceptance criteria

- AC-1: `globals.css` defines the token foundation (spacing scale, type ramp,
  semantic status tokens in both themes, teal accent, tinted neutrals) and
  `layout.tsx` applies `.dark` by default on `<html>`.
- AC-2: `StatusDot`, `StatusBadge`, and `AsyncSurface` primitives exist, are
  token-driven, and have unit tests mapping each status to its token + label.
- AC-3: `page.tsx` renders a responsive overview grid: all surfaces visible at
  once on desktop (>=1280px), 2-col on tablet; card weight varies by priority.
- AC-4: Each surface (agent board, HA, cost, alerts, timeline, mode) is
  re-skinned to the dark token system and the shared status language, with a
  loading + empty + error state via `AsyncSurface` where it fetches.
- AC-5: A11y sweep: keyboard nav works, focus rings are visible via
  `:focus-visible`, `prefers-reduced-motion` is respected, and no status relies
  on color alone (label or aria-label present).
- AC-6: Verification: `pnpm build`, `pnpm lint`, `pnpm typecheck`, and
  `pnpm test:unit` pass; the Playwright smoke contract (h1 "Walter Council",
  6 agent cards, nav links, page loads) still holds.

## Out of scope

- No backend / API route changes (D-7). No new data sources or endpoints.
- No phone-specific layout (D-6).
- No change to auth, SSE, or Grafana embedding logic.
- No new runtime dependencies; no shadcn/ui adoption (the app has none today).
- Council Chat deliberation logic is untouched; only its surface is re-themed.
- Recharts is already a dependency; no charting library swap.

## Anti-AI-slop guardrails (impeccable absolute bans)

- No `border-left/right` accent stripes (replace the timeline stripe with a
  full hairline + dot).
- No gradient text, no default glassmorphism, no hero-metric template.
- No identical card grid: overview cards span by priority.
- No uppercase eyebrow on every section heading; sentence-case section titles.
- No numbered section markers.
