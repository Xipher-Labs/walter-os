/**
 * Metrics reader for walter-council Prometheus textfile output.
 * Reads /var/lib/walter-council/metrics.prom (written by metrics.sh, T-1)
 * and parses agent state + heartbeat age.
 *
 * Format: Prometheus text exposition format (lines like:
 *   walter_council_agent_state{agent="coder",state="working"} 1 1234567890123
 * )
 */

import { readFileSync, existsSync } from "fs";
import * as path from "path";

export interface AgentState {
  agent: string;
  state: "idle" | "working" | "blocked";
  current_issue: string | null;
  heartbeat_age_seconds: number | null;
  since: string | null;
}

export interface MetricsSnapshot {
  agents: AgentState[];
  timestamp: string;
}

const KNOWN_AGENTS = [
  "triage",
  "researcher",
  "coder",
  "reviewer",
  "janitor",
  "liaison",
] as const;

const DATA_DIR =
  process.env.WALTER_COUNCIL_DATA_DIR ?? "/var/lib/walter-council";

/**
 * Parse a Prometheus label string like:
 *   agent="coder",state="working"
 * into a Record<string, string>.
 */
export function parseLabels(labelStr: string): Record<string, string> {
  const result: Record<string, string> = {};
  const pattern = /(\w+)="([^"]*)"/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(labelStr)) !== null) {
    result[match[1]] = match[2];
  }
  return result;
}

/**
 * Parse a Prometheus metrics file and extract all metric lines.
 * Returns a map of metric_name+labels → value.
 */
export function parseMetricsFile(
  content: string
): Map<string, { labels: Record<string, string>; value: number }[]> {
  const result = new Map<
    string,
    { labels: Record<string, string>; value: number }[]
  >();

  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    // Format: metric_name{labels} value [timestamp]
    const match = line.match(/^(\w+)\{([^}]*)\}\s+([\d.e+-]+)/);
    if (!match) {
      // No labels: metric_name value
      const noLabel = line.match(/^(\w+)\s+([\d.e+-]+)/);
      if (noLabel) {
        const name = noLabel[1];
        const value = parseFloat(noLabel[2]);
        if (!result.has(name)) result.set(name, []);
        result.get(name)!.push({ labels: {}, value });
      }
      continue;
    }

    const name = match[1];
    const labels = parseLabels(match[2]);
    const value = parseFloat(match[3]);
    if (!result.has(name)) result.set(name, []);
    result.get(name)!.push({ labels, value });
  }

  return result;
}

/**
 * Read the metrics.prom file and return a snapshot of agent states.
 * If the file doesn't exist, returns all agents as idle with null heartbeat.
 */
export function readMetricsSnapshot(): MetricsSnapshot {
  const metricsPath = path.join(DATA_DIR, "metrics.prom");
  const timestamp = new Date().toISOString();

  const defaultAgents: AgentState[] = KNOWN_AGENTS.map((agent) => ({
    agent,
    state: "idle",
    current_issue: null,
    heartbeat_age_seconds: null,
    since: null,
  }));

  if (!existsSync(metricsPath)) {
    return { agents: defaultAgents, timestamp };
  }

  let content: string;
  try {
    content = readFileSync(metricsPath, "utf-8");
  } catch {
    return { agents: defaultAgents, timestamp };
  }

  const metrics = parseMetricsFile(content);
  const stateMetrics = metrics.get("walter_council_agent_state") ?? [];
  const heartbeatMetrics =
    metrics.get("walter_council_heartbeat_age_seconds") ?? [];

  const agentMap = new Map<string, AgentState>(
    KNOWN_AGENTS.map((agent) => [
      agent,
      {
        agent,
        state: "idle" as const,
        current_issue: null,
        heartbeat_age_seconds: null,
        since: null,
      },
    ])
  );

  for (const entry of stateMetrics) {
    const agent = entry.labels.agent;
    if (!agent) continue;
    const state = entry.labels.state as AgentState["state"];
    if (entry.value === 1 && agentMap.has(agent)) {
      const existing = agentMap.get(agent)!;
      agentMap.set(agent, { ...existing, state });
    }
  }

  for (const entry of heartbeatMetrics) {
    const agent = entry.labels.agent;
    if (!agent || !agentMap.has(agent)) continue;
    const existing = agentMap.get(agent)!;
    agentMap.set(agent, {
      ...existing,
      heartbeat_age_seconds: entry.value,
    });
  }

  return {
    agents: Array.from(agentMap.values()),
    timestamp,
  };
}
