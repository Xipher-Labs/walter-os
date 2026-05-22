/**
 * Resolve the canonical public base URL the operator's browser used to reach
 * Control Tower.
 *
 * Background — the Next.js standalone server (`apps/control-tower/server.js`)
 * is bound to `HOSTNAME=0.0.0.0` so the container accepts forwarded traffic
 * from any interface. As a side effect, `request.url` inside route handlers
 * and `request.nextUrl` in middleware report the bind host
 * (`http://0.0.0.0:3000/...`). When that URL ends up in a `Location` header
 * the browser refuses to follow it: Chrome blocks `0.0.0.0` outright (the
 * "0.0.0.0 Day" mitigation, 2024) and even on browsers that allow it, the
 * address is unreachable across the public Internet.
 *
 * Control Tower is always deployed behind a trusted proxy (Cloudflare Tunnel
 * to the Walter-VM, or Tailscale Serve on the tailnet). Both set
 * `X-Forwarded-Host` and `X-Forwarded-Proto` reliably. This helper picks the
 * first trusted source available, in priority order:
 *
 *   1. `CONTROL_TOWER_PUBLIC_URL` env var — explicit operator override.
 *      Always wins. Operators set this when the deployment has a stable
 *      public hostname (e.g., `https://tower.xipherlabs.xyz`). It also
 *      neutralises X-Forwarded-Host spoofing if Control Tower is ever
 *      exposed directly (defense-in-depth).
 *   2. `X-Forwarded-Host` + `X-Forwarded-Proto` from the inbound request.
 *      Used in production when no explicit override is configured.
 *   3. `Host` header, when it does not point to the bind hostname
 *      (`0.0.0.0`). Useful in local development and direct tailnet IP
 *      access.
 *   4. `fallback` (typically `request.url`), as a last resort. This
 *      preserves current behaviour for any caller that has not yet been
 *      migrated to the helper.
 *
 * Refs:
 *   - https://chromestatus.com/feature/5763007541936128 (0.0.0.0 navigation)
 *   - https://github.com/vercel/next.js/issues/45301 (HOSTNAME vs Host)
 */
type EnvLike = Record<string, string | undefined>;

// Common "do not use this for URL construction" hostnames. The standalone
// server uses `0.0.0.0` as the bind address; the IPv6 equivalent is `::`.
const UNROUTABLE_HOSTS = new Set(["0.0.0.0", "::", "[::]"]);

function isUnroutableHost(host: string): boolean {
  const bare = host.split(":")[0];
  return UNROUTABLE_HOSTS.has(bare);
}

// A header that came from the upstream proxy may contain a comma-separated
// list when there are multiple proxies in the chain. Only the first hop is
// the origin-most (operator-controlled) value; the rest are appended by
// downstream proxies and not trustworthy.
function firstHopHeaderValue(headers: Headers, name: string): string | null {
  const raw = headers.get(name);
  if (!raw) return null;
  const first = raw.split(",")[0]?.trim();
  return first ? first : null;
}

// X-Forwarded-Host must be a bare `host` or `host:port` — never an absolute
// URL, never a path. Anything else is rejected to avoid URL-parsing surprises
// (an embedded scheme like `http://...` would be parsed as the path by
// `new URL`, leading to unintended origins).
function isPlausibleHostHeader(value: string): boolean {
  if (value.includes("/")) return false;
  if (value.includes("://")) return false;
  if (value.includes(" ")) return false;
  // host or host:port — at most one colon, host non-empty.
  const [host, port, ...rest] = value.split(":");
  if (rest.length > 0) return false; // disallow extra colons (no IPv6 raw here)
  if (!host) return false;
  if (port !== undefined && !/^\d+$/.test(port)) return false;
  return true;
}

function tryParseBaseUrl(value: string | undefined | null): URL | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  try {
    return new URL(trimmed);
  } catch {
    return null;
  }
}

export function getCanonicalBaseUrl(
  headers: Headers,
  fallback: string,
  env: EnvLike = process.env
): URL {
  // 1. Explicit operator override.
  const overrideUrl = tryParseBaseUrl(env.CONTROL_TOWER_PUBLIC_URL);
  if (overrideUrl) {
    return overrideUrl;
  }

  // 2. Trusted proxy forwarded headers.
  const forwardedHost = firstHopHeaderValue(headers, "x-forwarded-host");
  if (forwardedHost && isPlausibleHostHeader(forwardedHost)) {
    const forwardedProto = firstHopHeaderValue(headers, "x-forwarded-proto");
    // Default to https — both Cloudflare Tunnel and Tailscale Serve
    // terminate TLS in front of the container.
    const proto = forwardedProto === "http" ? "http" : "https";
    return new URL(`${proto}://${forwardedHost}`);
  }

  // 3. Host header, ignoring the bind-only sentinels.
  const host = headers.get("host");
  if (host && isPlausibleHostHeader(host) && !isUnroutableHost(host)) {
    const forwardedProto = firstHopHeaderValue(headers, "x-forwarded-proto");
    const proto = forwardedProto === "https" ? "https" : "http";
    return new URL(`${proto}://${host}`);
  }

  // 4. Last resort: whatever the framework gave us.
  return new URL(fallback);
}
