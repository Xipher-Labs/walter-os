/**
 * History API — lists and searches Council Chat sessions.
 *
 * GET /api/history?q=<query>&limit=50
 *
 * Returns sessions from council-chat-history.jsonl, optionally filtered
 * by a simple grep-style search on the message field.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-9 implied)
 * Task: T-47
 */
import { listSessions } from "@/server/council/history";
export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const query = url.searchParams.get("q")?.toLowerCase().trim() ?? "";
  const limit = Math.min(
    parseInt(url.searchParams.get("limit") ?? "50", 10) || 50,
    200
  );

  const sessions = listSessions(200);

  const filtered = query
    ? sessions.filter(
        (s) =>
          s.message.toLowerCase().includes(query) ||
          s.synthesis?.summary?.toLowerCase().includes(query) ||
          s.synthesis?.recommended_path?.toLowerCase().includes(query)
      )
    : sessions;

  return Response.json({
    sessions: filtered.slice(0, limit),
    total: filtered.length,
    query: query || null,
  });
}
