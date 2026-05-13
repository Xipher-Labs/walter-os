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
