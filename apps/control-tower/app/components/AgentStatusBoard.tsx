"use client";

import { useEffect, useRef, useState } from "react";
import type { AgentState, MetricsSnapshot } from "@/lib/metrics-reader";

/**
 * Agent Status Board — shows real-time state of all 6 Council agents.
 * Connects to the SSE endpoint /api/sse and renders a card grid.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-2)
 * Task: T-38
 */

const PLANE_BASE_URL =
  process.env.NEXT_PUBLIC_PLANE_URL ?? "http://localhost:8080";

const STATE_CONFIG: Record<
  AgentState["state"],
  { label: string; badgeClass: string; dotClass: string }
> = {
  idle: {
    label: "idle",
    badgeClass: "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400",
    dotClass: "bg-zinc-400",
  },
  working: {
    label: "working",
    badgeClass: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-400",
    dotClass: "bg-emerald-500 animate-pulse",
  },
  blocked: {
    label: "blocked",
    badgeClass: "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-400",
    dotClass: "bg-amber-500 animate-pulse",
  },
};

function AgentCard({ agent }: { agent: AgentState }) {
  const cfg = STATE_CONFIG[agent.state];
  const issueURL = agent.current_issue
    ? `${PLANE_BASE_URL}/walter-os/issues/${agent.current_issue}`
    : null;

  return (
    <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4 flex flex-col gap-3 shadow-sm">
      <div className="flex items-center justify-between">
        <span className="font-semibold text-sm text-zinc-900 dark:text-zinc-100 capitalize">
          {agent.agent}
        </span>
        <span
          className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${cfg.badgeClass}`}
        >
          <span className={`h-1.5 w-1.5 rounded-full ${cfg.dotClass}`} />
          {cfg.label}
        </span>
      </div>

      <div className="text-xs text-zinc-500 dark:text-zinc-400 min-h-[1.25rem]">
        {agent.current_issue ? (
          issueURL ? (
            <a
              href={issueURL}
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-zinc-700 dark:hover:text-zinc-200 underline underline-offset-2"
            >
              {agent.current_issue}
            </a>
          ) : (
            agent.current_issue
          )
        ) : (
          <span className="italic">no active issue</span>
        )}
      </div>

      {agent.heartbeat_age_seconds !== null && (
        <div className="text-xs text-zinc-400 dark:text-zinc-500">
          heartbeat {Math.round(agent.heartbeat_age_seconds)}s ago
        </div>
      )}
    </div>
  );
}

interface BoardProps {
  sseUrl?: string;
}

export default function AgentStatusBoard({ sseUrl = "/api/sse" }: BoardProps) {
  const [snapshot, setSnapshot] = useState<MetricsSnapshot | null>(null);
  const [connected, setConnected] = useState(false);
  const esRef = useRef<EventSource | null>(null);

  useEffect(() => {
    function connect() {
      const es = new EventSource(sseUrl);
      esRef.current = es;

      es.onopen = () => setConnected(true);

      es.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data) as MetricsSnapshot;
          setSnapshot(data);
          setConnected(true);
        } catch {
          // ignore malformed events
        }
      };

      es.onerror = () => {
        setConnected(false);
        es.close();
        // Reconnect after 5s
        setTimeout(connect, 5000);
      };
    }

    connect();

    return () => {
      esRef.current?.close();
    };
  }, [sseUrl]);

  if (!snapshot) {
    return (
      <section>
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-3">
          Agent Status
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {[...Array(6)].map((_, i) => (
            <div
              key={i}
              className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-900 p-4 h-24 animate-pulse"
            />
          ))}
        </div>
      </section>
    );
  }

  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
          Agent Status
        </h2>
        <span
          className={`text-xs flex items-center gap-1 ${
            connected ? "text-emerald-500" : "text-red-400"
          }`}
        >
          <span
            className={`h-1.5 w-1.5 rounded-full ${
              connected ? "bg-emerald-500" : "bg-red-400"
            }`}
          />
          {connected ? "live" : "disconnected"}
        </span>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {snapshot.agents.map((agent) => (
          <AgentCard key={agent.agent} agent={agent} />
        ))}
      </div>
    </section>
  );
}
