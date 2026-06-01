"use client";

import { useState, useEffect, useCallback } from "react";
import type { ChatSession } from "@/server/council/history";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import StatusBadge from "@/app/components/ui/StatusBadge";
import { Panel } from "@/app/components/ui/Panel";

/**
 * HistoryClient owns only the interactive history list. The page shell stays
 * server-rendered so the shared header can compose the version badge without
 * pulling server-only env reads into a client bundle.
 */

function SessionCard({ session }: { session: ChatSession }) {
  const [expanded, setExpanded] = useState(false);

  const hasFull =
    !!session.round1?.length && !!session.round2?.length && !!session.synthesis;
  const hasPartial = !!session.round1?.length && !session.round2?.length;

  return (
    <Panel padded={false} className="overflow-hidden">
      <button
        type="button"
        className="w-full p-4 text-left transition-colors hover:bg-surface-2/40"
        onClick={() => setExpanded((v) => !v)}
        aria-expanded={expanded}
      >
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <p className="line-clamp-2 text-sm font-medium text-foreground">
              {session.message}
            </p>
            <div className="mt-1.5 flex flex-wrap items-center gap-2">
              <span className="tabular text-xs text-subtle">
                {new Date(session.ts).toLocaleString()}
              </span>
              {session.session_type === "ideation" ? (
                <StatusBadge status="info" label="ideation" pulse={false} />
              ) : (
                <span className="rounded-full bg-status-idle-bg px-2 py-0.5 text-xs text-status-idle-fg">
                  {session.session_type}
                </span>
              )}
              {hasFull && (
                <StatusBadge status="ok" label="complete" pulse={false} />
              )}
              {hasPartial && (
                <StatusBadge status="warn" label="R1 only" pulse={false} />
              )}
            </div>
          </div>
          <span aria-hidden="true" className="shrink-0 text-sm text-subtle">
            {expanded ? "▴" : "▾"}
          </span>
        </div>
      </button>

      {expanded && (
        <div className="flex flex-col gap-4 border-t border-border p-4">
          {session.synthesis && (
            <div>
              <h4 className="mb-2 text-sm font-semibold text-foreground">
                Synthesis
              </h4>
              <p className="text-sm text-muted">{session.synthesis.summary}</p>
              {session.synthesis.recommended_path && (
                <p className="mt-2 text-sm text-muted">
                  <span className="font-medium text-foreground">Path: </span>
                  {session.synthesis.recommended_path}
                </p>
              )}
            </div>
          )}

          {session.round1 && (
            <div>
              <h4 className="mb-2 text-sm font-semibold text-foreground">
                Round 1 ({session.round1.length} responses)
              </h4>
              <div className="flex flex-wrap gap-2">
                {session.round1.map((r) => (
                  <span
                    key={r.agent}
                    className="rounded-md bg-surface-2 px-2 py-0.5 text-xs text-muted"
                  >
                    {r.agent}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </Panel>
  );
}

export default function HistoryClient() {
  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [total, setTotal] = useState(0);

  const fetchHistory = useCallback(async (q: string) => {
    setLoading(true);
    try {
      const params = new URLSearchParams({ limit: "50" });
      if (q) params.set("q", q);
      const res = await fetch(`/api/history?${params.toString()}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as {
        sessions: ChatSession[];
        total: number;
      };
      setSessions(data.sessions);
      setTotal(data.total);
      setError(null);
    } catch {
      setError("History unavailable.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchHistory("");
  }, [fetchHistory]);

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(() => fetchHistory(query), 300);
    return () => clearTimeout(timer);
  }, [query, fetchHistory]);

  return (
    <>
      <header className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-foreground">
            Conversation History
          </h1>
          <p className="tabular mt-1 text-sm text-muted">
            {total} sessions recorded
          </p>
        </div>

        <label className="block">
          <span className="sr-only">Search sessions</span>
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search sessions..."
            className="w-64 rounded-lg border border-border bg-surface-1 px-3 py-2 text-sm text-foreground placeholder:text-subtle transition-colors hover:border-border-strong"
          />
        </label>
      </header>

      <AsyncSurface
        loading={loading}
        empty={sessions.length === 0}
        error={error}
        onRetry={() => fetchHistory(query)}
        emptyState={
          <p className="text-sm text-muted">
            {query ? `No sessions matching "${query}".` : "No sessions yet."}
          </p>
        }
        skeleton={
          <div className="flex flex-col gap-3">
            {[...Array(5)].map((_, i) => (
              <div
                key={i}
                className="h-16 animate-pulse rounded-xl bg-surface-2/60"
              />
            ))}
          </div>
        }
      >
        <div className="flex flex-col gap-3">
          {sessions.map((s) => (
            <SessionCard key={s.session_id} session={s} />
          ))}
        </div>
      </AsyncSurface>
    </>
  );
}
