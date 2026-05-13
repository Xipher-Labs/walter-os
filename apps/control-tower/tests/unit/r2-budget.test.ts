/**
 * R2 wall-clock budget tests.
 *
 * Verifies that when the R2 loop exceeds the 60s budget, remaining agents
 * are marked as timed out instead of being invoked.
 *
 * Refs: docs/specs/walter-council-v2.md (AC-7)
 * Reviewer round 1 finding: R2 wall-clock budget for AC-7 SLA.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { applyR2Budget } from "@/lib/r2-budget";

describe("applyR2Budget [AC-7]", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns full agent list when budget is not exceeded", () => {
    const agents = ["triage", "researcher", "coder", "reviewer", "janitor", "liaison"];
    const startTime = Date.now();
    // Only 1 second elapsed — budget of 60s not exceeded
    vi.setSystemTime(startTime + 1000);
    const result = applyR2Budget(agents, startTime, 60_000);
    expect(result.canContinue).toBe(true);
    expect(result.remainingMs).toBeGreaterThan(50_000);
  });

  it("reports canContinue=false when less than 5s remains", () => {
    const agents = ["triage", "researcher", "coder"];
    const startTime = Date.now();
    // 56 seconds elapsed — only 4s left, below 5s threshold
    vi.setSystemTime(startTime + 56_000);
    const result = applyR2Budget(agents, startTime, 60_000);
    expect(result.canContinue).toBe(false);
  });

  it("reports canContinue=false when budget is fully exhausted", () => {
    const agents = ["liaison"];
    const startTime = Date.now();
    // 61 seconds elapsed — budget exceeded
    vi.setSystemTime(startTime + 61_000);
    const result = applyR2Budget(agents, startTime, 60_000);
    expect(result.canContinue).toBe(false);
    expect(result.remainingMs).toBeLessThanOrEqual(0);
  });

  it("provides remaining time capped at budget when within budget", () => {
    const agents = ["triage"];
    const startTime = Date.now();
    vi.setSystemTime(startTime + 30_000);
    const result = applyR2Budget(agents, startTime, 60_000);
    expect(result.canContinue).toBe(true);
    expect(result.remainingMs).toBeCloseTo(30_000, -2); // within 100ms
  });
});
