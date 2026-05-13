import { readMetricsSnapshot } from "@/lib/metrics-reader";

/**
 * Server-Sent Events endpoint for real-time agent state.
 * Streams agent state updates every 2 seconds.
 *
 * Event format:
 *   data: {"agent":"coder","state":"working","current_issue":"P-123","since":"...","heartbeat_age_seconds":5}
 *
 * Clients: useEventSource hook in AgentStatusBoard component.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-2)
 * Task: T-37
 */
export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(): Promise<Response> {
  const encoder = new TextEncoder();

  // Interval is declared in the outer scope so cancel() can reference it.
  // The WHATWG Streams API ignores the return value of start(), so cleanup
  // must live in cancel() — not as a returned function from start().
  let interval: ReturnType<typeof setInterval> | undefined;

  const stream = new ReadableStream({
    start(controller) {
      // Send initial snapshot immediately
      function sendSnapshot() {
        try {
          const snapshot = readMetricsSnapshot();
          const data = JSON.stringify(snapshot);
          controller.enqueue(encoder.encode(`data: ${data}\n\n`));
        } catch {
          // If metrics read fails, send a keepalive comment instead
          controller.enqueue(encoder.encode(": keepalive\n\n"));
        }
      }

      sendSnapshot();
      interval = setInterval(sendSnapshot, 2000);
    },
    cancel() {
      // Called when the client disconnects or the reader is cancelled.
      // Clears the polling interval to prevent timer leaks on reconnects.
      if (interval !== undefined) {
        clearInterval(interval);
        interval = undefined;
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-store, must-revalidate",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no", // Disable nginx buffering
    },
  });
}
