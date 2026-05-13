/**
 * Unit tests for Tailscale IP validation.
 * Covers [AC-1] of Control Tower Part B: non-Tailscale IPs → 403.
 *
 * AC-1: Access from non-Tailscale IP → 403. Tailscale IP → 200.
 */
import { describe, it, expect } from "vitest";
import { parseIPv4, ipInCidr, extractClientIP, isTailscaleAllowed } from "../../lib/tailscale";

describe("parseIPv4", () => {
  it("parses valid IPv4", () => {
    expect(parseIPv4("100.64.0.1")).toBe((100 << 24 | 64 << 16 | 0 << 8 | 1) >>> 0);
    expect(parseIPv4("0.0.0.0")).toBe(0);
    expect(parseIPv4("255.255.255.255")).toBe(0xffffffff);
  });

  it("returns null for invalid addresses", () => {
    expect(parseIPv4("256.0.0.1")).toBeNull();
    expect(parseIPv4("100.64.0")).toBeNull();
    expect(parseIPv4("not-an-ip")).toBeNull();
    expect(parseIPv4("100.64.0.1.5")).toBeNull();
  });
});

describe("ipInCidr [AC-1]", () => {
  const TAILSCALE_CIDR = "100.64.0.0/10";

  it("accepts IPs in the Tailscale CGNAT range", () => {
    expect(ipInCidr("100.64.0.1", TAILSCALE_CIDR)).toBe(true);
    expect(ipInCidr("100.127.255.255", TAILSCALE_CIDR)).toBe(true);
    expect(ipInCidr("100.100.50.25", TAILSCALE_CIDR)).toBe(true);
  });

  it("rejects IPs outside the Tailscale CGNAT range", () => {
    expect(ipInCidr("8.8.8.8", TAILSCALE_CIDR)).toBe(false);
    expect(ipInCidr("192.168.1.1", TAILSCALE_CIDR)).toBe(false);
    expect(ipInCidr("100.128.0.0", TAILSCALE_CIDR)).toBe(false);
    expect(ipInCidr("10.0.0.1", TAILSCALE_CIDR)).toBe(false);
  });

  it("handles /32 (single host)", () => {
    expect(ipInCidr("1.2.3.4", "1.2.3.4/32")).toBe(true);
    expect(ipInCidr("1.2.3.5", "1.2.3.4/32")).toBe(false);
  });

  it("handles /0 (allow all)", () => {
    expect(ipInCidr("8.8.8.8", "0.0.0.0/0")).toBe(true);
  });
});

describe("extractClientIP", () => {
  it("prefers CF-Connecting-IP", () => {
    const h = new Headers({ "cf-connecting-ip": "100.64.1.2", "x-forwarded-for": "1.2.3.4" });
    expect(extractClientIP(h)).toBe("100.64.1.2");
  });

  it("falls back to X-Real-IP", () => {
    const h = new Headers({ "x-real-ip": "100.64.1.2" });
    expect(extractClientIP(h)).toBe("100.64.1.2");
  });

  it("falls back to first X-Forwarded-For IP", () => {
    const h = new Headers({ "x-forwarded-for": "100.64.1.2, 1.2.3.4" });
    expect(extractClientIP(h)).toBe("100.64.1.2");
  });

  it("returns null when no IP header present", () => {
    expect(extractClientIP(new Headers())).toBeNull();
  });
});

describe("isTailscaleAllowed [AC-1]", () => {
  const cidr = "100.64.0.0/10";

  it("allows Tailscale IPs when enforcement is on", () => {
    expect(isTailscaleAllowed("100.64.0.5", { enforce: true, cidr })).toBe(true);
  });

  it("blocks non-Tailscale IPs when enforcement is on", () => {
    expect(isTailscaleAllowed("8.8.8.8", { enforce: true, cidr })).toBe(false);
    expect(isTailscaleAllowed(null, { enforce: true, cidr })).toBe(false);
  });

  it("allows all IPs when enforcement is off (local dev)", () => {
    expect(isTailscaleAllowed("8.8.8.8", { enforce: false, cidr })).toBe(true);
    expect(isTailscaleAllowed(null, { enforce: false, cidr })).toBe(true);
  });
});
