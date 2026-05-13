"use client";

import { useEffect, useState, useCallback } from "react";
import type { TimelineEntry, AlertTier } from "@/lib/events-reader";

/**
 * Alert Feed — shows recent warn/critical/panic alerts.
 * Updates every 30s. Acknowledged alerts can be dismissed client-side.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6)
 * Task: T-43
 */

const TIER_STYLES: Record<AlertTier, { bg: string; badge: string }> = {
  info: { bg: "bg-zinc-50 dark:bg-zinc-900", badge: "text-zinc-500" },
  warn: {
    bg: "bg-amber-50 dark:bg-amber-950/20",
    badge: "text-amber-600 dark:text-amber-400",
  },
  critical: {
    bg: "bg-red-50 dark:bg-red-950/20",
    badge: "text-red-600 dark:text-red-400",
  },
  panic: {
    bg: "bg-red-100 dark:bg-red-950/40",
    badge: "text-red-700 dark:text-red-300 font-bold animate-pulse",
  },
};

export default function AlertFeed() {
  const [alerts, setAlerts] = useState<TimelineEntry[]>([]);
  const [acked, setAcked] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);

  const fetchAlerts = useCallback(async () => {
    try {
      const res = await fetch("/api/alerts");
      if (!res.ok) return;
      const data = (await res.json()) as { alerts: TimelineEntry[] };
      setAlerts(data.alerts);
    } catch {
      // keep stale
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchAlerts();
    const interval = setInterval(fetchAlerts, 30_000);
    return () => clearInterval(interval);
  }, [fetchAlerts]);

  const visible = alerts.filter((a) => !acked.has(a.id));

  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
          Alerts
          {visible.length > 0 && (
            <span className="ml-2 inline-flex items-center rounded-full bg-red-100 dark:bg-red-900/30 px-2 py-0.5 text-xs font-medium text-red-600 dark:text-red-400">
              {visible.length}
            </span>
          )}
        </h2>
      </div>

      {loading ? (
        <div className="h-16 bg-zinc-100 dark:bg-zinc-800 rounded animate-pulse" />
      ) : visible.length === 0 ? (
        <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 p-4 text-center">
          <p className="text-sm text-zinc-400 italic">All clear.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {visible.map((alert) => {
            const tier = alert.tier ?? "info";
            const styles = TIER_STYLES[tier];
            return (
              <div
                key={alert.id}
                className={`rounded-xl border border-zinc-200 dark:border-zinc-700 p-3 flex items-start gap-3 ${styles.bg}`}
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline gap-2">
                    <span className={`text-xs font-medium uppercase ${styles.badge}`}>
                      {tier}
                    </span>
                    {alert.agent && (
                      <span className="text-xs text-zinc-500 dark:text-zinc-400">
                        {alert.agent}
                      </span>
                    )}
                  </div>
                  <p className="text-sm text-zinc-700 dark:text-zinc-300 mt-0.5">
                    {alert.message}
                  </p>
                </div>
                <button
                  onClick={() => setAcked((prev) => new Set([...prev, alert.id]))}
                  className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 whitespace-nowrap flex-shrink-0"
                >
                  Ack
                </button>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
