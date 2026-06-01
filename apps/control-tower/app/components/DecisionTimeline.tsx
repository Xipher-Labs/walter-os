"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import type { TimelineEntry, AlertTier } from "@/lib/events-reader";
import StatusDot from "@/app/components/ui/StatusDot";
import { SectionTitle } from "@/app/components/ui/Panel";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import { tierToStatus } from "@/app/components/ui/status";

/**
 * Decision Timeline — last N events from the Council audit log, refreshed
 * every 30s. Re-skinned to the shared status language (D-4).
 *
 * The old version marked tier with a `border-left-2` accent stripe — an
 * impeccable absolute ban. Replaced with a leading StatusDot on a rail formed
 * by a 1px full hairline, which carries the same information without the
 * side-stripe AI-slop signature.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-3)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-39
 */

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
  const tier: AlertTier = entry.tier ?? "info";
  const [expanded, setExpanded] = useState(false);
  const hasDetail = Object.keys(entry.raw).length > 0;

  return (
    <div className="flex gap-3 border-b border-border/50 py-2.5 last:border-0">
      <div className="pt-1.5">
        <StatusDot status={tierToStatus(tier)} label={tier} size="sm" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-2">
          <span
            className={`text-2xs font-semibold uppercase tracking-wide ${
              tier === "info" ? "text-muted" : ""
            }`}
          >
            <span className="sr-only">tier </span>
            {tier}
          </span>
          {entry.agent && (
            <span className="text-xs text-muted">{entry.agent}</span>
          )}
          {entry.issue_id && (
            <span className="tabular text-xs text-subtle">{entry.issue_id}</span>
          )}
          <span className="tabular ml-auto text-xs text-subtle">
            {formatRelativeTime(entry.ts)}
          </span>
        </div>
        <p className="mt-0.5 break-words text-sm text-foreground">
          {entry.message}
        </p>
        {hasDetail && (
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className="mt-1 rounded px-1 text-xs text-accent transition-colors hover:text-accent-strong"
            aria-expanded={expanded}
          >
            {expanded ? "Hide detail" : "Show detail"}
          </button>
        )}
        {expanded && (
          <pre className="tabular mt-2 overflow-x-auto rounded-lg bg-surface-2 p-2 text-xs text-muted">
            {JSON.stringify(entry.raw, null, 2)}
          </pre>
        )}
      </div>
    </div>
  );
}

export default function DecisionTimeline() {
  const [entries, setEntries] = useState<TimelineEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);
  // Read inside the stable fetchEntries closure so the interval (captured once
  // at mount) sees the current data state; without it a transient error after
  // the first load would flip the surface to "unavailable".
  const hasDataRef = useRef(false);

  const fetchEntries = useCallback(async () => {
    try {
      const res = await fetch("/api/timeline?limit=50");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { entries: TimelineEntry[] };
      setEntries(data.entries);
      setError(null);
      setLastUpdated(new Date().toLocaleTimeString());
    } catch {
      setError((prev) => (hasDataRef.current ? prev : "Timeline unavailable."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    hasDataRef.current = entries.length > 0;
  }, [entries.length]);

  useEffect(() => {
    fetchEntries();
    const interval = setInterval(fetchEntries, 30_000);
    return () => clearInterval(interval);
  }, [fetchEntries]);

  const emptyState = (
    <p className="text-sm text-muted">
      No events yet. Activity appears here once agents start running.
    </p>
  );

  return (
    <section aria-label="Decision timeline">
      <SectionTitle
        meta={
          lastUpdated && (
            <span className="text-subtle">updated {lastUpdated}</span>
          )
        }
      >
        Decision timeline
      </SectionTitle>
      <AsyncSurface
        loading={loading}
        empty={entries.length === 0}
        error={error}
        emptyState={emptyState}
        onRetry={() => {
          setLoading(true);
          setError(null);
          fetchEntries();
        }}
        skeleton={
          <div className="flex flex-col gap-3">
            {[...Array(5)].map((_, i) => (
              <div
                key={i}
                className="h-12 animate-pulse rounded-lg bg-surface-2/60"
              />
            ))}
          </div>
        }
      >
        <div className="max-h-96 overflow-y-auto rounded-xl border border-border bg-surface-1 px-4">
          {entries.map((entry) => (
            <TimelineItem key={entry.id} entry={entry} />
          ))}
        </div>
      </AsyncSurface>
    </section>
  );
}
