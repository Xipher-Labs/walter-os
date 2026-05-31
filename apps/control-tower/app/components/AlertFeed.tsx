"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import type { TimelineEntry, AlertTier } from "@/lib/events-reader";
import StatusBadge from "@/app/components/ui/StatusBadge";
import { SectionTitle } from "@/app/components/ui/Panel";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import { tierToStatus } from "@/app/components/ui/status";

/**
 * Alert Feed — recent warn/critical/panic alerts. Updates every 30s.
 * Acknowledged alerts dismiss client-side. Re-skinned to the shared status
 * language (D-4): tier → StatusBadge, no per-tier inline colour map.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-43
 */

export default function AlertFeed() {
  const [alerts, setAlerts] = useState<TimelineEntry[]>([]);
  const [acked, setAcked] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // Tracks whether we have ever loaded data, read inside the interval-captured
  // closure so a transient error after the first success keeps stale data
  // instead of flipping the surface to an error state.
  const hasDataRef = useRef(false);

  const fetchAlerts = useCallback(async () => {
    try {
      const res = await fetch("/api/alerts");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { alerts: TimelineEntry[] };
      setAlerts(data.alerts);
      setError(null);
    } catch {
      // Surface the error only when we have nothing to show; otherwise keep
      // the last good data and let the next refresh recover silently.
      setError((prev) => (hasDataRef.current ? prev : "Alerts unavailable."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    hasDataRef.current = alerts.length > 0;
  }, [alerts.length]);

  useEffect(() => {
    fetchAlerts();
    const interval = setInterval(fetchAlerts, 30_000);
    return () => clearInterval(interval);
  }, [fetchAlerts]);

  const visible = alerts.filter((a) => !acked.has(a.id));

  const emptyState = (
    <p className="text-sm text-muted">
      All clear. No active alerts.
    </p>
  );

  return (
    <section aria-label="Alerts">
      <SectionTitle
        meta={
          visible.length > 0 && (
            <StatusBadge
              status="critical"
              label={`${visible.length} active`}
              pulse={false}
            />
          )
        }
      >
        Alerts
      </SectionTitle>
      <AsyncSurface
        loading={loading}
        empty={visible.length === 0}
        error={error}
        emptyState={emptyState}
        onRetry={() => {
          setLoading(true);
          setError(null);
          fetchAlerts();
        }}
        skeleton={
          <div className="h-16 animate-pulse rounded-xl bg-surface-2/60" />
        }
      >
        <div className="flex flex-col gap-2">
          {visible.map((alert) => {
            const tier: AlertTier = alert.tier ?? "info";
            return (
              <div
                key={alert.id}
                className="flex items-start gap-3 rounded-xl border border-border bg-surface-1 p-3"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <StatusBadge
                      status={tierToStatus(tier)}
                      label={tier}
                      pulse={tier === "panic" || tier === "critical"}
                    />
                    {alert.agent && (
                      <span className="text-xs text-muted">{alert.agent}</span>
                    )}
                  </div>
                  <p className="mt-1 text-sm text-foreground">{alert.message}</p>
                </div>
                <button
                  type="button"
                  onClick={() =>
                    setAcked((prev) => new Set([...prev, alert.id]))
                  }
                  className="shrink-0 whitespace-nowrap rounded-md px-2 py-1 text-xs text-muted transition-colors hover:bg-surface-2 hover:text-foreground"
                >
                  Ack
                </button>
              </div>
            );
          })}
        </div>
      </AsyncSurface>
    </section>
  );
}
