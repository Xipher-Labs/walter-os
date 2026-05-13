---
name: web-security-baseline
description: OWASP Top 10 (web, not agentic) baseline review for any web application code change — auth, sessions, headers, CSRF, XSS, SQL injection, CORS, rate limits, secret handling, file upload, SSRF. Use this skill on any PR or diff that touches HTTP handlers, auth flows, session/cookie logic, file uploads, redirect/URL parsing, database queries with user input, or proxying/fetching external URLs. Catches the bug classes that ship to production and become public CVEs. Distinct from the security-auditor agent (which is invoked explicitly); this skill auto-triggers when relevant code is in scope.
---

# Web Security Baseline

OWASP Top 10 for web applications. Covers the bug classes that consistently
ship to production and become public CVEs. Auto-triggers on any code touching
HTTP handlers, auth, file uploads, URL parsing, or DB queries with user input.

This is BASELINE — it doesn't replace a real security audit before launch.
It catches the well-known patterns. For high-stakes systems ([Project B], [Project A]
production), the `security-auditor` agent goes deeper, and a third-party audit
goes deeper still.

## The 10 (with concrete checks)

### 1. Broken Access Control

The single most common production bug.

- **AuthN before AuthZ**: every endpoint verifies who you are BEFORE checking
  if you can do what you asked.
- **Default deny**: list of allowed actions, not list of denied. Missing role
  in the allowlist = denied.
- **IDOR check**: every "fetch resource by ID" verifies the requester owns it
  or has explicit permission. `GET /api/users/:id/orders` must check the
  caller is :id (or admin), not blindly query.
- **Privilege escalation paths**: API endpoints that change role / permissions
  audited specially. Rate-limited, logged, often require re-auth.
- **JWT claims trusted ONLY after server-side verification**: never trust
  `decoded.role` without verifying signature first.
- **Backend filtering**: don't return all users + filter on frontend. The
  backend filters; the frontend asks for what user can see.

### 2. Cryptographic Failures

- **HTTPS everywhere**: HSTS header set with `max-age >= 31536000` and
  `includeSubDomains`.
- **No DIY crypto**: use `libsodium`, `WebCrypto`, `crypto.subtle`. Never
  hand-rolled AES, never `eval` of crypto, never base64 mistaken for
  encryption.
- **Password hashing**: argon2id with reasonable parameters; bcrypt cost ≥ 12
  if argon2 unavailable. NEVER plain SHA-256, never MD5.
- **Secrets in env, not code**: pre-commit scanner (`gitleaks`/`trufflehog`)
  blocks accidental commits.
- **Token storage**: HttpOnly + Secure + SameSite=Lax (or Strict). Don't
  store in localStorage if XSS is a concern.
- **Data protection regulation** (GDPR/HIPAA/local law): personal data
  encrypted at rest, especially PHI (see `medical-data-compliance`) and
  any data covered by the applicable jurisdiction's rules.
- **Clock skew on JWT validation**: ±60s tolerance, no more.

### 3. Injection

- **SQL**: parameterized queries always. NEVER string concatenation:
  ```ts
  // BAD
  db.query(`SELECT * FROM users WHERE id = ${userId}`)
  // GOOD (Drizzle / pg)
  db.query('SELECT * FROM users WHERE id = $1', [userId])
  ```
- **NoSQL**: same pattern; mongo $where with user input = injection.
- **OS commands**: no `exec(userInput)`. If you must, allowlist + escape.
- **HTML**: framework escaping by default (React, Astro, Svelte do this).
  Never `dangerouslySetInnerHTML` with user content.
- **LDAP, XPath, log injection**: same family — escape per syntax.
- **Server-side template injection**: don't pass user input as a template,
  ever.

### 4. Insecure Design

- **Threat model documented** for any feature handling money, PHI, or auth.
- **Rate limiting at the boundary** (nginx/Caddy/edge), not just in-app.
- **Tenant isolation**: in multi-tenant code, every query filters by tenant.
  A test that proves cross-tenant access is impossible.
- **Recovery flows can't bypass primary auth**: "forgot password" doesn't
  skip MFA enrollment.

### 5. Security Misconfiguration

- **Headers**: every web app sets:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
  - `Content-Security-Policy` (start strict, relax as needed; report-only
    initially)
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY` (or `frame-ancestors` in CSP)
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy` (limit browser APIs)
- **Default credentials**: never. Bootstrap creates a single admin with
  forced password change.
- **Error pages don't leak**: stack traces in dev only. Prod returns
  opaque error + correlation ID.
- **Cloud bucket / storage**: never public-by-default. Signed URLs for
  user assets, short-lived.
- **CORS**: explicit origin allowlist. NEVER `Access-Control-Allow-Origin: *`
  with credentials. Wildcard with credentials is silently rejected by
  browsers, but the misconfig signals other bugs.

### 6. Vulnerable / Outdated Components

- `npm audit` / `cargo audit` / `pip-audit` clean before merge. CI blocks
  if findings ≥ HIGH.
- Daily dep updates via Renovate (auto-PR'd, auto-merged when patch and
  tests pass).
- Pin all MCPs, plugins, and CLI tools to versions (Walter-OS already
  enforces this).
- Subscribe to security advisories for the framework (Next.js, Astro,
  Anchor, Tonic).

### 7. Identification and Authentication Failures

- **Session ID rotation** on login + privilege change.
- **MFA** for admin/operator accounts. TOTP minimum; WebAuthn ideal.
- **Logout invalidates server-side**: not just client-side.
- **Account lockout / rate-limit**: 5 failed → exponential backoff (CAPTCHA
  or temporary lock; not permanent — that's a DoS vector).
- **Session timeout**: idle 30min for sensitive apps, absolute 24h.
- **Password reset tokens**: single-use, time-bound (≤ 1h), invalidate on use.

### 8. Software and Data Integrity Failures

- **Subresource Integrity (SRI)** on third-party scripts.
- **Signed releases** for any binary you ship.
- **CI integrity**: builds reproducible. Artifacts signed.
- **Webhook signature verification**: Stripe, GitHub, etc. — always verify
  the signature, NEVER trust the payload alone.
- **Deserialization safety**: don't `JSON.parse` from arbitrary network
  source without size cap + schema validation (zod, valibot).

### 9. Security Logging and Monitoring Failures

- **Auth events logged**: login, logout, failed login, password change, MFA
  enroll/disable.
- **Privileged actions logged**: role change, data export, mass operation.
- **NO PHI/PII in logs**: scrub before write. Use IDs not names.
- **Centralized logging**: Sentry for errors, structured logs to Loki/
  similar. Never `console.log` for prod.
- **Alerting**: spike in 401s, spike in 5xxs, geographic anomalies.

### 10. Server-Side Request Forgery (SSRF)

For any code that fetches a URL provided by the user:

- **Allowlist of allowed hosts/schemes**, not denylist.
- **Block private IP ranges**: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
  127.0.0.0/8, 169.254.0.0/16, IPv6 equivalents.
- **Block metadata services**: 169.254.169.254 (AWS/GCP/Azure metadata),
  fd00:ec2::254 (IPv6).
- **Resolve DNS server-side and validate**: attackers do DNS rebinding —
  resolve once, fetch from that IP, not the hostname.
- **Disable redirects** or follow with same checks.
- **Limit response size and time**.

## Stack-specific (Walter-OS operator)

### Next.js / React

- Server actions: validate input with zod before any work.
- Client components don't receive server-only env vars (no `process.env.X`
  prefix that leaks).
- No `dangerouslySetInnerHTML` ever for user content; for trusted content,
  sanitize with DOMPurify even if "trusted".
- Middleware runs auth check before every protected route.
- Image optimization: `next/image` validates remote URLs against config.

### Supabase

- RLS policies on every table. Test that anon key cannot read what it
  shouldn't.
- `select` policies separate from `insert/update/delete`. Apply principle
  of least privilege per role.
- Service role key NEVER in client code. Server-only.
- Storage buckets: bucket-level + object-level policies.

### Solana programs (already covered by `solana-program-review`)

Not duplicated here — see `solana-program-review` skill for signer/owner
checks, discriminator, PDA collisions, etc.

### RPC / API handlers

- Per-method, per-API-key rate limits (see `solana-rpc-review` for Solana-specific).
- Customer credentials never in logs.
- Auth via API key in `Authorization: Bearer` header, not query string
  (logs leak query strings).

## Output format

For every finding:

```
**[BLOCKING|WARN|NIT] [SEC-N] <one-line>**

Where: `path/to/file.ts:42-58`
Class: <which OWASP item, e.g. "A01: Broken Access Control">
Vector: <how it's exploited — one sentence>
Fix: <specific change, code if it fits>
References: <CWE, OWASP link, or relevant CVE if pattern-known>
```

Severity:
- **BLOCKING**: known-exploitable pattern. Auth bypass, injection, IDOR,
  SSRF that reaches metadata. Must fix before merge.
- **WARN**: best-practice gap, defense-in-depth. Should fix soon.
- **NIT**: minor (e.g., header could be tightened, log scrubbing more
  defensive).

## Tooling that complements this skill

Run these in CI; they catch what a code reviewer misses:

- **`semgrep`** — pattern-matching SAST. Free with curated rules.
- **`gitleaks`** or **`trufflehog`** — pre-commit secret scanner.
- **`npm audit` / `cargo audit`** — dependency CVEs.
- **`@vercel/edge-config` security headers preset** or middleware that sets
  baseline headers.
- **OWASP ZAP** baseline scan in staging — automated DAST.
- **Snyk / Socket.dev** for dep + supply chain — paid but worth it for
  production projects.

## Hard rules

- **A finding here is a BLOCKER until acked**: this skill does not allow
  "we'll fix it later" without an explicit `walter-os ack <id>` (with
  reason + ticket reference).
- **Defense in depth**: even when one layer protects, add another. CSP +
  output encoding + input validation, not "we have CSP so output encoding
  is optional".
- **Trust no input**: query params, headers, cookies, request bodies, file
  uploads, environment variables that come from outside the trust boundary.
- **For [Project B] specifically**: this skill's findings stack with
  `medical-data-compliance` rules. PHI-related findings are CRITICAL,
  not BLOCKING — different escalation path.

## What this skill does NOT cover

- Solana on-chain code (use `solana-program-review`).
- RPC infrastructure code (use `solana-rpc-review`).
- Agentic / MCP / supply-chain attacks (use `daily-supply-chain-audit` +
  `security-auditor` agent).
- Compliance-specific frameworks (PCI DSS, HIPAA, SOC 2). Those need their
  own checklists.

## References

- OWASP Top 10 2021 (most-recent stable; 2025 update in flight)
- OWASP ASVS Level 2 (Application Security Verification Standard)
- CWE Top 25
- Mozilla Web Security Cheatsheet
- Securing Express, Securing Next.js, Supabase docs RLS section
