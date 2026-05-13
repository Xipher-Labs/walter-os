/**
 * Tailscale IP validation utilities.
 * Control Tower is Tailscale-only: only IPs in the Headscale CGNAT range
 * (100.64.0.0/10) are allowed. All others get 403.
 *
 * The CGNAT range covers 100.64.0.0 – 100.127.255.255.
 */

/**
 * Parse an IPv4 address string into a 32-bit unsigned integer.
 * Returns null if the input is not a valid IPv4 address.
 */
export function parseIPv4(ip: string): number | null {
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  let value = 0;
  for (const part of parts) {
    const n = parseInt(part, 10);
    if (isNaN(n) || n < 0 || n > 255 || part !== String(n)) return null;
    value = (value << 8) | n;
  }
  // JS bitwise ops work on signed 32-bit; convert to unsigned
  return value >>> 0;
}

/**
 * Check whether an IP falls within a CIDR range.
 * Supports only IPv4 CIDRs.
 */
export function ipInCidr(ip: string, cidr: string): boolean {
  const [base, prefixStr] = cidr.split("/");
  const prefix = parseInt(prefixStr, 10);
  if (isNaN(prefix) || prefix < 0 || prefix > 32) return false;

  const ipInt = parseIPv4(ip);
  const baseInt = parseIPv4(base);
  if (ipInt === null || baseInt === null) return false;

  const mask = prefix === 0 ? 0 : (~0 << (32 - prefix)) >>> 0;
  return (ipInt & mask) === (baseInt & mask);
}

/**
 * Extract the client IP from a Next.js request.
 * Precedence: CF-Connecting-IP → X-Real-IP → X-Forwarded-For (first IP).
 * Returns null if no IP can be determined.
 */
export function extractClientIP(headers: Headers): string | null {
  // Cloudflare sets CF-Connecting-IP to the real client IP
  const cfIP = headers.get("cf-connecting-ip");
  if (cfIP) return cfIP.trim();

  const realIP = headers.get("x-real-ip");
  if (realIP) return realIP.trim();

  const forwarded = headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();

  return null;
}

/**
 * Determine whether a request is allowed based on Tailscale IP rules.
 *
 * When TAILSCALE_ENFORCE=false (or "disabled"), all requests are allowed.
 * This enables local development without Tailscale.
 */
export function isTailscaleAllowed(
  clientIP: string | null,
  opts: { enforce: boolean; cidr: string }
): boolean {
  if (!opts.enforce) return true;
  if (!clientIP) return false;
  return ipInCidr(clientIP, opts.cidr);
}
