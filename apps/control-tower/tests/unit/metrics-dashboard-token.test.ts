/**
 * Unit tests for MetricsDashboard component.
 * U-new-2: Grafana SA token must not appear in the iframe src URL.
 *          Tokens in URL query strings are exposed in browser history,
 *          server access logs, and Referer headers.
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

describe("MetricsDashboard token-in-URL static analysis", () => {
  it("U-new-2: MetricsDashboard.tsx does not put auth_token in URLSearchParams", () => {
    const content = readFileSync(
      resolve(__dirname, "../../app/components/MetricsDashboard.tsx"),
      "utf-8"
    );
    // The broken pattern: auth_token added to URLSearchParams (appears in iframe src)
    const hasAuthTokenInParams = content.includes("auth_token");
    expect(hasAuthTokenInParams).toBe(false);
  });

  it("U-new-2: MetricsDashboard.tsx does not interpolate token directly into URL", () => {
    const content = readFileSync(
      resolve(__dirname, "../../app/components/MetricsDashboard.tsx"),
      "utf-8"
    );
    // Also guard against direct URL interpolation like `?token=${token}`
    const hasTokenInUrl = /[?&](?:auth_token|token)=\$\{/.test(content);
    expect(hasTokenInUrl).toBe(false);
  });
});
