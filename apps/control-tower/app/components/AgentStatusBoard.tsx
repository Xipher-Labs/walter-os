"use client";

import { useEffect, useRef, useState } from "react";
import type { AgentState, MetricsSnapshot } from "@/lib/metrics-reader";
import StatusBadge from "@/app/components/ui/StatusBadge";
import StatusDot from "@/app/components/ui/StatusDot";
import { SectionTitle } from "@/app/components/ui/Panel";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import type { StatusKind } from "@/app/components/ui/status";

/**
 * Agent Status Board — real-time state of the 6 Council agents over SSE.
 * Re-skinned to the shared status language (D-4) and token surfaces (D-2).
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-2)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-38
 */

const PLANE_BASE_URL =
  process.env.NEXT_PUBLIC_PLANE_URL ?? "http://localhost:8080";

function AgentCard({ agent }: { agent: AgentState }) {
  const status = agent.state as StatusKind;
  const issueURL = agent.current_issue
    ? `${PLANE_BASE_URL}/walter-os/issues/${agent.current_issue}`
    : null;

  return (
    <div className="flex flex-col gap-3 rounded-xl border border-border bg-surface-1 p-4 transition-colors hover:border-border-strong">
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-semibold capitalize text-foreground">
          {agent.agent}
        </span>
        <StatusBadge status={status} />
      </div>

      <div className="min-h-[1.25rem] text-xs text-muted">
        {agent.current_issue ? (
          issueURL ? (
            <a
              href={issueURL}
              target="_blank"
              rel="noopener noreferrer"
              className="text-accent underline decoration-accent/40 underline-offset-2 transition-colors hover:decoration-accent"
            >
              {agent.current_issue}
            </a>
          ) : (
            agent.current_issue
          )
        ) : (
          <span className="text-subtle">no active issue</span>
        )}
      </div>

      {agent.heartbeat_age_seconds !== null && (
        <div className="tabular text-2xs text-subtle">
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
  const reconnectRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    // `mounted` guards every async callback so a reconnect timer or a late
    // SSE event that fires after unmount can never call setState or open a new
    // EventSource on a dead component.
    let mounted = true;

    function connect() {
      if (!mounted) return;
      const es = new EventSource(sseUrl);
      esRef.current = es;

      es.onopen = () => {
        if (mounted) setConnected(true);
      };

      es.onmessage = (event) => {
        if (!mounted) return;
        try {
          const data = JSON.parse(event.data) as MetricsSnapshot;
          setSnapshot(data);
          setConnected(true);
        } catch {
          // ignore malformed events
        }
      };

      es.onerror = () => {
        es.close();
        if (!mounted) return;
        setConnected(false);
        // Reconnect after 5s; the handle is tracked so cleanup can cancel a
        // pending reconnect on unmount.
        reconnectRef.current = setTimeout(connect, 5000);
      };
    }

    connect();

    return () => {
      mounted = false;
      if (reconnectRef.current) {
        clearTimeout(reconnectRef.current);
        reconnectRef.current = null;
      }
      esRef.current?.close();
      esRef.current = null;
    };
  }, [sseUrl]);

  const skeleton = (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
      {[...Array(6)].map((_, i) => (
        <div
          key={i}
          className="h-24 animate-pulse rounded-xl border border-border bg-surface-1"
        />
      ))}
    </div>
  );

  return (
    <section aria-label="Agent status">
      <SectionTitle
        meta={
          <StatusDot
            status={connected ? "ok" : "critical"}
            label={connected ? "live" : "disconnected"}
            size="sm"
            srOnlyLabel={false}
            pulse={connected}
          />
        }
      >
        Agents
      </SectionTitle>
      <AsyncSurface loading={!snapshot} skeleton={skeleton}>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {snapshot?.agents.map((agent) => (
            <AgentCard key={agent.agent} agent={agent} />
          ))}
        </div>
      </AsyncSurface>
    </section>
  );
}
