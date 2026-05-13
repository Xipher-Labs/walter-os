/**
 * Tailscale access enforcement — E2E test (integration tier).
 *
 * Tests the live server behavior: health + SSE endpoints when
 * TAILSCALE_ENFORCE=false (the default for the test webserver) and
 * Control Tower token auth is satisfied by the Playwright context header.
 *
 * The TAILSCALE_ENFORCE=true + non-Tailscale IP → 403 path is covered at
 * unit level in tests/unit/tailscale.test.ts (isTailscaleAllowed suite).
 * A full integration test for that path requires spawning a second Next.js
 * server with a different env — tracked as a CI matrix improvement, not
 * implemented here to avoid false coverage.
 *
 * Refs: docs/specs/walter-council-v2.md (AC-1)
 * Reviewer round 1 finding: E2E behavioral coverage missing.
 * Reviewer round 2 finding: test name misrepresented what was being tested.
 */
import { test, expect, request } from "@playwright/test";

test.describe("Tailscale enforcement [AC-1]", () => {
  test("health endpoint accessible when TAILSCALE_ENFORCE=false", async () => {
    // Verifies the server is up and /api/health correctly bypasses
    // Tailscale enforcement (health must always be reachable).
    // Unit-level 403 coverage: see tests/unit/tailscale.test.ts
    const ctx = await request.newContext({
      baseURL: process.env.BASE_URL ?? "http://localhost:3000",
    });

    // /api/health should always return 200 (Tailscale bypassed for health)
    const healthRes = await ctx.get("/api/health");
    expect(healthRes.status()).toBe(200);

    // With TAILSCALE_ENFORCE=false (test env default), /api/sse should return 200
    // with content-type: text/event-stream. SSE is a streaming response that never
    // completes; use AbortController to abort after reading headers.
    const sseBaseURL = process.env.BASE_URL ?? "http://localhost:3000";
    const ctrl = new AbortController();
    const sseRes = await fetch(`${sseBaseURL}/api/sse`, {
      headers: {
        Authorization: `Bearer ${
          process.env.CONTROL_TOWER_ADMIN_TOKEN ?? "control-tower-e2e-token"
        }`,
      },
      signal: ctrl.signal,
    });
    const sseStatus = sseRes.status;
    const sseCT = sseRes.headers.get("content-type") ?? "";
    ctrl.abort(); // close the SSE stream; body reads are not needed
    expect(sseStatus).toBe(200);
    expect(sseCT).toContain("text/event-stream");

    await ctx.dispose();
  });

  test("middleware bypasses Tailscale check for /api/health", async ({ request: req }) => {
    // /api/health must always be accessible regardless of IP enforcement
    // This is a safety property: the health check must not be blocked
    const response = await req.get("/api/health");
    expect(response.status()).toBe(200);
    const body = (await response.json()) as { status: string };
    expect(body.status).toBe("ok");
  });
});
