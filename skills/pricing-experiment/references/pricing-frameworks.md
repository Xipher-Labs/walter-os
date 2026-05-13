# Pricing Frameworks Reference

Three foundational frameworks used by `pricing-experiment`. Descriptions
are original summaries of general industry frameworks.

---

## 1. Van Westendorp Price Sensitivity Meter

Developed by Dutch economist Peter van Westendorp. Four questions asked
of target customers to identify an acceptable price range:

1. **Too cheap** — "At what price would this product be so cheap that you'd
   question the quality?"
2. **Cheap** — "At what price would this product be a bargain?"
3. **Expensive** — "At what price would this product start to feel expensive?"
4. **Too expensive** — "At what price would this product be too expensive
   to consider?"

**How to use the output:**
- Plot the four cumulative frequency curves.
- The intersection of "too cheap" and "expensive" gives the Acceptable Price
  Range (APR).
- The intersection of "cheap" and "too expensive" gives the Optimal Price Point (OPP).
- Set Starter at or below OPP; set Pro near the top of APR.

**Practical shortcut (no chart required):**
Ask the four questions across 5–10 interviews and take the median answer
for each. This gives a directional range without statistical rigor.

---

## 2. Anchor Pricing (Decoy Effect)

A well-designed pricing page uses cognitive anchors to make the middle
tier feel like the obvious choice.

**Core mechanics:**

- **Left anchor (Starter)**: priced low, limited features. Makes Pro look
  reasonable by comparison. Should NOT be a trap — genuine value for early
  or small users.
- **Middle tier (Pro)**: the target. Features intentionally chosen to be
  just above what most buyers need from Starter. Price set at 3–5x Starter.
- **Right anchor (Scale)**: priced high (often "contact us"). Makes Pro
  look affordable. The Scale tier also captures the high-end segment.

**Common mistakes:**
- Making Starter so limited it frustrates trial users (churn risk).
- Pricing Pro too close to Starter (no upgrade motivation).
- No Enterprise tier when large companies are in the ICP (they expect it).

**Decoy placement:** some products add a "popular" badge to Pro to make
the anchor effect explicit. Use sparingly — sophisticated buyers see through it.

---

## 3. Good-Better-Best Tier Design

A structured approach to deciding which features go in which tier.

**Principles:**

1. **Good (Starter)**: should be genuinely useful for a real segment of users,
   not a crippled trial. Think "solo user" or "first-time buyer."

2. **Better (Pro)**: should address the most common pain points of the segment
   that outgrows Starter. Features here should feel like natural next steps,
   not arbitrary gates.

3. **Best (Scale / Enterprise)**: should address scale, compliance, and
   team-coordination needs. Features: SSO, audit logs, advanced permissions,
   custom SLAs, dedicated support.

**Feature assignment heuristic:**
For each feature, ask: "Who is blocked without this?" If the answer is
"power users and teams," it goes in Scale. If it's "growing companies,"
it goes in Pro. If it's "anyone trying the product," it goes in Starter.

**Value metric alignment:**
The value metric (what you charge per unit) should align with the tier structure.
Per-seat models work well when value scales linearly with users.
Usage-based models work well when value scales with outcomes (API calls, data processed).
