import { describe, expect, it } from "vitest";
import {
  authorizeControlTowerRequest,
  controlTowerSessionValue,
  isControlTowerBypassPath,
  isExplicitDevAuthBypassAllowed,
} from "../../lib/control-tower-auth";

describe("Control Tower token auth", () => {
  it("exempts health and login routes", () => {
    expect(isControlTowerBypassPath("/api/health")).toBe(true);
    expect(isControlTowerBypassPath("/login")).toBe(true);
    expect(isControlTowerBypassPath("/api/login")).toBe(true);
    expect(isControlTowerBypassPath("/api/sse")).toBe(false);
  });

  it("fails closed when the admin token is missing", async () => {
    const result = await authorizeControlTowerRequest(new Headers(), undefined, {
      NODE_ENV: "production",
    });
    expect(result).toEqual({
      allowed: false,
      reason: "missing-token",
      status: 503,
    });
  });

  it("allows the explicit dev override only outside production", () => {
    expect(
      isExplicitDevAuthBypassAllowed({
        NODE_ENV: "development",
        CONTROL_TOWER_AUTH_DISABLED: "true",
      })
    ).toBe(true);

    expect(
      isExplicitDevAuthBypassAllowed({
        NODE_ENV: "production",
        CONTROL_TOWER_AUTH_DISABLED: "true",
      })
    ).toBe(false);
  });

  it("accepts a valid bearer token", async () => {
    const headers = new Headers({
      authorization: "Bearer test-admin-token",
    });
    const result = await authorizeControlTowerRequest(headers, undefined, {
      NODE_ENV: "production",
      CONTROL_TOWER_ADMIN_TOKEN: "test-admin-token",
    });
    expect(result).toEqual({ allowed: true, reason: "bearer" });
  });

  it("accepts a valid HttpOnly session cookie value", async () => {
    const now = 1_700_000_000_000;
    const cookie = await controlTowerSessionValue("test-admin-token", now);
    const result = await authorizeControlTowerRequest(new Headers(), cookie, {
      NODE_ENV: "production",
      CONTROL_TOWER_ADMIN_TOKEN: "test-admin-token",
    }, now);
    expect(result).toEqual({ allowed: true, reason: "cookie" });
  });

  it("rejects an expired HttpOnly session cookie value", async () => {
    const now = 1_700_000_000_000;
    const cookie = await controlTowerSessionValue("test-admin-token", now, 1);
    const result = await authorizeControlTowerRequest(
      new Headers(),
      cookie,
      {
        NODE_ENV: "production",
        CONTROL_TOWER_ADMIN_TOKEN: "test-admin-token",
      },
      now + 2_000
    );
    expect(result).toEqual({
      allowed: false,
      reason: "unauthorized",
      status: 401,
    });
  });

  it("rejects missing credentials when a token is configured", async () => {
    const result = await authorizeControlTowerRequest(new Headers(), undefined, {
      NODE_ENV: "production",
      CONTROL_TOWER_ADMIN_TOKEN: "test-admin-token",
    });
    expect(result).toEqual({
      allowed: false,
      reason: "unauthorized",
      status: 401,
    });
  });
});
