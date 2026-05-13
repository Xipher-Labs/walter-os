---
name: landing-page-fast
description: Ship a high-quality landing page in 4-8 hours using Astro + Tailwind + shadcn-style components — opinionated defaults, proven section structures, performance and SEO baked in. Use when launching a new product ([Project A], [Project B]), validating a hackathon idea, refreshing a [Company] product page, or any time the user asks to "build a landing", "make a landing page", "set up a landing for X". Output: a deployed landing page on Vercel with form capture, analytics, and proper meta. Bakes in `frontend-quality` rules.
---

# Landing Page Fast

Opinionated landing page production. Decisions made for you. Output: a
working, deployed, on-brand page in 4-8 hours, not weeks.

This skill bakes in `frontend-quality` rules (a11y, Core Web Vitals,
mobile-first) and `web-security-baseline` headers — you don't need to
think about them while you build.

## Stack (default — don't deviate without reason)

- **Astro** + **Tailwind** + **shadcn/ui-style components** + **Vercel**.
- TypeScript strict mode.
- `astro:assets` for image optimization.
- `astro:transitions` if multi-page (keep it minimal — single-page is
  faster to ship).

When to deviate:
- Need auth gates / dynamic per-user content evolving into the full app
  → use **Next.js 15 App Router** instead of Astro.
- Operator already standardized on **SvelteKit** for the project →
  use that.

Do NOT use: WordPress, Wix, raw HTML+JS without a framework, vanilla CSS
without Tailwind. Slower to ship, harder to evolve.

## Section structure (proven for B2B/SaaS technical audience)

In this order. Skip nothing without explicit reason:

1. **Hero** — headline + subhead + primary CTA + visual
2. **Social proof** — logos, stat banner, testimonial (only if real)
3. **Problem** — what's broken about status quo (you EARN credibility here)
4. **Solution** — how this fixes it (max 3 features)
5. **How it works** — 3-4 steps with diagram or screenshots
6. **Use cases** — 2-3 personas, not more
7. **Pricing** — show prices unless you really can't
8. **FAQ** — 5-8 real questions, real answers
9. **Final CTA** — restate value, repeat the action
10. **Footer** — legal, social, contact

Skip "About Us / Team" unless founder credibility is the sale (most B2B
infra products: skip; founder-led consumer products: include).

## Hero anatomy

```
[Headline: 6-10 words, value-promise]
[Subhead: 15-25 words, who/what/why]
[Primary CTA] [Secondary CTA — "see how it works"]
[Visual: screenshot, diagram, or 30s demo loop]
```

Headline rules:
- Promise an outcome, not a feature.
- Specific over abstract.
- Include primary keyword for SEO + qualification.

Examples:
- ❌ "Powerful infrastructure for modern apps"
- ✅ "Solana RPC infrastructure with sub-50ms p99"
- ❌ "Transparent platform for public tenders"
- ✅ "Join public tenders in 10 minutes"

## Project-specific defaults

### [Project A] landing
- **Primary localized market**, English at `/en` when a second locale is needed.
- Hero: dashboard screenshot with one tender card highlighted.
- Trust signals: legal references (relevant compliance badges), audit logo,
  regulatory certifications if applicable.
- Color: brand primary + neutral cream + sober accent.
- Mobile-first hard requirement: most users are on phones.
- Form capture: WhatsApp + email (WhatsApp is huge in AR for SMB).

### [Project B] landing
- **Primary localized market**, English at `/en` when a second locale is needed.
- Trust trust trust. Compliance badges, encryption visualization,
  patient-control messaging.
- Photographic style: warm, human, NOT techy/cold.
- Color: warmer palette than [Project A] (terracotta, sage, cream).
- Forms minimal — just email + "I'm a [patient | doctor | clinic]"
  selector.
- Privacy disclosure prominent (applicable local patient-rights and
  personal-data-protection law references).

### [Company] product page
- **English-first**, no localization.
- Code-heavy. Live snippets that copy-paste.
- Performance numbers everywhere ("p99 < 50ms", "100k TPS"), with
  benchmark methodology link.
- Free-tier signup CTA.
- Color: [Company] brand palette from `brand-creation` outputs.

## Hour-by-hour timeline

### Hour 1: Setup
```bash
pnpm create astro@latest <project> -- --template basics --typescript strict
cd <project>
pnpm add @astrojs/tailwind @astrojs/sitemap @astrojs/vercel
pnpm dlx astro add tailwind sitemap vercel
pnpm add -D @astrojs/check
```

Initialize Vercel project (CLI auto-detects Astro):
```bash
pnpm dlx vercel link
pnpm dlx vercel deploy --prod  # baseline blank deploy, validates pipeline
```

### Hour 2-3: Copy + structure
- Write copy in markdown FIRST (in `docs/landing-copy.md`).
- Don't design until copy is real.
- Section by section. Mobile-first viewport while building.

### Hour 4: Visual polish
- Hero visual via `nanobanana` skill OR real screenshot.
- Section illustrations consistent (one style — don't mix).
- Tailwind spacing scale strictly (no arbitrary values).

### Hour 5: Forms + analytics
- Form goes to Resend (transactional email) OR Supabase (waitlist DB)
  via Vercel Edge function.
- Plausible script (self-hosted on Walter-VM or cloud €9/mo).
- Test full flow: form → email confirmation → DB row.

### Hour 6: SEO + headers
- Meta tags (title, description, og:*, twitter:*) per page.
- Canonical URL.
- JSON-LD structured data (Organization or Product).
- Robots.txt + sitemap.xml (Astro plugin auto-generates).
- Security headers (in `vercel.json` or middleware):
  ```json
  {
    "headers": [{
      "source": "/(.*)",
      "headers": [
        { "key": "Strict-Transport-Security",
          "value": "max-age=31536000; includeSubDomains; preload" },
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "Permissions-Policy",
          "value": "camera=(), microphone=(), geolocation=()" },
        { "key": "Content-Security-Policy",
          "value": "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self' https://plausible.io" }
      ]
    }]
  }
  ```

### Hour 7: Performance pass
- Lighthouse run. ALL FOUR scores ≥ 95.
- Image sizes correct (next-gen formats, sized for viewport).
- Bundle < 150KB gzipped initial.
- LCP element preloaded.

### Hour 8: Deploy + verify
- Custom domain via Vercel (Cloudflare DNS pointed at Vercel).
- Production deploy.
- Test on real phone.
- Submit to Google Search Console.
- First analytics event landed.

## Performance budget (HARD)

| Metric | Budget | Tooling |
|---|---|---|
| Lighthouse Performance | ≥ 95 | CI |
| Lighthouse Accessibility | ≥ 95 | CI |
| Lighthouse Best Practices | ≥ 95 | CI |
| Lighthouse SEO | ≥ 95 | CI |
| LCP on 3G | < 2.5s | WebPageTest |
| INP p75 | < 200ms | RUM (Plausible if enabled, or web-vitals lib) |
| CLS | < 0.1 | RUM |
| Initial JS gzipped | < 150KB | bundlewatch |
| Time to first byte | < 200ms | Vercel edge |

If any metric fails: fix before launch. Marketing pages with bad
metrics tank conversion immediately.

## Copy rules

For technical product ([Company]):
- Lead with the noun the customer searches for ("Solana RPC").
- Stat early — give a reason to believe in the first 5 seconds.
- Show > tell: code snippet, screenshot, real numbers.
- One CTA, repeated.

For consumer / localized markets ([Project A], [Project B]):
- Plain words, short sentences.
- Lead with the question the user is asking themselves.
- Trust signals (compliance, security badges) more visible.
- Multiple CTAs OK (sign up, learn more, contact).

## Form capture

```ts
// Vercel Edge function: /api/signup.ts
export const config = { runtime: 'edge' }

export default async function handler(req: Request) {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 })

  const { email, source } = await req.json()

  // Rate limit by IP via Vercel KV / Upstash
  // Validate email with zod
  // Insert into Supabase waitlist table (RLS-protected)
  // Trigger confirmation email via Resend
  // Return 200 or specific error

  return Response.json({ ok: true })
}
```

NEVER:
- Trust client to "remember" submission state.
- Skip server-side validation.
- Forget rate limiting (one user, one bot, one DDoS — same bug).

## Analytics defaults

**Plausible** (self-hosted on Walter-VM or cloud):
```html
<script defer data-domain="[project-a].com.ar" src="https://plausible.<domain>/js/script.js"></script>
```

Track:
- Page views (default)
- Outbound clicks (`data-domain="..." data-track-outbound="true"`)
- Form submissions (custom event)
- Scroll depth on long pages (custom event, debounced)

DO NOT:
- Add Google Analytics. Heavy, privacy-hostile, EU-AAR ambiguous.
- Add session replay tools. Especially not for [Project B] (PHI risk).
- Add heatmaps. Heavy + creepy.

## Anti-patterns (don't do these)

- **Carousel hero** — nobody clicks past slide 1.
- **Too many CTAs** — "Sign up" + "Learn more" + "Watch demo" + "Read
  blog" in hero = decision paralysis.
- **Stock photos of diverse smiling people in offices** — instant "generic
  SaaS" signal.
- **Marquee of 50 tiny competitor logos** — pick 4-6 readable ones.
- **Wall of features** — pick 3 or 6, not 27.
- **Auto-playing video with sound** — instant bounce.
- **Modal popup before page loads** — instant bounce.
- **Cookie banner that blocks the page** — illegal in EU, annoying
  everywhere. Use minimal, non-blocking notification.

## When to A/B test

Don't until you have 1k+ visitors/week. Below that, the noise dominates.

When ready:
- Test ONE element at a time (headline, hero visual, CTA copy).
- Use Vercel A/B testing or Plausible's split test.
- Statistical significance before declaring a winner.

## Hard rules

- **8h budget is hard. If you're at hour 6 and still designing, ship
  hour 7's work and skip hour 8 polish.** Better imperfect live than
  perfect in your repo.
- **Every external script audited.** No "while we're at it, let's add
  Hotjar / FullStory / Drift". Each script slows the page and adds
  privacy risk.
- **No production changes without preview deploy approved.**
- **Lighthouse fail = launch blocked.**

## Integration

- `nanobanana` for hero / illustration generation.
- `brand-creation` outputs for palette, typography, voice.
- `frontend-quality` rules baked in (a11y + perf).
- `web-security-baseline` headers baked in.
- `seo-keyword-research` (deferred backlog) informs copy and meta.
- `pr-review` skill for the final review before merge.

## What this skill does NOT do

- Multi-page apps with auth, dashboards, etc. → start with Next.js.
- Blog setup. Use Astro Starlight or a Mintlify-style docs framework.
- Email marketing automation. Use ConvertKit / Beehiiv.
- Customer support chat. If you must, use Crisp (Argentine option,
  multilingual).
