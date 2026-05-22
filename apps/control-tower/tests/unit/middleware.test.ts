import { afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { middleware } from "../../middleware";

function request(path: string, headers: Record<string, string> = {}): NextRequest {
  return new NextRequest(`http://localhost${path}`, {
    headers: new Headers(headers),
  });
}

describe("Control Tower middleware ordering", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("blocks non-tailnet login requests before auth redirects", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("TAILSCALE_ENFORCE", "true");
    vi.stubEnv("CONTROL_TOWER_ADMIN_TOKEN", "test-admin-token");

    const response = await middleware(
      request("/login", { "x-forwarded-for": "8.8.8.8" })
    );

    expect(response.status).toBe(403);
  });

  it("blocks non-tailnet API requests even with a valid bearer token", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("TAILSCALE_ENFORCE", "true");
    vi.stubEnv("CONTROL_TOWER_ADMIN_TOKEN", "test-admin-token");

    const response = await middleware(
      request("/api/sse", {
        authorization: "Bearer test-admin-token",
        "x-forwarded-for": "8.8.8.8",
      })
    );

    expect(response.status).toBe(403);
  });

  it("blocks non-tailnet asset requests before auth bypasses", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("TAILSCALE_ENFORCE", "true");
    vi.stubEnv("CONTROL_TOWER_ADMIN_TOKEN", "test-admin-token");

    const response = await middleware(
      request("/assets/logo.svg", { "x-forwarded-for": "8.8.8.8" })
    );

    expect(response.status).toBe(403);
  });
});

describe("Control Tower middleware login redirect (canonical URL)", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  // The exact production failure path the operator hit on Walter-VM:
  // tailnet client → /dashboard → no session → middleware redirects to
  // /login. Before the fix the Location header was http://0.0.0.0:3000/login
  // (built from request.nextUrl which Next.js standalone constructs from
  // HOSTNAME=0.0.0.0). After the fix it must respect X-Forwarded-Host.
  it("redirects to X-Forwarded-Host /login on missing session (not 0.0.0.0)", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("TAILSCALE_ENFORCE", "true");
    vi.stubEnv("CONTROL_TOWER_ADMIN_TOKEN", "test-admin-token");

    const response = await middleware(
      request("/dashboard", {
        "x-forwarded-for": "100.64.0.1",
        "x-forwarded-host": "tower.example.com",
        "x-forwarded-proto": "https",
        host: "127.0.0.1:3000",
      })
    );

    expect(response.status).toBe(303);
    const location = response.headers.get("location");
    expect(location).not.toBeNull();
    expect(location).not.toContain("0.0.0.0");
    const url = new URL(location!);
    expect(url.origin).toBe("https://tower.example.com");
    expect(url.pathname).toBe("/login");
    expect(url.searchParams.get("next")).toBe("/dashboard");
  });

  it("honours CONTROL_TOWER_PUBLIC_URL over forwarded headers in the login redirect", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("TAILSCALE_ENFORCE", "true");
    vi.stubEnv("CONTROL_TOWER_ADMIN_TOKEN", "test-admin-token");
    vi.stubEnv("CONTROL_TOWER_PUBLIC_URL", "https://tower.canonical.example");

    const response = await middleware(
      request("/dashboard", {
        "x-forwarded-for": "100.64.0.1",
        // hostile / misconfigured proxy claims a different host
        "x-forwarded-host": "attacker.example",
      })
    );

    expect(response.status).toBe(303);
    const location = response.headers.get("location");
    expect(location).not.toBeNull();
    const url = new URL(location!);
    expect(url.origin).toBe("https://tower.canonical.example");
    expect(url.pathname).toBe("/login");
  });

  it("preserves the original request path + query in the next param", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("TAILSCALE_ENFORCE", "true");
    vi.stubEnv("CONTROL_TOWER_ADMIN_TOKEN", "test-admin-token");

    const response = await middleware(
      request("/history?limit=50&from=2026-05-01", {
        "x-forwarded-for": "100.64.0.1",
        "x-forwarded-host": "tower.example.com",
        "x-forwarded-proto": "https",
      })
    );

    expect(response.status).toBe(303);
    const url = new URL(response.headers.get("location")!);
    expect(url.origin).toBe("https://tower.example.com");
    expect(url.searchParams.get("next")).toBe(
      "/history?limit=50&from=2026-05-01"
    );
  });
});
