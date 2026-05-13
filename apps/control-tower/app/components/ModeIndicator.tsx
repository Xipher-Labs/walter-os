"use client";

import { useEffect, useState, useCallback } from "react";
import type { ModeState } from "@/app/api/mode/route";
import type { ConsensusStatus } from "@/app/api/consensus-status/route";

/**
 * Mode Indicator — shows consensus mode status with toggle and live stats.
 * Reads from /api/mode + /api/consensus-status.
 * Refreshes every 60 seconds.
 *
 * When consensus mode is ON: shows mini-dashboard with approved/failed/pending.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6, Improvement 9 AC-6)
 * Tasks: T-43, T-54
 */

export default function ModeIndicator() {
  const [mode, setMode] = useState<ModeState | null>(null);
  const [stats, setStats] = useState<ConsensusStatus | null>(null);
  const [toggling, setToggling] = useState(false);

  const fetchMode = useCallback(async () => {
    try {
      const [modeRes, statsRes] = await Promise.all([
        fetch("/api/mode"),
        fetch("/api/consensus-status"),
      ]);
      if (modeRes.ok) {
        const data = (await modeRes.json()) as ModeState;
        setMode(data);
      }
      if (statsRes.ok) {
        const data = (await statsRes.json()) as ConsensusStatus;
        setStats(data);
      }
    } catch {
      // keep stale
    }
  }, []);

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
        // Refresh stats after toggle
        setTimeout(fetchMode, 1000);
      }
    } finally {
      setToggling(false);
    }
  };

  if (!mode) {
    return (
      <div className="h-10 bg-zinc-100 dark:bg-zinc-800 rounded-xl animate-pulse" />
    );
  }

  return (
    <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
            Consensus Mode
          </span>
          <span
            className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${
              mode.consensus
                ? "bg-violet-100 text-violet-700 dark:bg-violet-900/40 dark:text-violet-300"
                : "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400"
            }`}
          >
            <span
              className={`h-1.5 w-1.5 rounded-full ${
                mode.consensus
                  ? "bg-violet-500 animate-pulse"
                  : "bg-zinc-400"
              }`}
            />
            {mode.consensus ? "ON" : "OFF"}
          </span>
        </div>

        <button
          onClick={handleToggle}
          disabled={toggling}
          className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${
            mode.consensus
              ? "bg-zinc-100 hover:bg-zinc-200 text-zinc-700 dark:bg-zinc-800 dark:hover:bg-zinc-700 dark:text-zinc-300"
              : "bg-violet-100 hover:bg-violet-200 text-violet-700 dark:bg-violet-900/40 dark:hover:bg-violet-900/60 dark:text-violet-300"
          } disabled:opacity-50 disabled:cursor-not-allowed`}
        >
          {toggling ? "..." : mode.consensus ? "Turn off" : "Turn on"}
        </button>
      </div>

      {mode.consensus && mode.since && (
        <p className="text-xs text-zinc-400 dark:text-zinc-500">
          Active since {new Date(mode.since).toLocaleString()}
          {" · "}threshold: {mode.voting_threshold}
        </p>
      )}

      {/* Consensus stats mini-dashboard — only when mode is ON */}
      {mode.consensus && stats && (
        <div className="grid grid-cols-3 gap-2 pt-2 border-t border-zinc-100 dark:border-zinc-800">
          <div className="text-center">
            <div className="text-lg font-bold text-emerald-600 dark:text-emerald-400">
              {stats.approved}
            </div>
            <div className="text-xs text-zinc-400 dark:text-zinc-500">approved</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-bold text-amber-600 dark:text-amber-400">
              {stats.pending}
            </div>
            <div className="text-xs text-zinc-400 dark:text-zinc-500">pending</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-bold text-red-500 dark:text-red-400">
              {stats.failed}
            </div>
            <div className="text-xs text-zinc-400 dark:text-zinc-500">awaiting human</div>
          </div>
        </div>
      )}
    </div>
  );
}
