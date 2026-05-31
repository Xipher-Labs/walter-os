"use client";

import { useEffect, useState, useCallback } from "react";
import type { ServiceStatus } from "@/app/api/ha-status/route";
import StatusDot from "@/app/components/ui/StatusDot";
import { SectionTitle, Panel } from "@/app/components/ui/Panel";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import { healthToStatus } from "@/app/components/ui/status";

/**
 * HA Status — primary/standby health for all Tier-A services. Refreshes every
 * 60s. Re-skinned to the shared status language (D-4): health maps through
 * healthToStatus so null (no standby) renders "n/a", never green.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-42
 */

function HealthCell({ healthy }: { healthy: boolean | null }) {
  const status = healthToStatus(healthy);
  const label =
    healthy === null ? "n/a" : healthy ? "healthy" : "down";
  // srOnlyLabel={false} renders the state as visible text beside the dot so the
  // status is never conveyed by hue alone (WCAG 1.4.1, AC-5) — matching the
  // agent board and alert feed, where the label is always on screen.
  return (
    <span className="inline-flex justify-center">
      <StatusDot
        status={status}
        label={label}
        srOnlyLabel={false}
        pulse={false}
      />
    </span>
  );
}

export default function HAStatus() {
  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);

  const fetchStatus = useCallback(async () => {
    try {
      const res = await fetch("/api/ha-status");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { services: ServiceStatus[] };
      setServices(data.services);
      setError(null);
      setLastUpdated(new Date().toLocaleTimeString());
    } catch {
      // Surface the error only when we have nothing to show; otherwise keep
      // the last good data and let the next refresh recover silently.
      setError((prev) => (services.length === 0 ? "Status unavailable." : prev));
    } finally {
      setLoading(false);
    }
  }, [services.length]);

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 60_000);
    return () => clearInterval(interval);
    // fetchStatus intentionally excluded: re-creating it each render (it closes
    // over services.length) would reset the 60s interval on every update.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const skeleton = (
    <Panel padded={false}>
      <div className="flex flex-col gap-2 p-4">
        {[...Array(4)].map((_, i) => (
          <div
            key={i}
            className="h-8 animate-pulse rounded-lg bg-surface-2/60"
          />
        ))}
      </div>
    </Panel>
  );

  return (
    <section aria-label="High-availability status">
      <SectionTitle
        meta={
          lastUpdated && <span className="text-subtle">{lastUpdated}</span>
        }
      >
        Service health
      </SectionTitle>
      <AsyncSurface
        loading={loading}
        error={error}
        onRetry={() => {
          setLoading(true);
          setError(null);
          fetchStatus();
        }}
        skeleton={skeleton}
      >
        <Panel padded={false} className="overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-surface-2/50 text-2xs uppercase tracking-wide text-subtle">
                <th className="px-4 py-2 text-left font-medium">Service</th>
                <th className="px-4 py-2 text-center font-medium">Primary</th>
                <th className="px-4 py-2 text-center font-medium">Standby</th>
                <th className="px-4 py-2 text-right font-medium">Latency</th>
              </tr>
            </thead>
            <tbody>
              {services.map((svc) => (
                <tr
                  key={svc.name}
                  className="border-b border-border/60 last:border-0 transition-colors hover:bg-surface-2/40"
                >
                  <td className="px-4 py-2.5 font-medium text-foreground">
                    {svc.name}
                  </td>
                  <td className="px-4 py-2.5 text-center">
                    <HealthCell healthy={svc.primary_healthy} />
                  </td>
                  <td className="px-4 py-2.5 text-center">
                    <HealthCell healthy={svc.standby_healthy} />
                  </td>
                  <td className="tabular px-4 py-2.5 text-right text-xs text-muted">
                    {svc.primary_latency_ms !== undefined
                      ? `${svc.primary_latency_ms}ms`
                      : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Panel>
      </AsyncSurface>
    </section>
  );
}
