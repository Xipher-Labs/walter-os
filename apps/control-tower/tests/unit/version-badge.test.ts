/**
 * version-badge.test.ts
 *
 * Tests for lib/version.ts — the utility that reads WALTER_VERSION and
 * WALTER_UPDATE_AVAILABLE env vars and returns version badge display data.
 *
 * Covers: AC-5 — Control Tower reads VERSION env var and shows update badge.
 *
 * Refs: docs/specs/phase-w-7-versioning-release.md
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { getVersionInfo } from "@/lib/version";

describe("getVersionInfo [AC-5]", () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    // Restore original env after each test.
    Object.keys(process.env).forEach((k) => {
      if (!(k in originalEnv)) delete process.env[k];
    });
    Object.assign(process.env, originalEnv);
  });

  it("returns version string from WALTER_VERSION env var [AC-5]", () => {
    process.env.WALTER_VERSION = "0.2.0";
    delete process.env.WALTER_UPDATE_AVAILABLE;
    const info = getVersionInfo();
    expect(info.version).toBe("0.2.0");
  });

  it("returns null version when WALTER_VERSION is not set [AC-5]", () => {
    delete process.env.WALTER_VERSION;
    delete process.env.WALTER_UPDATE_AVAILABLE;
    const info = getVersionInfo();
    expect(info.version).toBeNull();
  });

  it("returns updateAvailable when WALTER_UPDATE_AVAILABLE is set [AC-5]", () => {
    process.env.WALTER_VERSION = "0.2.0";
    process.env.WALTER_UPDATE_AVAILABLE = "0.3.0";
    const info = getVersionInfo();
    expect(info.updateAvailable).toBe("0.3.0");
  });

  it("returns null updateAvailable when WALTER_UPDATE_AVAILABLE is not set [AC-5]", () => {
    process.env.WALTER_VERSION = "0.2.0";
    delete process.env.WALTER_UPDATE_AVAILABLE;
    const info = getVersionInfo();
    expect(info.updateAvailable).toBeNull();
  });

  it("returns showBadge=true when update is available [AC-5]", () => {
    process.env.WALTER_VERSION = "0.2.0";
    process.env.WALTER_UPDATE_AVAILABLE = "0.3.0";
    const info = getVersionInfo();
    expect(info.showBadge).toBe(true);
  });

  it("returns showBadge=false when no update available [AC-5]", () => {
    process.env.WALTER_VERSION = "0.2.0";
    delete process.env.WALTER_UPDATE_AVAILABLE;
    const info = getVersionInfo();
    expect(info.showBadge).toBe(false);
  });
});
