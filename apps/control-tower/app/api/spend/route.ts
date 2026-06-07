/**
 * Spend API — proxies LiteLLM /spend/tags endpoint.
 * Returns spend by agent for the last 7 days.
 *
 * GET /api/spend?days=7
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-5)
 * Task: T-41
 */
export const dynamic = "force-dynamic";

export interface AgentSpend {
  agent: string;
  model: string;
  tokens_in: number;
  tokens_out: number;
  cost_usd: number;
  daily_budget_usd?: number;
  budget_pct?: number;
}

// Agent daily budgets (in USD) — mirrors the values in council config
const AGENT_BUDGETS: Record<string, number> = {
  triage: 2.0,
  researcher: 3.0,
  coder: 5.0,
  reviewer: 2.0,
  janitor: 1.0,
  liaison: 2.0,
};

function fallbackSpendResponse(days: number): Response {
  const fallback: AgentSpend[] = Object.keys(AGENT_BUDGETS).map((agent) => ({
    agent,
    model: "unknown",
    tokens_in: 0,
    tokens_out: 0,
    cost_usd: 0,
    daily_budget_usd: AGENT_BUDGETS[agent],
    budget_pct: 0,
  }));

  return Response.json({ agents: fallback, days, source: "fallback" });
}

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const days = parseInt(url.searchParams.get("days") ?? "7", 10) || 7;

  const litellmUrl = process.env.LITELLM_BASE_URL ?? "http://litellm:4000";
  const apiKey = process.env.LITELLM_API_KEY;

  const endDate = new Date();
  const startDate = new Date(endDate.getTime() - days * 24 * 60 * 60 * 1000);

  const params = new URLSearchParams({
    start_date: startDate.toISOString().split("T")[0],
    end_date: endDate.toISOString().split("T")[0],
    group_by: "agent_id",
  });

  // Build headers conditionally — LITELLM_API_KEY may be unset in dev/test;
  // sending "Bearer undefined" would be rejected by the proxy and leak info.
  const litellmHeaders: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (apiKey) {
    litellmHeaders["Authorization"] = `Bearer ${apiKey}`;
  }

  let res: Response;
  try {
    res = await fetch(`${litellmUrl}/spend/tags?${params.toString()}`, {
      headers: litellmHeaders,
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    return fallbackSpendResponse(days);
  }

  if (!res.ok) {
    // Return zero-rows for all known agents on LiteLLM error
    // (allows the UI to render even when LiteLLM is down)
    return fallbackSpendResponse(days);
  }

  try {
    // LiteLLM returns [{tag: "agent_id:coder", spend: 0.12, ...}, ...]
    // Normalize to our shape
    const raw = (await res.json()) as {
      tag?: string;
      spend?: number;
      total_tokens?: number;
      prompt_tokens?: number;
      completion_tokens?: number;
      model?: string;
    }[];

    const agentMap = new Map<string, AgentSpend>();

    for (const item of raw) {
      const tagParts = (item.tag ?? "").split(":");
      const agent = tagParts.length >= 2 ? tagParts[1] : "unknown";

      const existing = agentMap.get(agent) ?? {
        agent,
        model: item.model ?? "mixed",
        tokens_in: 0,
        tokens_out: 0,
        cost_usd: 0,
        daily_budget_usd: AGENT_BUDGETS[agent],
      };

      agentMap.set(agent, {
        ...existing,
        tokens_in: existing.tokens_in + (item.prompt_tokens ?? 0),
        tokens_out: existing.tokens_out + (item.completion_tokens ?? 0),
        cost_usd: existing.cost_usd + (item.spend ?? 0),
      });
    }

    // Ensure all known agents appear (even with $0)
    for (const agent of Object.keys(AGENT_BUDGETS)) {
      if (!agentMap.has(agent)) {
        agentMap.set(agent, {
          agent,
          model: "none",
          tokens_in: 0,
          tokens_out: 0,
          cost_usd: 0,
          daily_budget_usd: AGENT_BUDGETS[agent],
          budget_pct: 0,
        });
      }
    }

    const agents: AgentSpend[] = Array.from(agentMap.values())
      .map((s) => ({
        ...s,
        cost_usd: Math.round(s.cost_usd * 10000) / 10000,
        budget_pct:
          s.daily_budget_usd
            ? Math.min(
                Math.round((s.cost_usd / (s.daily_budget_usd * days)) * 100),
                100
              )
            : 0,
      }))
      .sort((a, b) => b.cost_usd - a.cost_usd);

    return Response.json({ agents, days, source: "litellm" });
  } catch (err) {
    return Response.json(
      { error: "Failed to process spend data", detail: String(err) },
      { status: 500 }
    );
  }
}
