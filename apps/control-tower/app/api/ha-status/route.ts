/**
 * HA Status API — polls health check endpoints for all Tier-A services.
 * Returns {service, primary_healthy, standby_healthy} for each service.
 *
 * GET /api/ha-status
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6)
 * Task: T-42
 */
export const dynamic = "force-dynamic";

export interface ServiceStatus {
  name: string;
  primary_healthy: boolean;
  // U-r2-3: null means no standby configured (N/A), not "healthy".
  // Returning true when standby_url is absent is semantically wrong and
  // causes the UI to show green for a standby that doesn't exist.
  standby_healthy: boolean | null;
  primary_latency_ms?: number;
  standby_latency_ms?: number;
}

interface HealthTarget {
  name: string;
  primary_url: string;
  standby_url?: string;
}

async function checkHealth(
  url: string,
  timeoutMs = 5000
): Promise<{ healthy: boolean; latency_ms: number }> {
  const start = Date.now();
  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(timeoutMs),
      headers: { "User-Agent": "control-tower/1.0 healthcheck" },
    });
    const latency_ms = Date.now() - start;
    return { healthy: res.ok, latency_ms };
  } catch {
    return { healthy: false, latency_ms: Date.now() - start };
  }
}

export async function GET(): Promise<Response> {
  const grafanaUrl = process.env.GRAFANA_URL ?? "http://grafana:3000";
  const planeUrl = process.env.PLANE_API_URL ?? "http://plane:8080";
  const litellmUrl = process.env.LITELLM_BASE_URL ?? "http://litellm:4000";

  // Tier-A services as documented in homelab-topology.md.
  // standby_url points at an optional standby homelab node when configured.
  const targets: HealthTarget[] = [
    {
      name: "LiteLLM",
      primary_url: `${litellmUrl}/health`,
      standby_url: process.env.LITELLM_STANDBY_URL
        ? `${process.env.LITELLM_STANDBY_URL}/health`
        : undefined,
    },
    {
      name: "Plane",
      primary_url: `${planeUrl}/api/health`,
      standby_url: undefined,
    },
    {
      name: "Grafana",
      primary_url: `${grafanaUrl}/api/health`,
      standby_url: undefined,
    },
    {
      name: "Control Tower",
      primary_url: "http://localhost:3000/api/health",
      standby_url: undefined,
    },
  ];

  const results = await Promise.all(
    targets.map(async (target): Promise<ServiceStatus> => {
      const [primary, standby] = await Promise.all([
        checkHealth(target.primary_url),
        target.standby_url
          ? checkHealth(target.standby_url)
          : Promise.resolve({ healthy: false, latency_ms: 0 }),
      ]);

      return {
        name: target.name,
        primary_healthy: primary.healthy,
        standby_healthy: target.standby_url ? standby.healthy : null, // null = no standby configured (N/A)
        primary_latency_ms: primary.latency_ms,
        standby_latency_ms: target.standby_url ? standby.latency_ms : undefined,
      };
    })
  );

  return Response.json({ services: results, ts: new Date().toISOString() });
}
