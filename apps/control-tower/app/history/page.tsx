"use client";

import { useState, useEffect, useCallback } from "react";
import type { ChatSession } from "@/server/council/history";
import Link from "next/link";

/**
 * Conversation History page — searchable archive of Council Chat sessions.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-9 implied)
 * Task: T-47
 */

function SessionCard({ session }: { session: ChatSession }) {
  const [expanded, setExpanded] = useState(false);

  const hasFull =
    !!session.round1?.length && !!session.round2?.length && !!session.synthesis;
  const hasPartial = !!session.round1?.length && !session.round2?.length;

  return (
    <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 overflow-hidden">
      <button
        className="w-full text-left p-4 hover:bg-zinc-50 dark:hover:bg-zinc-800/50 transition-colors"
        onClick={() => setExpanded((v) => !v)}
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-zinc-900 dark:text-zinc-100 line-clamp-2">
              {session.message}
            </p>
            <div className="flex items-center gap-2 mt-1.5">
              <span className="text-xs text-zinc-400">
                {new Date(session.ts).toLocaleString()}
              </span>
              <span
                className={`text-xs rounded-full px-2 py-0.5 ${
                  session.session_type === "ideation"
                    ? "bg-violet-100 text-violet-600 dark:bg-violet-900/40 dark:text-violet-300"
                    : "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400"
                }`}
              >
                {session.session_type}
              </span>
              {hasFull && (
                <span className="text-xs text-emerald-600 dark:text-emerald-400">
                  complete
                </span>
              )}
              {hasPartial && (
                <span className="text-xs text-amber-500">R1 only</span>
              )}
            </div>
          </div>
          <span className="text-zinc-400 text-sm flex-shrink-0">
            {expanded ? "▴" : "▾"}
          </span>
        </div>
      </button>

      {expanded && (
        <div className="border-t border-zinc-100 dark:border-zinc-800 p-4 flex flex-col gap-4">
          {session.synthesis && (
            <div>
              <h4 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-2">
                Synthesis
              </h4>
              <p className="text-sm text-zinc-700 dark:text-zinc-300">
                {session.synthesis.summary}
              </p>
              {session.synthesis.recommended_path && (
                <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-2">
                  <span className="font-medium">Path: </span>
                  {session.synthesis.recommended_path}
                </p>
              )}
            </div>
          )}

          {session.round1 && (
            <div>
              <h4 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-2">
                Round 1 ({session.round1.length} responses)
              </h4>
              <div className="flex flex-wrap gap-2">
                {session.round1.map((r) => (
                  <span
                    key={r.agent}
                    className="text-xs bg-zinc-100 dark:bg-zinc-800 rounded px-2 py-0.5 text-zinc-600 dark:text-zinc-400"
                  >
                    {r.agent}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default function HistoryPage() {
  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [total, setTotal] = useState(0);

  const fetchHistory = useCallback(
    async (q: string) => {
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
      } finally {
        setLoading(false);
      }
    },
    []
  );

  useEffect(() => {
    fetchHistory("");
  }, [fetchHistory]);

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(() => fetchHistory(query), 300);
    return () => clearTimeout(timer);
  }, [query, fetchHistory]);

  return (
    <main className="min-h-screen bg-zinc-50 dark:bg-zinc-950">
      <nav className="border-b border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-6 py-3">
        <div className="max-w-4xl mx-auto flex items-center gap-4 text-sm">
          <Link
            href="/"
            className="text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100"
          >
            ← Dashboard
          </Link>
          <span className="text-zinc-300 dark:text-zinc-600">|</span>
          <span className="font-semibold text-zinc-900 dark:text-zinc-100">
            History
          </span>
        </div>
      </nav>

      <div className="max-w-4xl mx-auto p-6">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-100">
              Conversation History
            </h1>
            <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
              {total} sessions recorded
            </p>
          </div>

          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search sessions..."
            className="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 px-3 py-2 text-sm text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-violet-500 w-64"
          />
        </div>

        {loading ? (
          <div className="flex flex-col gap-3">
            {[...Array(5)].map((_, i) => (
              <div
                key={i}
                className="h-16 bg-zinc-100 dark:bg-zinc-800 rounded-xl animate-pulse"
              />
            ))}
          </div>
        ) : sessions.length === 0 ? (
          <p className="text-sm text-zinc-400 italic">
            {query ? `No sessions matching "${query}".` : "No sessions yet."}
          </p>
        ) : (
          <div className="flex flex-col gap-3">
            {sessions.map((s) => (
              <SessionCard key={s.session_id} session={s} />
            ))}
          </div>
        )}
      </div>
    </main>
  );
}
