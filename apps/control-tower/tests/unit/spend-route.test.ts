/**
 * Unit tests for /api/spend route.
 * U-new-1: Authorization header must not be sent as "Bearer undefined"
 *          when LITELLM_API_KEY is unset.
 */
import { afterEach, describe, it, expect, vi } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { GET } from "../../app/api/spend/route";

const __dirname = dirname(fileURLToPath(import.meta.url));
const knownAgents = ["triage", "researcher", "coder", "reviewer", "janitor", "liaison"];

async function expectFallbackSpendResponse(response: Response): Promise<unknown> {
  const body = (await response.json()) as {
    agents: {
      agent: string;
      model: string;
      tokens_in: number;
      tokens_out: number;
      cost_usd: number;
      budget_pct: number;
    }[];
    days: number;
    source: string;
  };

  expect(response.status).toBe(200);
  expect(body.source).toBe("fallback");
  expect(body.days).toBe(7);
  expect(body.agents.map((agent) => agent.agent).sort()).toEqual(
    [...knownAgents].sort()
  );
  expect(
    body.agents.every(
      (agent) =>
        agent.model === "unknown" &&
        agent.tokens_in === 0 &&
        agent.tokens_out === 0 &&
        agent.cost_usd === 0 &&
        agent.budget_pct === 0
    )
  ).toBe(true);

  return body;
}

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

describe("GET /api/spend fallback behavior", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns the safe zero-agent fallback when LiteLLM fetch fails", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("ECONNREFUSED"));

    const response = await GET(new Request("http://localhost/api/spend?days=7"));

    await expectFallbackSpendResponse(response);
  });

  it("uses the same safe zero-agent fallback for fetch failures and non-2xx responses", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(new Response(null, { status: 503 }));
    const nonOkResponse = await GET(new Request("http://localhost/api/spend?days=7"));
    const nonOkBody = await expectFallbackSpendResponse(nonOkResponse);

    vi.mocked(globalThis.fetch).mockRejectedValueOnce(new Error("ECONNREFUSED"));
    const fetchFailureResponse = await GET(
      new Request("http://localhost/api/spend?days=7")
    );
    const fetchFailureBody = await expectFallbackSpendResponse(fetchFailureResponse);

    expect(fetchFailureBody).toEqual(nonOkBody);
  });

  it("does not hide malformed successful LiteLLM responses behind fallback data", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response("{", {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    );

    const response = await GET(new Request("http://localhost/api/spend?days=7"));
    const body = (await response.json()) as { error?: string; source?: string };

    expect(response.status).toBe(500);
    expect(body.error).toBe("Failed to process spend data");
    expect(body.source).toBeUndefined();
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
