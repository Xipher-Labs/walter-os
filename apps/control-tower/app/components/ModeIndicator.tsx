"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import type { ModeState } from "@/app/api/mode/route";
import type { ConsensusStatus } from "@/app/api/consensus-status/route";
import { Panel } from "@/app/components/ui/Panel";
import AsyncSurface from "@/app/components/ui/AsyncSurface";

/**
 * Mode Indicator — consensus mode status, toggle, and live stats. Reads
 * /api/mode + /api/consensus-status, refreshes every 60s. Re-skinned to tokens
 * (D-2); consensus uses its own --consensus token (distinct from the ops
 * accent) so "deliberation" reads as its own concept.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6, Improvement 9 AC-6)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Tasks: T-43, T-54
 */

export default function ModeIndicator() {
  const [mode, setMode] = useState<ModeState | null>(null);
  const [stats, setStats] = useState<ConsensusStatus | null>(null);
  const [toggling, setToggling] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Read inside fetchMode so a transient failure after the first successful
  // load keeps the last good mode on screen instead of flipping to the error
  // state (the surface only shows the error before we ever have data).
  const hasDataRef = useRef(false);

  const fetchMode = useCallback(async () => {
    try {
      const [modeRes, statsRes] = await Promise.all([
        fetch("/api/mode"),
        fetch("/api/consensus-status"),
      ]);
      if (!modeRes.ok) throw new Error(`HTTP ${modeRes.status}`);
      const data = (await modeRes.json()) as ModeState;
      setMode(data);
      setError(null);
      if (statsRes.ok) {
        const statsData = (await statsRes.json()) as ConsensusStatus;
        setStats(statsData);
      }
    } catch {
      setError((prev) => (hasDataRef.current ? prev : "Mode unavailable."));
    }
  }, []);

  useEffect(() => {
    hasDataRef.current = mode !== null;
  }, [mode]);

  useEffect(() => {
    fetchMode();
    const interval = setInterval(fetchMode, 60_000);
    return () => clearInterval(interval);
  }, [fetchMode]);

  const handleToggle = async () => {
    if (!mode || toggling) return;
    setToggling(true);
    try {
      const res = await fetch("/api/mode", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: mode.consensus ? "off" : "on" }),
      });
      if (res.ok) {
        const newMode = (await res.json()) as ModeState;
        setMode(newMode);
        setTimeout(fetchMode, 1000);
      }
    } finally {
      setToggling(false);
    }
  };

  const on = mode?.consensus ?? false;

  const skeleton = (
    <div className="h-full min-h-[5rem] animate-pulse rounded-xl border border-border bg-surface-1" />
  );

  return (
    <AsyncSurface
      loading={!mode}
      error={error}
      onRetry={() => {
        setError(null);
        fetchMode();
      }}
      skeleton={skeleton}
    >
    <Panel tone="raised" className="flex h-full flex-col gap-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-foreground">
            Consensus mode
          </span>
          <span
            className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${
              on
                ? "bg-consensus-bg text-consensus-fg"
                : "bg-status-idle-bg text-status-idle-fg"
            }`}
          >
            <span
              aria-hidden="true"
              className={`h-1.5 w-1.5 rounded-full bg-current ${
                on ? "status-pulse" : ""
              }`}
            />
            {on ? "on" : "off"}
          </span>
        </div>

        <button
          type="button"
          onClick={handleToggle}
          disabled={toggling}
          className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${
            on
              ? "bg-surface-1 text-muted hover:bg-surface-2 hover:text-foreground"
              : "bg-consensus-bg text-consensus-fg hover:brightness-110"
          }`}
        >
          {toggling ? "…" : on ? "Turn off" : "Turn on"}
        </button>
      </div>

      {on && mode?.since && (
        <p className="text-xs text-subtle">
          Active since {new Date(mode.since).toLocaleString()} · threshold{" "}
          {mode.voting_threshold}
        </p>
      )}

      {on && stats && (
        <div className="mt-auto grid grid-cols-3 gap-2 border-t border-border pt-3">
          <div className="text-center">
            <div className="tabular text-lg font-bold text-status-ok-fg">
              {stats.approved}
            </div>
            <div className="text-2xs text-subtle">approved</div>
          </div>
          <div className="text-center">
            <div className="tabular text-lg font-bold text-status-warn-fg">
              {stats.pending}
            </div>
            <div className="text-2xs text-subtle">pending</div>
          </div>
          <div className="text-center">
            <div className="tabular text-lg font-bold text-status-critical-fg">
              {stats.failed}
            </div>
            <div className="text-2xs text-subtle">awaiting human</div>
          </div>
        </div>
      )}
    </Panel>
    </AsyncSurface>
  );
}
