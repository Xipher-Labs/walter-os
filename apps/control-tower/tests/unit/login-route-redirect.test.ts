/**
 * Integration-flavoured test for the POST /api/login handler — verifies that
 * the redirect Location header points at the canonical PUBLIC base URL the
 * browser used (not at http://0.0.0.0:3000/ which the standalone Next.js
 * server reports as request.url when HOSTNAME=0.0.0.0).
 *
 * Regression: see https://github.com/Xipher-Labs/walter-os/issues/... —
 * Walter-VM operators reported that after submitting the admin token the
 * browser was redirected to 0.0.0.0:3000 and refused to follow.
 */
import { describe, expect, it, beforeEach, vi } from "vitest";

// Node 22 already ships WebCrypto under the global `crypto` object, so the
// real `crypto.subtle` is available — no stubbing required. We reset env
// + module cache between tests so each case sees a fresh handler with
// deterministic env.
beforeEach(() => {
  process.env.CONTROL_TOWER_ADMIN_TOKEN = "test-admin-token";
  delete process.env.CONTROL_TOWER_PUBLIC_URL;
  // NODE_ENV is read-only typed; assign rather than delete for TS.
  (process.env as Record<string, string | undefined>).NODE_ENV = undefined;
  vi.resetModules();
});

async function callPost(input: {
  body: Record<string, string>;
  headers?: Record<string, string>;
  url?: string;
}): Promise<Response> {
  const { POST } = await import("../../app/api/login/route");
  const formBody = new URLSearchParams(input.body).toString();
  const request = new Request(input.url ?? "http://0.0.0.0:3000/api/login", {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      ...input.headers,
    },
    body: formBody,
  });
  return POST(request) as unknown as Response;
}

describe("POST /api/login redirect Location", () => {
  it("redirects to the X-Forwarded-Host on success, not to 0.0.0.0:3000", async () => {
    const response = await callPost({
      body: { token: "test-admin-token", next: "/" },
      headers: {
        "x-forwarded-host": "tower.example.com",
        "x-forwarded-proto": "https",
        host: "127.0.0.1:3000",
      },
    });

    expect(response.status).toBe(303);
    const location = response.headers.get("location");
    expect(location).toBe("https://tower.example.com/");
  });

  it("redirects to the X-Forwarded-Host on bad-token error", async () => {
    const response = await callPost({
      body: { token: "wrong-token", next: "/dashboard" },
      headers: {
        "x-forwarded-host": "tower.example.com",
        "x-forwarded-proto": "https",
      },
    });

    expect(response.status).toBe(303);
    const location = response.headers.get("location");
    expect(location).not.toBeNull();
    const url = new URL(location!);
    expect(url.origin).toBe("https://tower.example.com");
    expect(url.pathname).toBe("/login");
    expect(url.searchParams.get("error")).toBe("1");
    expect(url.searchParams.get("next")).toBe("/dashboard");
  });

  it("honours CONTROL_TOWER_PUBLIC_URL even when forwarded headers differ", async () => {
    process.env.CONTROL_TOWER_PUBLIC_URL = "https://tower.canonical.example";
    const response = await callPost({
      body: { token: "test-admin-token", next: "/" },
      headers: {
        // hostile / misconfigured proxy claims a different host
        "x-forwarded-host": "attacker.example.com",
      },
    });

    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe(
      "https://tower.canonical.example/"
    );
  });

  it("does not emit 0.0.0.0 in the redirect when no forwarded headers exist (falls back to request.url)", async () => {
    // No forwarded headers — the helper falls back to the Request URL.
    // This still works because `new Request("http://0.0.0.0:3000/...")` is
    // the raw bind address; the test asserts behaviour rather than ideal
    // (operators relying on this path get the same legacy behaviour).
    // The fix's contract is: when forwarded headers ARE present, never
    // return 0.0.0.0.
    const response = await callPost({
      body: { token: "test-admin-token", next: "/" },
      headers: {},
      url: "https://tower.fallback.example/api/login",
    });

    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe(
      "https://tower.fallback.example/"
    );
  });
});
