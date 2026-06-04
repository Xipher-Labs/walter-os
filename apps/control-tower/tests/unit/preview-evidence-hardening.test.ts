import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { formatInvalidCountLabel } from "../../app/components/PreviewEvidencePanel";
import { redactPreviewEvidenceRoot } from "../../app/api/preview-evidence/route";
import { parseLitellmMockPort } from "../../playwright.config";

describe("preview evidence hardening", () => {
  it("rejects partially numeric mock LiteLLM ports", () => {
    const script = new URL("../e2e/mock-litellm.mjs", import.meta.url);
    let stderr = "";

    try {
      execFileSync(process.execPath, [script.pathname], {
        env: { ...process.env, LITELLM_MOCK_PORT: "4010abc" },
        stdio: "pipe",
        timeout: 500,
      });
    } catch (error) {
      stderr = String((error as { stderr?: Buffer }).stderr ?? "");
    }

    expect(stderr).toContain(
      "LITELLM_MOCK_PORT must be a positive integer"
    );
  });

  it("normalizes Playwright LiteLLM mock ports before building URLs", () => {
    expect(parseLitellmMockPort(" 4010 ")).toBe("4010");
    expect(() => parseLitellmMockPort("4010abc")).toThrow(
      "LITELLM_MOCK_PORT must be a positive integer"
    );
  });

  it("uses noopener on external preview links", () => {
    const source = readFileSync(
      new URL("../../app/components/PreviewEvidencePanel.tsx", import.meta.url),
      "utf8"
    );

    expect(source).toContain('rel="noopener noreferrer"');
  });

  it("formats invalid preview counts with singular and plural copy", () => {
    expect(formatInvalidCountLabel(1)).toBe("1 needs attention");
    expect(formatInvalidCountLabel(2)).toBe("2 need attention");
  });

  it("redacts absolute preview evidence roots from API responses", () => {
    expect(
      redactPreviewEvidenceRoot({
        root: "/srv/walter/.walter/previews",
        source: "filesystem",
        previews: [],
      }).root
    ).toBe("[redacted]");
  });

  it("keeps stale preview evidence data on transient refresh failures", () => {
    const source = readFileSync(
      new URL("../../app/components/PreviewEvidencePanel.tsx", import.meta.url),
      "utf8"
    );

    expect(source).toContain("hasDataRef");
    expect(source).toContain(
      'hasDataRef.current ? prev : "Preview evidence unavailable."'
    );
  });
});
