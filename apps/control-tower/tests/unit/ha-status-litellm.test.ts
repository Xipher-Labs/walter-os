/**
 * Regression test for issue #177 — Control Tower's LiteLLM tile was
 * reporting "unreachable" against a healthy LiteLLM because the probe
 * targeted `/health`, which requires `Authorization: Bearer <master-key>`.
 * Without the header LiteLLM returns 401, which the tile interprets as
 * unhealthy.
 *
 * Fix: probe LiteLLM via `/health/liveliness` — the unauthenticated
 * liveness endpoint LiteLLM exposes for k8s probes. It returns 200 OK
 * when the process is up regardless of model state.
 *
 * Refs: https://github.com/Xipher-Labs/walter-os/issues/177
 */
import { describe, expect, it, beforeEach, afterEach, vi } from "vitest";

beforeEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  delete process.env.LITELLM_STANDBY_URL;
  process.env.LITELLM_BASE_URL = "http://litellm:4000";
  process.env.GRAFANA_URL = "http://grafana:3000";
  process.env.PLANE_API_URL = "http://plane:8080";
});

afterEach(() => {
  vi.restoreAllMocks();
});

async function callGet(): Promise<{
  services: Array<{ name: string; primary_healthy: boolean }>;
}> {
  const { GET } = await import("../../app/api/ha-status/route");
  const response = (await GET()) as unknown as Response;
  return (await response.json()) as {
    services: Array<{ name: string; primary_healthy: boolean }>;
  };
}

describe("GET /api/ha-status — LiteLLM probe URL", () => {
  it("probes LiteLLM via /health/liveliness, not /health", async () => {
    const fetchSpy = vi.spyOn(global, "fetch").mockImplementation(
      async (input) => {
        // jsdom-less env: input is a string URL on our straightforward calls
        const url = typeof input === "string" ? input : input.toString();
        // LiteLLM container would 401 on /health (auth required), 200 on
        // /health/liveliness. We assert the helper hits the liveliness path.
        if (url.includes("litellm")) {
          if (url.endsWith("/health/liveliness")) {
            return new Response("OK", { status: 200 });
          }
          if (url.endsWith("/health")) {
            return new Response("Unauthorized", { status: 401 });
          }
        }
        return new Response("OK", { status: 200 });
      }
    );

    const body = await callGet();
    const litellmTile = body.services.find((s) => s.name === "LiteLLM");
    expect(litellmTile, "LiteLLM tile must be present").toBeDefined();
    expect(litellmTile!.primary_healthy).toBe(true);

    // Verify the probe URL is the liveliness path — not the auth-gated one.
    const litellmCalls = fetchSpy.mock.calls.filter(([input]) => {
      const url = typeof input === "string" ? input : input.toString();
      return url.includes("litellm");
    });
    expect(litellmCalls.length).toBeGreaterThan(0);
    for (const [input] of litellmCalls) {
      const url = typeof input === "string" ? input : input.toString();
      expect(url, "Probe URL must target /health/liveliness").toMatch(
        /\/health\/liveliness$/
      );
      expect(url, "Probe URL must NOT target the auth-gated /health").not.toMatch(
        /\/health$/
      );
    }
  });

  it("uses the same liveliness path for LITELLM_STANDBY_URL when set", async () => {
    process.env.LITELLM_STANDBY_URL = "http://litellm-standby:4000";
    const fetchSpy = vi.spyOn(global, "fetch").mockImplementation(
      async (input) => {
        const url = typeof input === "string" ? input : input.toString();
        if (url.endsWith("/health/liveliness")) {
          return new Response("OK", { status: 200 });
        }
        if (url.endsWith("/health")) {
          return new Response("Unauthorized", { status: 401 });
        }
        return new Response("OK", { status: 200 });
      }
    );

    const body = await callGet();
    const litellmTile = body.services.find((s) => s.name === "LiteLLM");
    expect(litellmTile!.primary_healthy).toBe(true);

    const standbyCalls = fetchSpy.mock.calls.filter(([input]) => {
      const url = typeof input === "string" ? input : input.toString();
      return url.includes("litellm-standby");
    });
    expect(standbyCalls.length).toBe(1);
    const standbyUrl = standbyCalls[0][0]?.toString() ?? "";
    expect(standbyUrl).toMatch(/\/health\/liveliness$/);
  });

  it("does not regress other tiles (Plane / Grafana / Control Tower keep /api/health)", async () => {
    // The fix targets ONLY the LiteLLM tile. Plane, Grafana, and Control
    // Tower expose unauthenticated /api/health endpoints; they should
    // keep that probe path.
    const fetchSpy = vi.spyOn(global, "fetch").mockImplementation(
      async () => new Response("OK", { status: 200 })
    );

    await callGet();

    const calls = fetchSpy.mock.calls.map(([input]) =>
      typeof input === "string" ? input : input.toString()
    );
    expect(calls.some((u) => u === "http://plane:8080/api/health")).toBe(true);
    expect(calls.some((u) => u === "http://grafana:3000/api/health")).toBe(true);
    expect(
      calls.some((u) => u === "http://localhost:3000/api/health")
    ).toBe(true);
  });
});
