/**
 * SSE route — interval cleanup tests.
 *
 * Verifies that clearInterval is called when the stream is cancelled,
 * preventing timer leaks on client reconnects.
 *
 * Refs: docs/specs/walter-council-v2.md
 * Reviewer round 1 finding: SSE memory leak (interval not cleared on cancel).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Mock the metrics-reader module so we don't need real metric files
vi.mock("@/lib/metrics-reader", () => ({
  readMetricsSnapshot: vi.fn(() => ({
    agents: [],
    ts: new Date().toISOString(),
  })),
}));

// Dynamically import after mock is set up
async function importRoute() {
  // Clear module cache to get a fresh import each time
  return await import("@/app/api/sse/route");
}

describe("SSE /api/sse route — interval lifecycle [AC-2]", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.resetModules();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("clears the interval when the stream is cancelled", async () => {
    const { GET } = await importRoute();
    const response = await GET();

    expect(response).toBeInstanceOf(Response);
    const body = response.body as ReadableStream<Uint8Array> | null;
    expect(body).not.toBeNull();

    // Track setInterval calls
    const setIntervalSpy = vi.spyOn(globalThis, "setInterval");
    const clearIntervalSpy = vi.spyOn(globalThis, "clearInterval");

    // Get a fresh response so our spies are active
    vi.resetModules();
    const { GET: GET2 } = await importRoute();
    const response2 = await GET2();
    const body2 = response2.body as ReadableStream<Uint8Array>;

    // Read and then cancel the stream
    const reader = body2.getReader();
    // Read the initial snapshot
    await reader.read();
    // Cancel — this should trigger the cancel() method
    await reader.cancel();

    // The interval established by this stream should have been cleared
    expect(clearIntervalSpy).toHaveBeenCalled();

    setIntervalSpy.mockRestore();
    clearIntervalSpy.mockRestore();
  });

  it("does not leak intervals across multiple reconnects", async () => {
    const clearIntervalSpy = vi.spyOn(globalThis, "clearInterval");

    const RECONNECTS = 5;
    for (let i = 0; i < RECONNECTS; i++) {
      vi.resetModules();
      const { GET } = await importRoute();
      const response = await GET();
      const body = response.body as ReadableStream<Uint8Array>;
      const reader = body.getReader();
      // Read initial data
      await reader.read();
      // Cancel simulates client disconnect/reconnect
      await reader.cancel();
    }

    // Each of the RECONNECTS cancel() calls should have cleared its interval
    expect(clearIntervalSpy.mock.calls.length).toBeGreaterThanOrEqual(RECONNECTS);

    clearIntervalSpy.mockRestore();
  });
});
