/**
 * Unit tests for events-reader.ts
 * Covers: JSONL parsing, sorting, limit enforcement.
 *
 * AC-3: Timeline shows last 50 events with correct timestamps and agents.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import * as fs from "fs";

// Mock fs before importing the module under test
vi.mock("fs", async () => {
  const actual = await vi.importActual<typeof import("fs")>("fs");
  return { ...actual, readFileSync: vi.fn(), existsSync: vi.fn() };
});

// Import after mocking
const { readRecentEvents } = await import("../../lib/events-reader");

const mockExistsSync = vi.mocked(fs.existsSync);
const mockReadFileSync = vi.mocked(fs.readFileSync);

beforeEach(() => {
  vi.clearAllMocks();
  mockExistsSync.mockReturnValue(false);
});

describe("readRecentEvents", () => {
  it("returns empty array when log files do not exist", () => {
    const entries = readRecentEvents();
    expect(entries).toEqual([]);
  });

  it("parses events.log JSONL entries", () => {
    mockExistsSync.mockImplementation((p: unknown) =>
      typeof p === "string" && p.includes("events.log")
    );
    mockReadFileSync.mockImplementation((p: unknown) => {
      if (typeof p === "string" && p.includes("events.log")) {
        return [
          JSON.stringify({ ts: "2026-05-11T10:00:00Z", tier: "warn", message: "Budget 80%", context: { agent: "coder" } }),
          JSON.stringify({ ts: "2026-05-11T09:00:00Z", tier: "info", message: "Task done", context: {} }),
        ].join("\n");
      }
      throw new Error("file not found");
    });

    const entries = readRecentEvents();
    expect(entries.length).toBe(2);
    // Sorted descending: most recent first
    expect(entries[0].ts).toBe("2026-05-11T10:00:00Z");
    expect(entries[0].tier).toBe("warn");
    expect(entries[0].agent).toBe("coder");
    expect(entries[1].ts).toBe("2026-05-11T09:00:00Z");
  });

  it("parses consensus-votes.log and merges with events", () => {
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockImplementation((p: unknown) => {
      if (typeof p === "string" && p.includes("events.log")) {
        return JSON.stringify({ ts: "2026-05-11T10:00:00Z", tier: "info", message: "Done", context: {} });
      }
      if (typeof p === "string" && p.includes("consensus-votes.log")) {
        return JSON.stringify({
          ts: "2026-05-11T10:05:00Z",
          task_id: "P-42",
          votes: 3,
          yes: 2,
          no: 1,
          quorum_met: true,
          voters: [],
        });
      }
      return "";
    });

    const entries = readRecentEvents();
    expect(entries.length).toBe(2);
    const vote = entries.find((e) => e.type === "consensus");
    expect(vote).toBeDefined();
    expect(vote?.message).toContain("passed");
    expect(vote?.message).toContain("P-42");
  });

  it("skips malformed JSONL lines", () => {
    mockExistsSync.mockImplementation((p: unknown) =>
      typeof p === "string" && p.includes("events.log")
    );
    mockReadFileSync.mockImplementation(() =>
      "not-json\n" +
      JSON.stringify({ ts: "2026-05-11T10:00:00Z", tier: "info", message: "Good", context: {} })
    );

    const entries = readRecentEvents();
    expect(entries.length).toBe(1);
  });

  it("respects limit parameter", () => {
    mockExistsSync.mockImplementation((p: unknown) =>
      typeof p === "string" && p.includes("events.log")
    );
    const lines = Array.from({ length: 20 }, (_, i) =>
      JSON.stringify({ ts: `2026-05-11T${String(i).padStart(2, "0")}:00:00Z`, tier: "info", message: `Evt ${i}`, context: {} })
    );
    mockReadFileSync.mockReturnValue(lines.join("\n"));

    const entries = readRecentEvents(5);
    expect(entries.length).toBe(5);
  });
});
