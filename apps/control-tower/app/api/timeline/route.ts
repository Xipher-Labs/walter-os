import { readRecentEvents } from "@/lib/events-reader";

/**
 * Timeline API — returns last 50 events from events.log + consensus-votes.log.
 *
 * GET /api/timeline?limit=50
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-3)
 * Task: T-39
 */
export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const limit = Math.min(
    parseInt(url.searchParams.get("limit") ?? "50", 10) || 50,
    200
  );

  try {
    const entries = readRecentEvents(limit);
    return Response.json({ entries, count: entries.length });
  } catch (err) {
    return Response.json(
      { error: "Failed to read events", detail: String(err) },
      { status: 500 }
    );
  }
}
