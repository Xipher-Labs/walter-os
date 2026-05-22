import { describe, expect, it } from "vitest";
import { getCanonicalBaseUrl } from "../../lib/canonical-url";

// Helper: build Headers from a plain record so each test reads naturally.
function makeHeaders(record: Record<string, string>): Headers {
  return new Headers(record);
}

describe("getCanonicalBaseUrl", () => {
  // ---------------------------------------------------------------------
  // 1. Explicit operator override — CONTROL_TOWER_PUBLIC_URL
  // ---------------------------------------------------------------------

  it("uses CONTROL_TOWER_PUBLIC_URL when set (highest priority)", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "evil.example.com" }),
      "http://0.0.0.0:3000/api/login",
      { CONTROL_TOWER_PUBLIC_URL: "https://tower.example.com" }
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("accepts CONTROL_TOWER_PUBLIC_URL with or without trailing slash", () => {
    // `new URL` normalises the trailing slash on the origin, so both
    // `https://tower.example.com` and `https://tower.example.com/` produce
    // the same canonical href. This test pins that behaviour.
    const url = getCanonicalBaseUrl(
      makeHeaders({}),
      "http://0.0.0.0:3000/api/login",
      { CONTROL_TOWER_PUBLIC_URL: "https://tower.example.com/" }
    );
    expect(url.href).toBe("https://tower.example.com/");
  });

  it("rejects CONTROL_TOWER_PUBLIC_URL with javascript: scheme", () => {
    // An operator misconfiguration setting `javascript:alert(1)` would
    // otherwise produce an unsafe Location header. Fall through to
    // header-based resolution.
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com" }),
      "http://0.0.0.0:3000",
      { CONTROL_TOWER_PUBLIC_URL: "javascript:alert(1)" }
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("rejects CONTROL_TOWER_PUBLIC_URL with file: scheme", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com" }),
      "http://0.0.0.0:3000",
      { CONTROL_TOWER_PUBLIC_URL: "file:///etc/passwd" }
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("rejects CONTROL_TOWER_PUBLIC_URL with data: scheme", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com" }),
      "http://0.0.0.0:3000",
      { CONTROL_TOWER_PUBLIC_URL: "data:text/html,<script>alert(1)</script>" }
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("falls through when CONTROL_TOWER_PUBLIC_URL is whitespace-only", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com" }),
      "http://0.0.0.0:3000/api/login",
      { CONTROL_TOWER_PUBLIC_URL: "   " }
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("ignores invalid CONTROL_TOWER_PUBLIC_URL (falls through to headers)", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com" }),
      "http://0.0.0.0:3000/api/login",
      { CONTROL_TOWER_PUBLIC_URL: "not-a-url" }
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  // ---------------------------------------------------------------------
  // 2. Trusted proxy forwarded headers — X-Forwarded-Host + X-Forwarded-Proto
  // ---------------------------------------------------------------------

  it("uses X-Forwarded-Host + X-Forwarded-Proto when present", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({
        "x-forwarded-host": "tower.example.com",
        "x-forwarded-proto": "https",
        host: "127.0.0.1:3000",
      }),
      "http://0.0.0.0:3000/api/login",
      {}
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("defaults X-Forwarded-Proto to https when X-Forwarded-Host is present", () => {
    // Cloudflare Tunnel + Tailscale Serve both terminate TLS; the origin
    // request to the container is plain HTTP. So when X-Forwarded-Host is
    // set without an explicit Proto, the public URL is virtually always
    // HTTPS.
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com" }),
      "http://0.0.0.0:3000/api/login",
      {}
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  it("honors http X-Forwarded-Proto when explicitly set", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({
        "x-forwarded-host": "tower.local",
        "x-forwarded-proto": "http",
      }),
      "http://0.0.0.0:3000/api/login",
      {}
    );
    expect(url.origin).toBe("http://tower.local");
  });

  it("uses first value from comma-separated X-Forwarded-Host", () => {
    // Multi-proxy chains may append; only the first (origin-most) is trusted.
    const url = getCanonicalBaseUrl(
      makeHeaders({
        "x-forwarded-host": "tower.example.com, internal.proxy",
        "x-forwarded-proto": "https, https",
      }),
      "http://0.0.0.0:3000",
      {}
    );
    expect(url.origin).toBe("https://tower.example.com");
  });

  // ---------------------------------------------------------------------
  // 3. Host header — when running directly (e.g., dev, local tailnet IP)
  // ---------------------------------------------------------------------

  it("uses Host header when no X-Forwarded-Host but Host is routable", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ host: "localhost:3000" }),
      "http://0.0.0.0:3000/api/login",
      {}
    );
    expect(url.origin).toBe("http://localhost:3000");
  });

  it("skips Host header when it is 0.0.0.0 (unreachable from browsers)", () => {
    // This is the bug we are fixing: Next.js standalone constructs
    // request.url from HOSTNAME (=0.0.0.0), and that ends up in the
    // Location header. The browser then refuses to navigate to 0.0.0.0.
    const url = getCanonicalBaseUrl(
      makeHeaders({ host: "0.0.0.0:3000" }),
      "http://example.com/api/login",
      {}
    );
    expect(url.origin).toBe("http://example.com");
  });

  it("skips bare 0.0.0.0 Host (no port)", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ host: "0.0.0.0" }),
      "http://example.com",
      {}
    );
    expect(url.origin).toBe("http://example.com");
  });

  it("skips X-Forwarded-Host: 0.0.0.0 (misconfigured internal proxy)", () => {
    // Symmetry with the Host-header guard: a proxy that mistakenly
    // forwards the bind sentinel would otherwise reproduce the bug.
    // Falls through to the Host header.
    const url = getCanonicalBaseUrl(
      makeHeaders({
        "x-forwarded-host": "0.0.0.0",
        host: "tower.example.com",
      }),
      "http://0.0.0.0:3000",
      {}
    );
    expect(url.origin).toBe("http://tower.example.com");
  });

  it("skips X-Forwarded-Host: 0.0.0.0:3000 with port", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "0.0.0.0:3000" }),
      "https://tower.fallback.example",
      {}
    );
    expect(url.origin).toBe("https://tower.fallback.example");
  });

  // ---------------------------------------------------------------------
  // 4. Fallback to request.url
  // ---------------------------------------------------------------------

  it("falls back to request.url as last resort", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({}),
      "https://canonical.example.com/api/login",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });

  it("documents the unreachable fallback: empty headers + 0.0.0.0 request.url returns 0.0.0.0", () => {
    // The production failure mode this fix addresses. When no proxy is
    // in front of Control Tower AND no headers are present AND the
    // request.url is the bind URL, the helper has nothing to work with
    // and returns the bad URL — this is the SAME behaviour as before
    // the fix, intentionally preserved so we don't silently invent an
    // origin. The cure for this corner case is `CONTROL_TOWER_PUBLIC_URL`:
    // operators who run without a proxy MUST set it. README and
    // `.env.example` document this requirement.
    //
    // This test exists to make the limitation explicit: any change in
    // behaviour for this case requires deliberately updating the test.
    const url = getCanonicalBaseUrl(
      makeHeaders({}),
      "http://0.0.0.0:3000/api/login",
      {}
    );
    expect(url.origin).toBe("http://0.0.0.0:3000");
  });

  // ---------------------------------------------------------------------
  // 5. Security regression guards
  // ---------------------------------------------------------------------

  it("does not honor untrusted X-Forwarded-Host when CONTROL_TOWER_PUBLIC_URL is set", () => {
    // Defense in depth: even if the proxy chain is misconfigured and a
    // hostile X-Forwarded-Host slips through, the explicit operator
    // override wins. Prevents open-redirect when Control Tower is exposed
    // without a trusted proxy in front.
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "attacker.com" }),
      "http://0.0.0.0:3000",
      { CONTROL_TOWER_PUBLIC_URL: "https://tower.legitimate.com" }
    );
    expect(url.origin).toBe("https://tower.legitimate.com");
  });

  it("never honors an X-Forwarded-Host containing a path or query", () => {
    // X-Forwarded-Host should be a bare host[:port]; reject anything else
    // to avoid URL-parsing surprises.
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com/evil" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });

  it("never honors an X-Forwarded-Host with embedded scheme", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "http://tower.example.com" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });

  it("rejects X-Forwarded-Host with @ (userinfo open-redirect vector)", () => {
    // Critical: `new URL("https://tower.example.com@evil.com")` parses
    // `tower.example.com` as userinfo and `evil.com` as the host. Without
    // the @-reject guard a hostile proxy could steer the login redirect to
    // any origin under its control.
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com@evil.com" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
    expect(url.origin).not.toContain("evil.com");
  });

  it("rejects X-Forwarded-Host with userinfo prefix (user:pass@host)", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "user:pass@evil.com" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });

  it("rejects X-Forwarded-Host with backslash (URL parser surprise)", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com\\@evil.com" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });

  it("rejects X-Forwarded-Host with fragment marker", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com#evil" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });

  it("rejects X-Forwarded-Host with query marker", () => {
    const url = getCanonicalBaseUrl(
      makeHeaders({ "x-forwarded-host": "tower.example.com?evil" }),
      "https://canonical.example.com",
      {}
    );
    expect(url.origin).toBe("https://canonical.example.com");
  });
});
