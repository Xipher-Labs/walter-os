"use client";

import { useEffect, useState, useCallback } from "react";
import type { TimelineEntry, AlertTier } from "@/lib/events-reader";

/**
 * Decision Timeline — shows last N events from the Council audit log.
 * Refreshes every 30 seconds. Color-coded by alert tier.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-3)
 * Task: T-39
 */

const TIER_STYLES: Record<
  AlertTier,
  { dot: string; badge: string; border: string }
> = {
  info: {
    dot: "bg-zinc-400",
    badge: "text-zinc-500",
    border: "border-l-zinc-200 dark:border-l-zinc-700",
  },
  warn: {
    dot: "bg-amber-400",
    badge: "text-amber-600 dark:text-amber-400",
    border: "border-l-amber-400",
  },
  critical: {
    dot: "bg-red-500",
    badge: "text-red-600 dark:text-red-400",
    border: "border-l-red-500",
  },
  panic: {
    dot: "bg-red-700 animate-pulse",
    badge: "text-red-700 dark:text-red-300 font-bold",
    border: "border-l-red-700",
  },
};

function formatRelativeTime(ts: string): string {
  try {
    const diff = Date.now() - new Date(ts).getTime();
    const secs = Math.floor(diff / 1000);
    if (secs < 60) return `${secs}s ago`;
    const mins = Math.floor(secs / 60);
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    return new Date(ts).toLocaleDateString();
  } catch {
    return ts;
  }
}

function TimelineItem({ entry }: { entry: TimelineEntry }) {
  const tier = entry.tier ?? "info";
  const styles = TIER_STYLES[tier];
  const [expanded, setExpanded] = useState(false);

  return (
    <div
      className={`border-l-2 pl-4 py-2 ${styles.border} flex flex-col gap-1`}
    >
      <div className="flex items-start gap-2">
        <span
          className={`mt-1.5 h-2 w-2 rounded-full flex-shrink-0 ${styles.dot}`}
        />
        <div className="flex-1 min-w-0">
          <div className="flex items-baseline gap-2 flex-wrap">
            <span className={`text-xs font-medium uppercase ${styles.badge}`}>
              {tier}
            </span>
            {entry.agent && (
              <span className="text-xs text-zinc-500 dark:text-zinc-400">
                {entry.agent}
              </span>
            )}
            {entry.issue_id && (
              <span className="text-xs text-zinc-400 dark:text-zinc-500 font-mono">
                {entry.issue_id}
              </span>
            )}
            <span className="text-xs text-zinc-400 dark:text-zinc-500 ml-auto">
              {formatRelativeTime(entry.ts)}
            </span>
          </div>
          <p className="text-sm text-zinc-700 dark:text-zinc-300 mt-0.5 break-words">
            {entry.message}
          </p>
          {Object.keys(entry.raw).length > 0 && (
            <button
              onClick={() => setExpanded((v) => !v)}
              className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 mt-1"
            >
              {expanded ? "hide detail" : "show detail"}
            </button>
          )}
          {expanded && (
            <pre className="mt-2 text-xs bg-zinc-100 dark:bg-zinc-800 rounded p-2 overflow-x-auto text-zinc-600 dark:text-zinc-400">
              {JSON.stringify(entry.raw, null, 2)}
            </pre>
          )}
        </div>
      </div>
    </div>
  );
}

export default function DecisionTimeline() {
  const [entries, setEntries] = useState<TimelineEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);

  const fetchEntries = useCallback(async () => {
    try {
      const res = await fetch("/api/timeline?limit=50");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { entries: TimelineEntry[] };
      setEntries(data.entries);
      setLastUpdated(new Date().toLocaleTimeString());
    } catch {
      // Fail silently — keep stale data
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEntries();
    const interval = setInterval(fetchEntries, 30_000);
    return () => clearInterval(interval);
  }, [fetchEntries]);

  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
          Decision Timeline
        </h2>
        {lastUpdated && (
          <span className="text-xs text-zinc-400 dark:text-zinc-500">
            updated {lastUpdated}
          </span>
        )}
      </div>

      {loading ? (
        <div className="flex flex-col gap-3">
          {[...Array(5)].map((_, i) => (
            <div
              key={i}
              className="h-12 bg-zinc-100 dark:bg-zinc-800 rounded animate-pulse"
            />
          ))}
        </div>
      ) : entries.length === 0 ? (
        <p className="text-sm text-zinc-400 dark:text-zinc-500 italic">
          No events yet. Events appear here once agents start running.
        </p>
      ) : (
        <div className="flex flex-col gap-1 max-h-96 overflow-y-auto pr-1">
          {entries.map((entry) => (
            <TimelineItem key={entry.id} entry={entry} />
          ))}
        </div>
      )}
    </section>
  );
}
