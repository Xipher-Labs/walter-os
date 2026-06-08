/**
 * History JSONL bounding and atomic-write tests.
 *
 * Verifies:
 * - Files larger than 500 lines get pruned to 400 (oldest entries dropped).
 * - Concurrent writers don't corrupt the JSONL file.
 *
 * Refs: docs/specs/walter-council-v2.md
 * Reviewer round 1 finding: history JSONL unbounded + race condition.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  chmodSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "fs";
import * as path from "path";
import * as os from "os";

// We test the internal pruning function directly
import { pruneIfNeeded, atomicAppend } from "@/server/council/history-io";

let testDir: string;
let testFile: string;

beforeEach(() => {
  testDir = mkdtempSync(path.join(os.tmpdir(), "walter-history-test-"));
  testFile = path.join(testDir, "test-history.jsonl");
});

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true });
});

function makeLines(n: number): string {
  return Array.from({ length: n }, (_, i) =>
    JSON.stringify({ session_id: `sess-${i}`, ts: new Date().toISOString(), i })
  ).join("\n") + "\n";
}

describe("pruneIfNeeded [history bounds]", () => {
  it("does nothing when file has <= 500 lines", () => {
    writeFileSync(testFile, makeLines(400));
    pruneIfNeeded(testFile, 500, 400);
    const lines = readFileSync(testFile, "utf-8").split("\n").filter(Boolean);
    expect(lines.length).toBe(400);
  });

  it("truncates to 400 lines when file exceeds 500 lines", () => {
    writeFileSync(testFile, makeLines(600));
    pruneIfNeeded(testFile, 500, 400);
    const lines = readFileSync(testFile, "utf-8").split("\n").filter(Boolean);
    expect(lines.length).toBe(400);
  });

  it("keeps the LAST 400 entries (most recent)", () => {
    const allLines = Array.from({ length: 600 }, (_, i) =>
      JSON.stringify({ session_id: `sess-${i}`, i })
    );
    writeFileSync(testFile, allLines.join("\n") + "\n");
    pruneIfNeeded(testFile, 500, 400);
    const remaining = readFileSync(testFile, "utf-8").split("\n").filter(Boolean);
    // First remaining entry should be from index 200 (600 - 400)
    const first = JSON.parse(remaining[0]) as { i: number };
    expect(first.i).toBe(200);
    // Last remaining entry should be from index 599
    const last = JSON.parse(remaining[remaining.length - 1]) as { i: number };
    expect(last.i).toBe(599);
  });

  it("preserves private file permissions when pruning", () => {
    writeFileSync(testFile, makeLines(600), { mode: 0o600 });
    chmodSync(testFile, 0o600);

    pruneIfNeeded(testFile, 500, 400);

    expect(statSync(testFile).mode & 0o777).toBe(0o600);
  });
});

describe("atomicAppend [history concurrency]", () => {
  it("writes a single line correctly", () => {
    atomicAppend(testFile, '{"session_id":"s1","ts":"2026-01-01"}');
    const content = readFileSync(testFile, "utf-8");
    expect(content).toContain('"session_id":"s1"');
    expect(content.endsWith("\n")).toBe(true);
  });

  it("creates a new history file with private permissions", () => {
    atomicAppend(testFile, '{"session_id":"s-private","ts":"2026-01-01"}');

    expect(statSync(testFile).mode & 0o777).toBe(0o600);
  });

  it("tightens an existing parent directory to owner-only permissions", () => {
    chmodSync(testDir, 0o777);

    atomicAppend(testFile, '{"session_id":"s1","ts":"2026-01-01"}');

    expect(statSync(testDir).mode & 0o777).toBe(0o700);
  });

  it("handles concurrent writes without corruption", async () => {
    const CONCURRENCY = 5;
    const writes = Array.from({ length: CONCURRENCY }, (_, i) =>
      new Promise<void>((resolve) => {
        // Use setTimeout to interleave writes
        setTimeout(() => {
          atomicAppend(testFile, JSON.stringify({ session_id: `sess-${i}`, i }));
          resolve();
        }, Math.random() * 10);
      })
    );

    await Promise.all(writes);

    // All lines should be valid JSON
    const lines = readFileSync(testFile, "utf-8").split("\n").filter(Boolean);
    expect(lines.length).toBe(CONCURRENCY);
    for (const line of lines) {
      expect(() => JSON.parse(line)).not.toThrow();
    }
  });
});
