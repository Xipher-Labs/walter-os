"use client";

import { useEffect, useState, useCallback } from "react";
import type { ServiceStatus } from "@/app/api/ha-status/route";

/**
 * HA Status — shows primary and standby health for all Tier-A services.
 * Refreshes every 60 seconds.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6)
 * Task: T-42
 */

// U-r2-3: healthy is boolean | null — null means "no standby configured" (N/A).
function StatusDot({ healthy }: { healthy: boolean | null }) {
  if (healthy === null) {
    return (
      <span
        className="inline-block h-2.5 w-2.5 rounded-full bg-zinc-400"
        title="N/A — no standby configured"
      />
    );
  }
  return (
    <span
      className={`inline-block h-2.5 w-2.5 rounded-full ${
        healthy ? "bg-emerald-500" : "bg-red-500"
      }`}
    />
  );
}

export default function HAStatus() {
  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);

  const fetchStatus = useCallback(async () => {
    try {
      const res = await fetch("/api/ha-status");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { services: ServiceStatus[] };
      setServices(data.services);
      setLastUpdated(new Date().toLocaleTimeString());
    } catch {
      // keep stale data
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 60_000);
    return () => clearInterval(interval);
  }, [fetchStatus]);

  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
          HA Status
        </h2>
        {lastUpdated && (
          <span className="text-xs text-zinc-400 dark:text-zinc-500">
            {lastUpdated}
          </span>
        )}
      </div>

      <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 overflow-hidden">
        {loading ? (
          <div className="p-4 flex flex-col gap-2">
            {[...Array(4)].map((_, i) => (
              <div
                key={i}
                className="h-8 bg-zinc-100 dark:bg-zinc-800 rounded animate-pulse"
              />
            ))}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-900">
                <th className="text-left py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Service
                </th>
                <th className="text-center py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Primary
                </th>
                <th className="text-center py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Standby
                </th>
                <th className="text-right py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Latency
                </th>
              </tr>
            </thead>
            <tbody>
              {services.map((svc, i) => (
                <tr
                  key={svc.name}
                  className={`border-b border-zinc-100 dark:border-zinc-800 ${
                    i % 2 === 0
                      ? "bg-white dark:bg-zinc-950"
                      : "bg-zinc-50/50 dark:bg-zinc-900/50"
                  }`}
                >
                  <td className="py-2 px-4 text-zinc-900 dark:text-zinc-100 font-medium">
                    {svc.name}
                  </td>
                  <td className="py-2 px-4 text-center">
                    <StatusDot healthy={svc.primary_healthy} />
                  </td>
                  <td className="py-2 px-4 text-center">
                    <StatusDot healthy={svc.standby_healthy} />
                  </td>
                  <td className="py-2 px-4 text-right text-xs text-zinc-500 dark:text-zinc-400 font-mono">
                    {svc.primary_latency_ms !== undefined
                      ? `${svc.primary_latency_ms}ms`
                      : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </section>
  );
}
