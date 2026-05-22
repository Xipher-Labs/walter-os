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

// Standalone server bind addresses we never want to leak into a Location
// header. The IPv4 bind sentinel is `0.0.0.0`; the IPv6 forms (`::`,
// `[::]`, `[::]:3000`) are rejected upstream by isPlausibleHostHeader
// (which refuses values containing extra colons or square brackets), so
// they cannot reach this guard. We keep the IPv4 check explicit and
// trust the plausibility filter for IPv6 — extending the set without
// also relaxing isPlausibleHostHeader would be dead code.
const UNROUTABLE_HOSTS = new Set(["0.0.0.0"]);

function isUnroutableHost(host: string): boolean {
  const bare = host.split(":")[0];
  return UNROUTABLE_HOSTS.has(bare);
}

// X-Forwarded-* headers may carry a comma-separated list when the request
// has traversed multiple proxies. The append semantics differ by proxy:
// nginx and Caddy append (rightmost = closest to the server); Cloudflare
// Tunnel and Tailscale Serve replace the header entirely with a single
// value (the public-facing one). In the Walter-VM deployment topology
// (CF Tunnel → Tailscale Serve → container) only one value is ever
// present and it is the public hostname the operator's browser used.
// We always take the first (leftmost) value: that matches the
// CF-Tunnel / Tailscale-Serve replace semantics, and in an appending
// chain it is the origin-most hop — also what we want. Operators who
// front Control Tower with an appending proxy that they don't trust
// should set CONTROL_TOWER_PUBLIC_URL to bypass header trust entirely.
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

  // 2. Trusted proxy forwarded headers. Symmetry with step 3: a
  // misconfigured internal proxy that forwards `X-Forwarded-Host: 0.0.0.0`
  // would otherwise reproduce the bug we are fixing. Reject the bind
  // sentinel here too and fall through to the next source.
  const forwardedHost = firstHopHeaderValue(headers, "x-forwarded-host");
  if (
    forwardedHost &&
    isPlausibleHostHeader(forwardedHost) &&
    !isUnroutableHost(forwardedHost)
  ) {
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
