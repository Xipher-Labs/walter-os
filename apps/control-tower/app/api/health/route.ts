/**
 * Health check endpoint for Docker healthcheck.
 * Skipped by Tailscale middleware.
 */
export async function GET(): Promise<Response> {
  return Response.json({ status: "ok", ts: new Date().toISOString() });
}
