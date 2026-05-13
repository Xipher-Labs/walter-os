# Technical SEO Checklist

## P1 — Fix before publishing any content

- [ ] `sitemap.xml` exists, is submitted to Google Search Console and Bing
      Webmaster Tools, and is auto-regenerated on content publish.
- [ ] `robots.txt` exists and does not accidentally block important paths.
      Test at `https://your-domain.com/robots.txt`.
- [ ] All pages have unique `<title>` tags (50-60 chars) and `<meta description>`
      (150-160 chars). No duplicate titles across the site.
- [ ] HTTPS enforced site-wide. HTTP → HTTPS redirect in place. Check with
      `curl -I http://your-domain.com` — should return 301.
- [ ] Canonical URLs set via `<link rel="canonical">` on every page.
      Prevents duplicate content from `www` vs non-`www`, trailing slashes, etc.
- [ ] Core Web Vitals: LCP < 2.5s, INP < 200ms, CLS < 0.1. Measure with
      PageSpeed Insights (desktop + mobile).

## P2 — Fix within first sprint after launch

- [ ] Schema.org structured data on key pages: `Organization`, `Product`,
      `FAQPage`, `BreadcrumbList`. Validate with Google Rich Results Test.
- [ ] `hreflang` tags if you serve multiple languages or regions. Critical if
      you have `/en/` and `/es/` variants.
- [ ] 301 redirect hygiene: no redirect chains (A→B→C). Every removed page
      redirects to its replacement. Use `Screaming Frog` or `sitebulb` to audit.
- [ ] Image optimization: all images have `alt` text, served in WebP format,
      with explicit `width` and `height` attributes (prevents CLS).
- [ ] Internal linking: every page reachable in ≤ 3 clicks from the homepage.
      Use anchor text that reflects the target page's keyword.
- [ ] Crawl budget: `<link rel="noindex">` on thin or duplicate pages (login,
      search results, admin). Check Google Search Console Coverage report.

## P3 — Ongoing / quarterly

- [ ] Keyword research process: use Ahrefs, Semrush, or free alternatives
      (Ubersuggest, Google Keyword Planner) quarterly. Focus on intent-match
      over volume: informational → blog, navigational → homepage/docs,
      transactional → landing page.
- [ ] Backlink audit: monthly check for spammy backlinks. Disavow if needed via
      Google Search Console.
- [ ] Content freshness: update high-traffic posts annually with new data and
      re-date them. Freshness signals matter for news-adjacent queries.
- [ ] Mobile-first: Google uses mobile-first indexing. Test at
      `search.google.com/test/mobile-friendly`.
- [ ] Page experience signals: ensure pages are not blocked by interstitials on
      mobile. Avoid full-page pop-ups before content loads.

## Keyword Research Process (brief)

1. Seed keywords: brainstorm 10-20 terms your ICP would search.
2. Expand: use "People also ask", "Related searches", and a keyword tool to
   find long-tail variants (typically lower difficulty, higher intent).
3. Prioritize by: (Intent match × Search volume) / Keyword difficulty.
   Sweet spot for early-stage: volume 100-1,000/month, difficulty < 40.
4. Map keywords to pages: one primary keyword per page.
5. Track: add to Google Search Console and check ranking monthly.
