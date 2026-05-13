/**
 * Alerts API — returns recent warn/critical/panic events.
 * Acknowledgements are tracked in a local file.
 *
 * GET  /api/alerts        — list recent alerts
 * POST /api/alerts/ack    — acknowledge an alert by ID
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-6)
 * Task: T-43
 */
import { readRecentEvents } from "@/lib/events-reader";
export const dynamic = "force-dynamic";

export async function GET(): Promise<Response> {
  const all = readRecentEvents(100);
  // Filter to actionable tiers only
  const alerts = all.filter(
    (e) =>
      e.type === "alert" &&
      (e.tier === "warn" || e.tier === "critical" || e.tier === "panic")
  );
  return Response.json({ alerts: alerts.slice(0, 20) });
}
