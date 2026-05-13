/**
 * Mode API — reads/sets consensus mode state.
 * Reads from ~/.config/walter-os/mode.json (written by walter-os CLI, T-32).
 * Toggle calls the walter-os CLI via child_process.exec (server-side only).
 *
 * GET  /api/mode          — returns current mode state
 * POST /api/mode          — body: {action: "on"|"off"} — toggles consensus mode
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6, Improvement 9 AC-6)
 * Task: T-43
 */
import { readFileSync, existsSync } from "fs";
import * as path from "path";
import { execFile } from "child_process";
import { promisify } from "util";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

// U-r2-2: use execFile (not exec) to prevent shell injection via WALTER_OS_BIN env var.
// execFile bypasses /bin/sh and passes args as an array, so metacharacters are inert.
const execFileAsync = promisify(execFile);
const CONFIG_DIR = process.env.WALTER_CONFIG_DIR ?? "/root/.config/walter-os";

export interface ModeState {
  consensus: boolean;
  since: string | null;
  voting_threshold: number;
}

function readModeJson(): ModeState {
  const modePath = path.join(CONFIG_DIR, "mode.json");
  if (!existsSync(modePath)) {
    return { consensus: false, since: null, voting_threshold: 3 };
  }
  try {
    const raw = readFileSync(modePath, "utf-8");
    return JSON.parse(raw) as ModeState;
  } catch {
    return { consensus: false, since: null, voting_threshold: 3 };
  }
}

export async function GET(): Promise<Response> {
  const state = readModeJson();
  return Response.json(state);
}

export async function POST(request: Request): Promise<Response> {
  let body: { action?: string };
  try {
    body = (await request.json()) as { action?: string };
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const action = body.action;
  if (action !== "on" && action !== "off") {
    return Response.json(
      { error: "action must be 'on' or 'off'" },
      { status: 400 }
    );
  }

  // Call the walter-os CLI to set the mode.
  // U-r2-2: use execFile with args array — no shell interpolation, no injection risk.
  try {
    const walterBin = process.env.WALTER_OS_BIN ?? "/usr/local/bin/walter-os";
    await execFileAsync(walterBin, ["mode", "consensus", action], {
      timeout: 10000,
    });
    const newState = readModeJson();
    return Response.json(newState);
  } catch (err) {
    return Response.json(
      { error: "Failed to toggle consensus mode", detail: String(err) },
      { status: 500 }
    );
  }
}
