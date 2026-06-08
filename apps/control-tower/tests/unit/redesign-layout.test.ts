import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Static-analysis coverage for the redesign layout acceptance criteria that
 * previously had no test (DoD gate). Mirrors the readFileSync pattern of the
 * other unit tests (e.g. status-tokens.test.ts).
 *
 * AC-1: dark default applied on <html> + status tokens defined in both theme
 *       blocks of globals.css.
 * AC-3: the overview page uses the responsive grid breakpoints with at least
 *       one full-width span.
 *
 * Refs: docs/specs/control-tower-redesign.md (AC-1, AC-3)
 */

// This file lives in tests/unit/, so the app root is two levels up.
const root = join(__dirname, "..", "..");

describe("redesign layout — AC-1 (dark default + themed tokens)", () => {
  it("applies the dark theme class on <html> in the root layout", () => {
    const src = readFileSync(join(root, "app/layout.tsx"), "utf8");
    expect(src).toMatch(/<html[\s\S]*?className=\{`[^`]*\bdark\b/);
  });

  it("defines status tokens in both the dark (:root) and light theme blocks", () => {
    const css = readFileSync(join(root, "app/globals.css"), "utf8");
    expect(css).toContain(":root");
    expect(css).toContain(".light");
    expect(css).toContain("--status-critical-fg");
    expect(css).toContain("--status-idle-fg");
    // The status tokens are redeclared per theme, so each appears in both the
    // dark and light blocks (i.e. at least twice across the file).
    const idleFgCount = css.split("--status-idle-fg:").length - 1;
    expect(idleFgCount).toBeGreaterThanOrEqual(2);
  });
});

describe("redesign layout — AC-3 (responsive overview grid)", () => {
  it("uses the responsive grid breakpoints on the overview page", () => {
    const src = readFileSync(join(root, "app/page.tsx"), "utf8");
    expect(src).toContain("xl:grid-cols-12");
    expect(src).toContain("md:grid-cols-2");
  });

  it("includes at least one full-width span across the grid", () => {
    const src = readFileSync(join(root, "app/page.tsx"), "utf8");
    expect(src).toContain("xl:col-span-12");
  });

  it("surfaces preview evidence on the overview page", () => {
    const src = readFileSync(join(root, "app/page.tsx"), "utf8");
    expect(src).toContain("PreviewEvidencePanel");
  });

  it("forces dynamic rendering for runtime operator env links", () => {
    const src = readFileSync(join(root, "app/page.tsx"), "utf8");
    expect(src).toMatch(/export\s+const\s+dynamic\s*=\s*["']force-dynamic["']/);
  });
});

describe("history page — server TopNav shell", () => {
  it("keeps /history as a Server Component so VersionBadge is not bundled client-side", () => {
    const page = readFileSync(join(root, "app/history/page.tsx"), "utf8");
    const client = readFileSync(
      join(root, "app/history/HistoryClient.tsx"),
      "utf8"
    );

    expect(page).not.toMatch(/["']use client["']/);
    expect(page).toContain("TopNav");
    expect(page).toContain("HistoryClient");
    expect(client).toMatch(/^["']use client["'];/);
    expect(client).not.toContain("TopNav");
    expect(client).not.toContain("VersionBadge");
  });
});
