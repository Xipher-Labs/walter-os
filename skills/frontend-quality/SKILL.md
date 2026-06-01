---
name: frontend-quality
description: >-
  Enforce frontend quality bar — accessibility (WCAG 2.2 AA), performance (Core
  Web Vitals: LCP/INP/CLS), semantic HTML, image optimization, bundle size,
  mobile-first, loading/empty/error states. Use this skill on any PR that
  touches React/Next.js/Astro/Svelte/Vue components, CSS/Tailwind, layout files,
  or anything in `app/`, `components/`, `pages/`, `src/`. Critical for [Project
  A] (Argentine mobile users on slow 3G/4G) and [Company] docs site (developer
  audience expects fast). Auto-triggers on `*.tsx`, `*.jsx`, `*.svelte`,
  `*.vue`, `*.astro`, `*.css`.
---

# Frontend Quality

Quality bar for any user-facing web UI. Hard requirements (a11y, perf,
mobile-first), not stylistic preferences. Reviews catch the bugs that
matter to real users — slow pages, broken keyboard nav, layouts that
shift while loading.

This skill auto-triggers on frontend-touching diffs. For a build-from-zero
landing page, use `landing-page-fast` (which includes these rules but
provides scaffolding).

## Why this matters specifically for this operator

- **[Project A]** users are Argentine SMB suppliers — many on phones, often
  on 3G/4G with intermittent connection. Slow site = users leave. WCAG
  matters because some users have low tech literacy + impaired vision.
- **[Project B]** users include patients with disabilities. WCAG isn't
  "nice to have" — it's a usability requirement.
- **[Company] docs** is read by sophisticated devs who instantly bounce on
  slow or broken-keyboard sites.

## Accessibility (WCAG 2.2 AA — required)

### Keyboard

- **Every interactive element reachable by Tab**. Buttons, links, form
  fields, custom controls. Run a manual Tab-through; if any control is
  skipped, BLOCKER.
- **Focus visible**. The `:focus-visible` outline must be obvious. Don't
  set `outline: none` without an alternative.
- **Logical tab order**. Reading order matches DOM order; avoid `tabindex`
  values >0 (they break the natural flow).
- **Skip link**. First focusable element on every page is "Skip to main
  content".
- **Escape closes modals**. Trap focus inside modal until closed.

### Semantic HTML

- **`<button>` for actions, `<a>` for navigation**. Never `<div onClick>`
  for either.
- **Headings hierarchical**: one `<h1>` per page; `<h2>` ... `<h6>` don't
  skip levels.
- **Landmarks**: `<header>`, `<nav>`, `<main>`, `<footer>`. ARIA roles
  only when no semantic element fits.
- **Lists are `<ul>`/`<ol>`**. Don't fake lists with `<div>`.
- **Form controls have `<label>`**. `for` attribute matches `id`.

### Color and contrast

- **WCAG AA contrast minimum**: 4.5:1 for body text, 3:1 for large text
  (18pt+ or 14pt+ bold), 3:1 for UI components and graphics.
- **Color is not the only indicator**: error states show icon + text +
  color, not just red border.
- **Tested with simulated color blindness**. Use Stark, axe DevTools,
  or browser devtools color-vision simulators.

### Forms

- **Every input has a visible label**. Placeholder is NOT a label.
- **Error messages are programmatically associated** via `aria-describedby`.
- **Required fields marked**. Both visually (`*` or "required") AND
  programmatically (`aria-required="true"` or `required`).
- **Validation errors don't disappear on focus**. Persist until corrected
  or dismissed.
- **Success states confirmed**. After submit, screen-reader users know it
  worked.

### Images and media

- **`alt` attribute on every `<img>`**. Empty (`alt=""`) for decorative;
  descriptive for content. Generated AI images: describe what's actually
  in the image, not the prompt.
- **Captions/transcripts** for video/audio.
- **No autoplay with sound**.
- **Animations respect `prefers-reduced-motion`**:
  ```css
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: 0.01ms !important;
      transition-duration: 0.01ms !important;
    }
  }
  ```

### Tooling

- **`@axe-core/react`** in dev mode — logs a11y issues to console.
- **`eslint-plugin-jsx-a11y`** — catches at build time.
- **Manual screen reader test** before launch: VoiceOver (Mac), NVDA
  (Windows), TalkBack (Android).
- **Lighthouse a11y score ≥ 95** in CI.

## Performance — Core Web Vitals

The 3 metrics Google ranks on. Pass ALL THREE to be in "Good":

### LCP (Largest Contentful Paint) — load speed

Target: **< 2.5s on 3G**. Real-world for [Project A] is more aggressive
since Argentine mobile networks are slower than median.

How:
- **Preload the LCP image**: `<link rel="preload" as="image" href="...">`.
- **No render-blocking resources**: defer non-critical JS, inline
  critical CSS.
- **Self-host fonts** with `font-display: swap` or use system font stack.
- **CDN for static assets**: Vercel, Cloudflare R2, Bunny.net.
- **HTTP/2 or HTTP/3**: Vercel/Cloudflare default.
- **Compress images**: WebP/AVIF, sized for viewport.
- **Optimize the hero image specifically**: it's almost always LCP.

### INP (Interaction to Next Paint) — responsiveness

Target: **< 200ms p75**. Replaced FID in 2024.

How:
- **No long tasks > 50ms** on the main thread during interaction.
- **Defer hydration** (Astro islands, Next.js streaming, qwik).
- **Web Workers** for heavy compute.
- **Debounce/throttle** input handlers.
- **Avoid `dangerouslySetInnerHTML` with large strings** — parsing blocks.
- **`useMemo`/`memo` only where measured**, not preemptively.

### CLS (Cumulative Layout Shift) — visual stability

Target: **< 0.1**.

How:
- **Image and video tags have `width` + `height`** (browser reserves space).
- **Reserve space for ads/embeds** with min-height.
- **Don't insert content above existing**: notification banners go below
  fold or push down via transform, not by inserting in DOM above.
- **Web fonts**: use `font-display: swap` + `size-adjust` to match
  metrics, OR `font-display: optional` if you can.
- **Skeleton screens** sized to match real content.

### Bundle size

- **Initial JS budget: < 150KB gzipped** for landing pages, < 250KB for
  app shells.
- **Code-split by route** (Next.js, Astro, SvelteKit do this by default).
- **Dynamic imports for heavy non-critical deps** (charts, editors).
- **Audit deps**: `bundle-analyzer` or `next-bundle-analyzer`. Drop the
  10MB UI library you imported one component from.
- **Tree-shaking working**: import only what you need
  (`import { thing } from 'lib'` not `import lib from 'lib'`).

### Loading patterns

- **Preconnect** to required origins: `<link rel="preconnect" href="...">`.
- **Prefetch** likely-next pages on hover/focus (Next.js does this).
- **Lazy-load images below fold**: `loading="lazy"`.
- **Lazy-load iframes**: `loading="lazy"`.
- **Service Worker for offline-first** (where it makes sense — [Project A]
  benefits, marketing pages don't).

## States — every component handles all five

For any data-driven UI, BLOCKER if any state is unhandled:

1. **Loading** — skeleton or spinner. NOT blank screen. NOT layout shift.
2. **Empty** — first-time, no-data state. With CTA to populate.
3. **Error** — clear message, retry button, no stack trace to user.
   Logged to Sentry.
4. **Partial / stale** — when data is from cache or partial fetch.
5. **Success** — the happy path.

Example for a list:
```tsx
if (isLoading) return <ListSkeleton />
if (error)     return <ErrorState onRetry={refetch} />
if (data.length === 0) return <EmptyState cta={...} />
return <List items={data} />
```

If your component has only the success state shown to me in the diff,
ask: where do the other 4 live?

## Mobile-first

- **Design for 360px wide first**, scale up.
- **Touch targets ≥ 44×44px** (Apple HIG) or 48×48px (Material).
- **No hover-only interactions**: anything available on hover also has
  a focus/touch path.
- **Test on real device or chrome devtools throttled**: 3G network,
  4× CPU slowdown.
- **Forms work without zoom**: input `font-size: 16px+` (otherwise iOS
  zooms on focus).

## Tooling reference

CI / pre-merge:
- **Lighthouse CI** with budgets per metric.
- **`@axe-core/cli`** or Lighthouse a11y subset.
- **`bundlewatch`** to fail PRs that grow bundle beyond budget.
- **Visual regression**: Chromatic (Storybook), Percy, or Playwright
  screenshots checked in.

Local:
- **Chrome DevTools** Performance + Lighthouse panels.
- **`unlighthouse`** for full-site audit.
- **`@unjs/check-vitals`** for one-shot Web Vitals.

## Output format

```
**[BLOCKING|WARN|NIT] [FE-N] <one-line>**

Where: `path/to/Component.tsx:42-58`
Category: <a11y | perf | states | mobile | semantic>
Impact: <which user / scenario / metric>
Fix: <specific change, code if it fits>
Verify: <how to confirm — Lighthouse run / manual test / etc.>
```

Severity:
- **BLOCKING**: WCAG AA violation, broken core flow, Web Vitals failing
  in "Poor" range. Must fix.
- **WARN**: best-practice gap, performance regression that's not yet
  user-visible.
- **NIT**: opportunity for improvement (smaller bundle, better skeleton).

## Hard rules

- **No `<div onClick>` for buttons.** Always.
- **No images without `alt`.** Always.
- **No layout shift from real content.** Always reserve space.
- **No autoplay with sound.** Always.
- **`prefers-reduced-motion` respected.** Always.

## What this skill does NOT cover

- Backend (use `web-security-baseline`).
- DB schema / queries (use `data-migration-safety`).
- Brand identity / visual design (use `brand-creation`).
- New landing-page construction (use `landing-page-fast` which
  scaffolds).

## References

- WCAG 2.2 quick reference
- web.dev Core Web Vitals docs
- web.dev Performance learning path
- Inclusive Components by Heydon Pickering
- The A11y Project checklist
