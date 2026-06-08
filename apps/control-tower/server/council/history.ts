/**
 * Council Chat history persistence.
 * Sessions are stored as JSONL in Control Tower's configured state dir.
 *
 * Each line is a session JSON object with R1, R2, and synthesis results.
 */

import { existsSync, readFileSync } from "fs";
import * as path from "path";
import { atomicAppend, pruneIfNeeded } from "./history-io";

const CONFIG_DIR =
  process.env.WALTER_CONFIG_DIR ??
  process.env.WALTER_CONFIG ??
  "/var/lib/walter-os/control-tower";
const HISTORY_FILE = path.join(CONFIG_DIR, "council-chat-history.jsonl");

export interface R1Response {
  agent: string;
  content: string;
  elapsed_ms: number;
  token_count?: number;
}

export interface R2Response {
  agent: string;
  content: string;
  elapsed_ms: number;
}

export interface SynthesisResult {
  summary: string;
  convergences: string[];
  disagreements: string[];
  recommended_path: string;
  next_steps: string[];
}

export interface ChatSession {
  session_id: string;
  session_type: "chat" | "ideation";
  ts: string;
  message: string;
  round1?: R1Response[];
  round2?: R2Response[];
  synthesis?: SynthesisResult;
}

export function persistSession(session: ChatSession): void {
  try {
    atomicAppend(HISTORY_FILE, JSON.stringify(session));
    // Prune after every write to keep the file bounded.
    // Keeps the 400 most recent entries when the file exceeds 500 lines.
    pruneIfNeeded(HISTORY_FILE, 500, 400);
  } catch {
    // Non-fatal — history persistence failure should not break the chat flow
  }
}

export function updateSession(
  sessionId: string,
  updates: Partial<ChatSession>
): void {
  // Simple append-based update — a new line with same session_id + updated fields
  // The history reader uses the LAST entry per session_id
  try {
    const current = getSession(sessionId);
    if (current) {
      persistSession({ ...current, ...updates });
    }
  } catch {
    // Non-fatal
  }
}

export function getSession(sessionId: string): ChatSession | null {
  if (!existsSync(HISTORY_FILE)) return null;
  try {
    const lines = readFileSync(HISTORY_FILE, "utf-8").split("\n").filter(Boolean);
    // Return the last entry with this session_id (most up-to-date)
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const session = JSON.parse(lines[i]) as ChatSession;
        if (session.session_id === sessionId) return session;
      } catch {
        continue;
      }
    }
    return null;
  } catch {
    return null;
  }
}

export function listSessions(limit = 50): ChatSession[] {
  if (!existsSync(HISTORY_FILE)) return [];
  try {
    const lines = readFileSync(HISTORY_FILE, "utf-8").split("\n").filter(Boolean);
    // Dedupe by session_id keeping the last occurrence
    const sessionMap = new Map<string, ChatSession>();
    for (const line of lines) {
      try {
        const session = JSON.parse(line) as ChatSession;
        sessionMap.set(session.session_id, session);
      } catch {
        continue;
      }
    }
    return Array.from(sessionMap.values())
      .sort((a, b) => b.ts.localeCompare(a.ts))
      .slice(0, limit);
  } catch {
    return [];
  }
}
