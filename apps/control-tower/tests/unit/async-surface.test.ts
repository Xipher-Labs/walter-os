/**
 * Source-invariant tests for the shared primitives (AC-2, AC-5).
 *
 * The repo's component tests are static-analysis style (see
 * metrics-dashboard-token.test.ts) because there is no jsdom/RTL runner wired
 * up. These assert the load-bearing accessibility + state contracts of the
 * shared primitives so a future edit can't silently regress them.
 *
 * Refs: docs/specs/control-tower-redesign.md (AC-2, AC-5, D-5)
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const uiDir = resolve(__dirname, "../../app/components/ui");

function read(file: string): string {
  return readFileSync(resolve(uiDir, file), "utf-8");
}

describe("AsyncSurface triad [AC-2, D-5]", () => {
  const src = read("AsyncSurface.tsx");

  it("renders an error branch with a Retry affordance", () => {
    expect(src).toMatch(/if \(error\)/);
    expect(src).toContain("onRetry");
    expect(src).toContain("Retry");
  });

  it("renders a loading branch with an accessible busy state", () => {
    expect(src).toMatch(/if \(loading\)/);
    expect(src).toContain('aria-busy="true"');
    expect(src).toContain('role="status"');
  });

  it("renders an empty branch distinct from loading and error", () => {
    expect(src).toMatch(/if \(empty\)/);
  });

  it("error takes precedence over loading", () => {
    // The error guard must appear before the loading guard so a failed refresh
    // of already-shown data still surfaces.
    expect(src.indexOf("if (error)")).toBeLessThan(src.indexOf("if (loading)"));
  });
});

describe("StatusDot / StatusBadge accessibility [AC-2, AC-5]", () => {
  it("StatusDot always emits a label (sr-only or visible)", () => {
    const src = read("StatusDot.tsx");
    expect(src).toContain("sr-only");
    // The coloured dot itself is decorative; the label carries the meaning.
    expect(src).toContain('aria-hidden="true"');
  });

  it("StatusBadge renders its label text inline (not colour-only)", () => {
    const src = read("StatusBadge.tsx");
    expect(src).toContain("{text}");
    expect(src).toContain('aria-hidden="true"');
  });
});
