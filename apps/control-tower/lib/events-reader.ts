/**
 * Reader for walter-council JSONL event logs.
 * Reads /var/log/walter-council/events.log (written by alerts.sh, T-8)
 * and /var/log/walter-council/consensus-votes.log (written by run.sh, T-36)
 *
 * Events log format:
 *   {"ts":"2026-05-11T14:00:00Z","tier":"warn","message":"...","context":{}}
 *
 * Consensus log format:
 *   {"ts":"...","task_id":"...","voters":[...],"yes":2,"no":1,"quorum_met":true}
 */

import { readFileSync, existsSync } from "fs";
import * as path from "path";

export type AlertTier = "info" | "warn" | "critical" | "panic";

export interface AlertEvent {
  id: string; // synthetic: ts + index
  ts: string;
  tier: AlertTier;
  message: string;
  context: Record<string, unknown>;
  acknowledged?: boolean;
}

export interface ConsensusVote {
  id: string;
  ts: string;
  task_id: string;
  task_description?: string;
  votes: number;
  yes: number;
  no: number;
  quorum_met: boolean;
  voters: { agent: string; vote: "yes" | "no" | "abstain"; reason: string }[];
}

export interface TimelineEntry {
  id: string;
  ts: string;
  type: "alert" | "consensus";
  tier?: AlertTier;
  message: string;
  agent?: string;
  issue_id?: string;
  raw: Record<string, unknown>;
}

const LOG_DIR =
  process.env.WALTER_COUNCIL_LOG_DIR ?? "/var/log/walter-council";

function readJsonlFile(filePath: string, limit: number): unknown[] {
  if (!existsSync(filePath)) return [];
  try {
    const content = readFileSync(filePath, "utf-8");
    const lines = content
      .split("\n")
      .filter((l) => l.trim())
      .slice(-limit);
    return lines.map((l) => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    }).filter(Boolean);
  } catch {
    return [];
  }
}

export function readRecentEvents(limit = 50): TimelineEntry[] {
  const eventsPath = path.join(LOG_DIR, "events.log");
  const consensusPath = path.join(LOG_DIR, "consensus-votes.log");

  const entries: TimelineEntry[] = [];

  // Parse events.log
  const events = readJsonlFile(eventsPath, limit) as Record<string, unknown>[];
  for (let i = 0; i < events.length; i++) {
    const e = events[i];
    if (!e || typeof e.ts !== "string") continue;
    entries.push({
      id: `evt-${e.ts}-${i}`,
      ts: e.ts as string,
      type: "alert",
      tier: (e.tier as AlertTier) ?? "info",
      message: (e.message as string) ?? "",
      agent: e.context && typeof e.context === "object"
        ? ((e.context as Record<string, unknown>).agent as string | undefined)
        : undefined,
      issue_id: e.context && typeof e.context === "object"
        ? ((e.context as Record<string, unknown>).issue_id as string | undefined)
        : undefined,
      raw: e,
    });
  }

  // Parse consensus-votes.log
  const votes = readJsonlFile(consensusPath, limit) as Record<string, unknown>[];
  for (let i = 0; i < votes.length; i++) {
    const v = votes[i];
    if (!v || typeof v.ts !== "string") continue;
    const quorum = v.quorum_met as boolean;
    entries.push({
      id: `vote-${v.ts}-${i}`,
      ts: v.ts as string,
      type: "consensus",
      tier: quorum ? "info" : "warn",
      message: `Consensus vote for ${v.task_id ?? "unknown task"}: ${
        quorum
          ? `passed (${v.yes}/${v.votes})`
          : `failed (${v.yes}/${v.votes})`
      }`,
      issue_id: v.task_id as string | undefined,
      raw: v,
    });
  }

  // Sort descending by timestamp
  entries.sort((a, b) => b.ts.localeCompare(a.ts));
  return entries.slice(0, limit);
}
