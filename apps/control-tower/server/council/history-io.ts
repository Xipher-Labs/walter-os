/**
 * Low-level JSONL I/O helpers for council-chat history.
 *
 * Extracted from history.ts to be unit-testable.
 * Provides:
 * - atomicAppend: uses write-to-tmp + rename to avoid partial writes
 * - pruneIfNeeded: caps the file at maxLines, keeping the most recent entries
 *
 * Refs: docs/specs/walter-council-v2.md
 * Reviewer round 1 finding: history JSONL unbounded + race condition.
 */

import {
  chmodSync,
  existsSync,
  readFileSync,
  writeFileSync,
  renameSync,
  mkdirSync,
} from "fs";
import * as path from "path";

/**
 * Append a single JSONL line to the file.
 *
 * Uses a write-to-tmp-then-rename pattern so readers see either the previous
 * file or the complete replacement file. The final rename is atomic on POSIX
 * filesystems when the temp file is on the same mount. On Windows
 * (non-production target) falls back to direct append.
 *
 * Note: this approach is not safe for very high-frequency concurrent writes
 * (last-writer-wins on concurrent renames). For the council-chat use case
 * (at most one session active at a time) this is sufficient. A proper lock
 * would require a lock file or an async queue.
 */
export function atomicAppend(filePath: string, jsonLine: string): void {
  const dir = path.dirname(filePath);
  mkdirSync(dir, { recursive: true });
  try {
    chmodSync(dir, 0o700);
  } catch {
    // Best effort: directory creation/write behavior remains non-fatal below.
  }

  // Read existing content (may not exist yet)
  const existing = existsSync(filePath)
    ? readFileSync(filePath, "utf-8")
    : "";

  const newContent = existing.endsWith("\n") || existing === ""
    ? existing + jsonLine + "\n"
    : existing + "\n" + jsonLine + "\n";

  // Write to a temp file in the same directory, then rename
  const tmpPath = `${filePath}.tmp.${process.pid}.${Date.now()}`;
  try {
    writeFileSync(tmpPath, newContent, "utf-8");
    renameSync(tmpPath, filePath);
  } catch {
    // If rename fails (e.g., cross-device on some setups), fall back to direct write
    try {
      writeFileSync(filePath, newContent, "utf-8");
    } catch {
      // Non-fatal — same policy as history.ts
    }
    // Clean up tmp if it still exists
    try {
      if (existsSync(tmpPath)) {
        renameSync(tmpPath, filePath);
      }
    } catch {
      // ignore
    }
  }
}

/**
 * Prune the history file if it exceeds maxLines lines.
 * Keeps the most recent keepLines entries (drops oldest from the top).
 */
export function pruneIfNeeded(
  filePath: string,
  maxLines = 500,
  keepLines = 400
): void {
  if (!existsSync(filePath)) return;
  try {
    const lines = readFileSync(filePath, "utf-8").split("\n").filter(Boolean);
    if (lines.length <= maxLines) return;
    const pruned = lines.slice(lines.length - keepLines);
    writeFileSync(filePath, pruned.join("\n") + "\n", "utf-8");
  } catch {
    // Non-fatal
  }
}
