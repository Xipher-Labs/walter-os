/**
 * Consensus Status API — reads mode.json + consensus-votes.log.
 * Returns {mode_on, since, approved, failed, pending}.
 *
 * GET /api/consensus-status
 *
 * Refs: docs/specs/walter-council-v2.md (Improvement 9, AC-6)
 * Task: T-54
 */
import { readFileSync, existsSync } from "fs";
import * as path from "path";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const CONFIG_DIR =
  process.env.WALTER_CONFIG_DIR ?? "/var/lib/walter-os/control-tower";
const LOG_DIR = process.env.WALTER_COUNCIL_LOG_DIR ?? "/var/log/walter-council";

export interface ConsensusStatus {
  mode_on: boolean;
  since: string | null;
  voting_threshold: number;
  approved: number;
  failed: number;
  pending: number;
}

function readModeJson(): { consensus: boolean; since?: string; voting_threshold?: number } {
  const modePath = path.join(CONFIG_DIR, "mode.json");
  if (!existsSync(modePath)) return { consensus: false };
  try {
    return JSON.parse(readFileSync(modePath, "utf-8")) as {
      consensus: boolean;
      since?: string;
      voting_threshold?: number;
    };
  } catch {
    return { consensus: false };
  }
}

function readConsensusStats(since: string | null): { approved: number; failed: number; pending: number } {
  const votesPath = path.join(LOG_DIR, "consensus-votes.log");
  if (!existsSync(votesPath)) return { approved: 0, failed: 0, pending: 0 };

  let approved = 0;
  let failed = 0;
  let pending = 0;

  try {
    const content = readFileSync(votesPath, "utf-8");
    for (const line of content.split("\n").filter(Boolean)) {
      try {
        const entry = JSON.parse(line) as {
          ts: string;
          quorum_met?: boolean;
          state?: string;
        };
        // Filter to votes since consensus mode was activated
        if (since && entry.ts < since) continue;

        if (entry.state === "awaiting-consensus" || entry.state === "awaiting_consensus") {
          pending++;
        } else if (entry.quorum_met === true) {
          approved++;
        } else if (entry.quorum_met === false) {
          failed++;
        }
      } catch {
        continue;
      }
    }
  } catch {
    // non-fatal
  }

  return { approved, failed, pending };
}

export async function GET(): Promise<Response> {
  const mode = readModeJson();
  const stats = readConsensusStats(mode.since ?? null);

  const result: ConsensusStatus = {
    mode_on: mode.consensus,
    since: mode.since ?? null,
    voting_threshold: mode.voting_threshold ?? 3,
    ...stats,
  };

  return Response.json(result);
}
