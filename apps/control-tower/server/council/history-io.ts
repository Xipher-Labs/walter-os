/**
 * Low-level JSONL I/O helpers for council-chat history.
 *
 * Extracted from history.ts to be unit-testable.
 * Provides:
 * - atomicAppend: uses write-to-tmp + rename for crash safety
 * - pruneIfNeeded: caps the file at maxLines, keeping the most recent entries
 *
 * Refs: docs/specs/walter-council-v2.md
 * Reviewer round 1 finding: history JSONL unbounded + race condition.
 */

import {
  chmodSync,
  readFileSync,
  writeFileSync,
  renameSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
} from "fs";
import * as path from "path";

function readExistingFile(filePath: string): string | null {
  try {
    return readFileSync(filePath, "utf-8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

function atomicWritePrivate(filePath: string, content: string): void {
  const dir = path.dirname(filePath);
  mkdirSync(dir, { recursive: true, mode: 0o700 });

  const tmpDir = mkdtempSync(path.join(dir, ".history-write-"));
  const tmpPath = path.join(tmpDir, "payload");
  try {
    writeFileSync(tmpPath, content, {
      encoding: "utf-8",
      flag: "wx",
      mode: 0o600,
    });
    renameSync(tmpPath, filePath);
    chmodSync(filePath, 0o600);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
}

/**
 * Append a single JSONL line to the file.
 *
 * Uses an exclusive temp directory + write-to-temp + rename pattern for
 * crash safety. The final rename is atomic on POSIX filesystems when source
 * and destination are on the same mount.
 *
 * Note: this approach is not safe for very high-frequency concurrent writes
 * (last-writer-wins on concurrent renames). For the council-chat use case
 * (at most one session active at a time) this is sufficient. A proper lock
 * would require a lock file or an async queue.
 */
export function atomicAppend(filePath: string, jsonLine: string): void {
  const existing = readExistingFile(filePath) ?? "";

  const newContent = existing.endsWith("\n") || existing === ""
    ? existing + jsonLine + "\n"
    : existing + "\n" + jsonLine + "\n";

  try {
    atomicWritePrivate(filePath, newContent);
  } catch {
    // Non-fatal — same policy as history.ts
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
  try {
    const existing = readExistingFile(filePath);
    if (existing === null) return;
    const lines = existing.split("\n").filter(Boolean);
    if (lines.length <= maxLines) return;
    const pruned = lines.slice(lines.length - keepLines);
    atomicWritePrivate(filePath, pruned.join("\n") + "\n");
  } catch {
    // Non-fatal
  }
}
