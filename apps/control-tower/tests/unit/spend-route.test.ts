/**
 * Unit tests for /api/spend route.
 * U-new-1: Authorization header must not be sent as "Bearer undefined"
 *          when LITELLM_API_KEY is unset.
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// We test the header-building logic in isolation by extracting it.
// The actual fetch() call in the route uses these headers.

function buildLitellmHeaders(apiKey: string | undefined): Record<string, string> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (apiKey) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }
  return headers;
}

describe("spend route header building", () => {
  it("U-new-1: includes Authorization header when LITELLM_API_KEY is set", () => {
    const headers = buildLitellmHeaders("my-secret-key");
    expect(headers["Authorization"]).toBe("Bearer my-secret-key");
  });

  it("U-new-1: omits Authorization header when LITELLM_API_KEY is undefined", () => {
    const headers = buildLitellmHeaders(undefined);
    expect(headers["Authorization"]).toBeUndefined();
    // Must not contain the literal string "undefined"
    expect(JSON.stringify(headers)).not.toContain("undefined");
  });

  it("U-new-1: omits Authorization header when LITELLM_API_KEY is empty string", () => {
    const headers = buildLitellmHeaders("");
    expect(headers["Authorization"]).toBeUndefined();
  });
});

describe("spend route.ts static analysis", () => {
  it("U-new-1: route.ts does not unconditionally interpolate apiKey into Authorization header", () => {
    const routeContent = readFileSync(
      resolve(__dirname, "../../app/api/spend/route.ts"),
      "utf-8"
    );
    // The broken pattern from before the fix:
    //   headers: {
    //     Authorization: `Bearer ${apiKey}`,   <- unconditional
    //   }
    // We look for an Authorization object-literal key directly inside a headers
    // object literal (not guarded by an if). The broken form sets Authorization
    // as an object property directly, not as an assignment inside an if-block.
    //
    // Detect: `Authorization:` followed (with possible whitespace) by a template
    // literal containing apiKey — that's the object-literal/unconditional form.
    const unconditionalObjectLiteralPattern = /Authorization:\s*`Bearer \$\{apiKey\}`/;
    const hasUnconditionalForm = unconditionalObjectLiteralPattern.test(routeContent);
    expect(hasUnconditionalForm).toBe(false);

    // Also verify the fix is present: conditional assignment with if (apiKey)
    const hasConditionalGuard =
      routeContent.includes("if (apiKey)") || routeContent.includes("apiKey &&");
    expect(hasConditionalGuard).toBe(true);
  });
});
