"use client";

import { useEffect, useState, useCallback } from "react";
import type { AgentSpend } from "@/app/api/spend/route";

/**
 * Cost Dashboard — shows LiteLLM spend per agent for the last 7 days.
 * Includes a budget percentage bar per agent.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-5)
 * Task: T-41
 */

function BudgetBar({ pct }: { pct: number }) {
  const color =
    pct >= 90
      ? "bg-red-500"
      : pct >= 70
      ? "bg-amber-400"
      : "bg-emerald-500";

  return (
    <div className="w-24 h-1.5 bg-zinc-200 dark:bg-zinc-700 rounded-full overflow-hidden">
      <div
        className={`h-full rounded-full transition-all ${color}`}
        style={{ width: `${Math.min(pct, 100)}%` }}
      />
    </div>
  );
}

export default function CostDashboard() {
  const [agents, setAgents] = useState<AgentSpend[]>([]);
  const [loading, setLoading] = useState(true);
  const [days, setDays] = useState(7);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);
  const [source, setSource] = useState<string>("...");

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
      setLastUpdated(new Date().toLocaleTimeString());
    } catch {
      // keep stale data
    } finally {
      setLoading(false);
    }
  }, [days]);

  useEffect(() => {
    fetchSpend();
  }, [fetchSpend]);

  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
          Cost ({days}d)
        </h2>
        <div className="flex items-center gap-3">
          {source === "fallback" && (
            <span className="text-xs text-amber-500">LiteLLM unreachable</span>
          )}
          <select
            value={days}
            onChange={(e) => setDays(parseInt(e.target.value, 10))}
            className="text-xs border border-zinc-200 dark:border-zinc-700 rounded px-2 py-0.5 bg-white dark:bg-zinc-900 text-zinc-700 dark:text-zinc-300"
          >
            <option value={1}>1d</option>
            <option value={7}>7d</option>
            <option value={30}>30d</option>
          </select>
          {lastUpdated && (
            <span className="text-xs text-zinc-400 dark:text-zinc-500">
              {lastUpdated}
            </span>
          )}
        </div>
      </div>

      <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 overflow-hidden">
        {loading ? (
          <div className="p-4 flex flex-col gap-3">
            {[...Array(6)].map((_, i) => (
              <div
                key={i}
                className="h-8 bg-zinc-100 dark:bg-zinc-800 rounded animate-pulse"
              />
            ))}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-900">
                <th className="text-left py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Agent
                </th>
                <th className="text-right py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Tokens in
                </th>
                <th className="text-right py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Tokens out
                </th>
                <th className="text-right py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Cost (USD)
                </th>
                <th className="text-right py-2 px-4 text-xs font-medium text-zinc-500 dark:text-zinc-400">
                  Budget
                </th>
              </tr>
            </thead>
            <tbody>
              {agents.map((agent, i) => (
                <tr
                  key={agent.agent}
                  className={`border-b border-zinc-100 dark:border-zinc-800 ${
                    i % 2 === 0
                      ? "bg-white dark:bg-zinc-950"
                      : "bg-zinc-50/50 dark:bg-zinc-900/50"
                  }`}
                >
                  <td className="py-2 px-4 capitalize text-zinc-900 dark:text-zinc-100 font-medium">
                    {agent.agent}
                  </td>
                  <td className="py-2 px-4 text-right text-zinc-600 dark:text-zinc-400 font-mono text-xs">
                    {agent.tokens_in.toLocaleString()}
                  </td>
                  <td className="py-2 px-4 text-right text-zinc-600 dark:text-zinc-400 font-mono text-xs">
                    {agent.tokens_out.toLocaleString()}
                  </td>
                  <td className="py-2 px-4 text-right text-zinc-900 dark:text-zinc-100 font-mono text-xs">
                    ${agent.cost_usd.toFixed(4)}
                  </td>
                  <td className="py-2 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <span className="text-xs text-zinc-500 dark:text-zinc-400 w-8 text-right">
                        {agent.budget_pct ?? 0}%
                      </span>
                      <BudgetBar pct={agent.budget_pct ?? 0} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="bg-zinc-50 dark:bg-zinc-900 border-t border-zinc-200 dark:border-zinc-700">
                <td
                  colSpan={3}
                  className="py-2 px-4 text-xs text-zinc-500 dark:text-zinc-400 font-medium"
                >
                  Total
                </td>
                <td className="py-2 px-4 text-right text-zinc-900 dark:text-zinc-100 font-mono text-xs font-bold">
                  $
                  {agents
                    .reduce((s, a) => s + a.cost_usd, 0)
                    .toFixed(4)}
                </td>
                <td />
              </tr>
            </tfoot>
          </table>
        )}
      </div>
    </section>
  );
}
