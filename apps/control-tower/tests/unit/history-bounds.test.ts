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
import { writeFileSync, readFileSync, mkdirSync, rmSync, existsSync } from "fs";
import * as path from "path";
import * as os from "os";

// We test the internal pruning function directly
import { pruneIfNeeded, atomicAppend } from "@/server/council/history-io";

const TEST_DIR = path.join(os.tmpdir(), `walter-history-test-${Date.now()}`);
const TEST_FILE = path.join(TEST_DIR, "test-history.jsonl");

beforeEach(() => {
  mkdirSync(TEST_DIR, { recursive: true });
  // Start with a clean file
  if (existsSync(TEST_FILE)) rmSync(TEST_FILE);
});

afterEach(() => {
  rmSync(TEST_DIR, { recursive: true, force: true });
});

function makeLines(n: number): string {
  return Array.from({ length: n }, (_, i) =>
    JSON.stringify({ session_id: `sess-${i}`, ts: new Date().toISOString(), i })
  ).join("\n") + "\n";
}

describe("pruneIfNeeded [history bounds]", () => {
  it("does nothing when file has <= 500 lines", () => {
    writeFileSync(TEST_FILE, makeLines(400));
    pruneIfNeeded(TEST_FILE, 500, 400);
    const lines = readFileSync(TEST_FILE, "utf-8").split("\n").filter(Boolean);
    expect(lines.length).toBe(400);
  });

  it("truncates to 400 lines when file exceeds 500 lines", () => {
    writeFileSync(TEST_FILE, makeLines(600));
    pruneIfNeeded(TEST_FILE, 500, 400);
    const lines = readFileSync(TEST_FILE, "utf-8").split("\n").filter(Boolean);
    expect(lines.length).toBe(400);
  });

  it("keeps the LAST 400 entries (most recent)", () => {
    const allLines = Array.from({ length: 600 }, (_, i) =>
      JSON.stringify({ session_id: `sess-${i}`, i })
    );
    writeFileSync(TEST_FILE, allLines.join("\n") + "\n");
    pruneIfNeeded(TEST_FILE, 500, 400);
    const remaining = readFileSync(TEST_FILE, "utf-8").split("\n").filter(Boolean);
    // First remaining entry should be from index 200 (600 - 400)
    const first = JSON.parse(remaining[0]) as { i: number };
    expect(first.i).toBe(200);
    // Last remaining entry should be from index 599
    const last = JSON.parse(remaining[remaining.length - 1]) as { i: number };
    expect(last.i).toBe(599);
  });
});

describe("atomicAppend [history concurrency]", () => {
  it("writes a single line correctly", () => {
    atomicAppend(TEST_FILE, '{"session_id":"s1","ts":"2026-01-01"}');
    const content = readFileSync(TEST_FILE, "utf-8");
    expect(content).toContain('"session_id":"s1"');
    expect(content.endsWith("\n")).toBe(true);
  });

  it("handles concurrent writes without corruption", async () => {
    const CONCURRENCY = 5;
    const writes = Array.from({ length: CONCURRENCY }, (_, i) =>
      new Promise<void>((resolve) => {
        // Use setTimeout to interleave writes
        setTimeout(() => {
          atomicAppend(TEST_FILE, JSON.stringify({ session_id: `sess-${i}`, i }));
          resolve();
        }, Math.random() * 10);
      })
    );

    await Promise.all(writes);

    // All lines should be valid JSON
    const lines = readFileSync(TEST_FILE, "utf-8").split("\n").filter(Boolean);
    expect(lines.length).toBe(CONCURRENCY);
    for (const line of lines) {
      expect(() => JSON.parse(line)).not.toThrow();
    }
  });
});
