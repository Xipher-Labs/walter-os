"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import type { AgentSpend } from "@/app/api/spend/route";
import { SectionTitle, Panel } from "@/app/components/ui/Panel";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import StatusDot from "@/app/components/ui/StatusDot";
import type { StatusKind } from "@/app/components/ui/status";

/**
 * Cost Dashboard — LiteLLM spend per agent with a budget bar. Re-skinned to
 * tokens (D-2) and the shared status language (D-4): the budget bar colour
 * comes from the same ok/warn/critical tokens as everything else.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-5)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-41
 */

function budgetStatus(pct: number): StatusKind {
  if (pct >= 90) return "critical";
  if (pct >= 70) return "warn";
  return "ok";
}

function BudgetBar({ pct }: { pct: number }) {
  const status = budgetStatus(pct);
  const fg =
    status === "critical"
      ? "bg-status-critical-fg"
      : status === "warn"
        ? "bg-status-warn-fg"
        : "bg-status-ok-fg";
  return (
    <div
      className="h-1.5 w-24 overflow-hidden rounded-full bg-surface-2"
      role="meter"
      aria-valuenow={Math.round(pct)}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-label={`Budget used: ${Math.round(pct)}%`}
    >
      <div
        className={`h-full rounded-full transition-all ${fg}`}
        style={{ width: `${Math.min(pct, 100)}%` }}
      />
    </div>
  );
}

export default function CostDashboard() {
  const [agents, setAgents] = useState<AgentSpend[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [days, setDays] = useState(7);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);
  const [source, setSource] = useState<string>("...");
  // Read inside the stable fetchSpend closure so a transient error after the
  // first successful load keeps stale data instead of flipping to the error
  // state. fetchSpend depends only on `days`, so the closure no longer goes
  // stale on the empty mount-time agents list.
  const hasDataRef = useRef(false);

  const fetchSpend = useCallback(async () => {
    try {
      const res = await fetch(`/api/spend?days=${days}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as {
        agents: AgentSpend[];
        days: number;
        source: string;
      };
      setAgents(data.agents);
      setSource(data.source);
      setError(null);
      setLastUpdated(new Date().toLocaleTimeString());
    } catch {
      setError((prev) => (hasDataRef.current ? prev : "Spend data unavailable."));
    } finally {
      setLoading(false);
    }
  }, [days]);

  useEffect(() => {
    hasDataRef.current = agents.length > 0;
  }, [agents.length]);

  useEffect(() => {
    setLoading(true);
    fetchSpend();
  }, [fetchSpend]);

  const total = agents.reduce((s, a) => s + a.cost_usd, 0);

  const skeleton = (
    <Panel padded={false}>
      <div className="flex flex-col gap-3 p-4">
        {[...Array(6)].map((_, i) => (
          <div
            key={i}
            className="h-8 animate-pulse rounded-lg bg-surface-2/60"
          />
        ))}
      </div>
    </Panel>
  );

  return (
    <section aria-label="Agent cost">
      <SectionTitle
        meta={
          <>
            {source === "fallback" && (
              <StatusDot
                status="warn"
                label="LiteLLM unreachable"
                size="sm"
                srOnlyLabel={false}
                pulse={false}
              />
            )}
            <label className="sr-only" htmlFor="cost-days">
              Time window
            </label>
            <select
              id="cost-days"
              value={days}
              onChange={(e) => setDays(parseInt(e.target.value, 10))}
              className="rounded-md border border-border bg-surface-1 px-2 py-0.5 text-xs text-foreground transition-colors hover:border-border-strong"
            >
              <option value={1}>1d</option>
              <option value={7}>7d</option>
              <option value={30}>30d</option>
            </select>
            {lastUpdated && <span className="text-subtle">{lastUpdated}</span>}
          </>
        }
      >
        Spend · {days}d
      </SectionTitle>
      <AsyncSurface
        loading={loading}
        error={error}
        onRetry={() => {
          setLoading(true);
          setError(null);
          fetchSpend();
        }}
        skeleton={skeleton}
      >
        <Panel padded={false} className="overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-surface-2/50 text-2xs uppercase tracking-wide text-subtle">
                <th className="px-4 py-2 text-left font-medium">Agent</th>
                <th className="px-4 py-2 text-right font-medium">Tokens in</th>
                <th className="px-4 py-2 text-right font-medium">Tokens out</th>
                <th className="px-4 py-2 text-right font-medium">Cost</th>
                <th className="px-4 py-2 text-right font-medium">Budget</th>
              </tr>
            </thead>
            <tbody>
              {agents.map((agent) => (
                <tr
                  key={agent.agent}
                  className="border-b border-border/60 last:border-0 transition-colors hover:bg-surface-2/40"
                >
                  <td className="px-4 py-2.5 font-medium capitalize text-foreground">
                    {agent.agent}
                  </td>
                  <td className="tabular px-4 py-2.5 text-right text-xs text-muted">
                    {agent.tokens_in.toLocaleString()}
                  </td>
                  <td className="tabular px-4 py-2.5 text-right text-xs text-muted">
                    {agent.tokens_out.toLocaleString()}
                  </td>
                  <td className="tabular px-4 py-2.5 text-right text-xs font-medium text-foreground">
                    ${agent.cost_usd.toFixed(4)}
                  </td>
                  <td className="px-4 py-2.5">
                    <div className="flex items-center justify-end gap-2">
                      <span className="tabular w-8 text-right text-xs text-muted">
                        {agent.budget_pct ?? 0}%
                      </span>
                      <BudgetBar pct={agent.budget_pct ?? 0} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t border-border bg-surface-2/50">
                <td
                  colSpan={3}
                  className="px-4 py-2.5 text-xs font-medium text-muted"
                >
                  Total
                </td>
                <td className="tabular px-4 py-2.5 text-right text-xs font-bold text-foreground">
                  ${total.toFixed(4)}
                </td>
                <td />
              </tr>
            </tfoot>
          </table>
        </Panel>
      </AsyncSurface>
    </section>
  );
}
