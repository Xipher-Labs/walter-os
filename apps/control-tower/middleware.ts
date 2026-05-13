import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  CONTROL_TOWER_SESSION_COOKIE,
  authorizeControlTowerRequest,
  isControlTowerBypassPath,
} from "@/lib/control-tower-auth";
import { extractClientIP, isTailscaleAllowed } from "@/lib/tailscale";

/**
 * Tailscale-only access enforcement middleware.
 * All requests are checked against the Headscale CGNAT range (100.64.0.0/10).
 * Non-Tailscale requests receive a 403 response.
 *
 * Set TAILSCALE_ENFORCE=false in .env.local to disable for local development.
 *
 * Refs: docs/specs/walter-council-v2.md AC-1 (Part B)
 * Task: T-48
 */
export async function middleware(request: NextRequest): Promise<NextResponse> {
  const enforce = process.env.TAILSCALE_ENFORCE !== "false" &&
                  process.env.TAILSCALE_ENFORCE !== "disabled";
  const cidr = process.env.TAILSCALE_CGNAT_CIDR ?? "100.64.0.0/10";
  const pathname = request.nextUrl.pathname;
  const skipsNetworkGate = pathname === "/api/health";

  if (skipsNetworkGate) {
    return NextResponse.next();
  }

  // Security assumption: the reverse proxy (nginx/Caddy/Tailscale serve) is
  // trusted to set CF-Connecting-IP / X-Forwarded-For / X-Real-IP accurately.
  // If the container is directly exposed without a proxy, an attacker can
  // spoof these headers. The expected deployment is behind Tailscale Serve or
  // a Caddy instance inside the Tailscale network, where the proxy is on the
  // same host and cannot be reached externally without being on the tailnet.
  const clientIP = extractClientIP(request.headers);

  if (!isTailscaleAllowed(clientIP, { enforce, cidr })) {
    return new NextResponse(
      "403 Forbidden — Walter Council Control Tower is Tailscale-only.",
      {
        status: 403,
        headers: { "Content-Type": "text/plain" },
      }
    );
  }

  // Login/static routes bypass token auth but remain Tailscale-gated above.
  if (isControlTowerBypassPath(pathname)) {
    return NextResponse.next();
  }

  const auth = await authorizeControlTowerRequest(
    request.headers,
    request.cookies.get(CONTROL_TOWER_SESSION_COOKIE)?.value
  );

  if (!auth.allowed) {
    if (auth.reason === "missing-token") {
      return new NextResponse(
        "503 Service Unavailable - CONTROL_TOWER_ADMIN_TOKEN is required.",
        {
          status: 503,
          headers: { "Content-Type": "text/plain" },
        }
      );
    }

    if (pathname.startsWith("/api/")) {
      return new NextResponse("401 Unauthorized", {
        status: 401,
        headers: {
          "Content-Type": "text/plain",
          "WWW-Authenticate": 'Bearer realm="control-tower"',
        },
      });
    }

    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    loginUrl.searchParams.set(
      "next",
      `${request.nextUrl.pathname}${request.nextUrl.search}`
    );
    return NextResponse.redirect(loginUrl, 303);
  }

  return NextResponse.next();
}

export const config = {
  // Apply to all routes except Next.js internals and static files
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
