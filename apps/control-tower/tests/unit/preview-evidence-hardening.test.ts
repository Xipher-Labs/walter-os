import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("preview evidence hardening", () => {
  it("parses the mock LiteLLM port as a number", () => {
    const source = readFileSync(
      new URL("../e2e/mock-litellm.mjs", import.meta.url),
      "utf8"
    );

    expect(source).toContain("Number.parseInt");
    expect(source).toContain("LITELLM_MOCK_PORT");
    expect(source).toContain("server.listen(PORT");
  });

  it("uses noopener on external preview links", () => {
    const source = readFileSync(
      new URL("../../app/components/PreviewEvidencePanel.tsx", import.meta.url),
      "utf8"
    );

    expect(source).toContain('rel="noopener noreferrer"');
  });
});
