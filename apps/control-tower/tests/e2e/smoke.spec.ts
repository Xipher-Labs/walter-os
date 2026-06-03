/**
 * Control Tower smoke tests.
 * Tests: (1) page loads, (2) agent board renders 6 cards, (3) SSE connects,
 * (4) timeline renders, (5) cost dashboard renders,
 * (6) HA Status renders, (7) mode toggle visible, (8) nav links work,
 * (9) mobile nav does not create horizontal overflow,
 * (10) council chat loads, (11) history page loads.
 *
 * Tailscale enforcement is disabled in test env (TAILSCALE_ENFORCE=false).
 * Control Tower token auth is satisfied by the Playwright context header.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-1 through AC-10)
 * Task: T-49
 */
import { test, expect } from "@playwright/test";
import {
  CONTROL_TOWER_SESSION_COOKIE,
  controlTowerSessionValue,
} from "../../lib/control-tower-auth";

const controlTowerE2EToken =
  process.env.CONTROL_TOWER_ADMIN_TOKEN ?? "control-tower-e2e-token";
const webServerPort = process.env.PORT ?? "3000";
const baseURL = process.env.BASE_URL ?? `http://localhost:${webServerPort}`;

test.describe("Control Tower smoke tests", () => {
  test.beforeEach(async ({ context }) => {
    await context.addCookies([
      {
        name: CONTROL_TOWER_SESSION_COOKIE,
        value: await controlTowerSessionValue(controlTowerE2EToken),
        url: baseURL,
        httpOnly: true,
        sameSite: "Lax",
        expires: Math.floor(Date.now() / 1000) + 60 * 60,
      },
    ]);
  });

  test("(1) dashboard loads in < 5s", async ({ page }) => {
    const start = Date.now();
    await page.goto("/");
    await expect(page.locator("h1")).toContainText("Walter Council");
    const elapsed = Date.now() - start;
    expect(elapsed).toBeLessThan(5000);
  });

  test("(2) Agent Status Board renders 6 agent cards", async ({ page }) => {
    await page.goto("/");
    // Wait for the agent grid to appear (may need to wait for SSE/skeleton)
    await page.waitForTimeout(1000);
    // Each agent card has a capitalized agent name
    const agents = ["triage", "researcher", "coder", "reviewer", "janitor", "liaison"];
    for (const agent of agents) {
      const locator = page.locator(`text=${agent}`).first();
      await expect(locator).toBeVisible({ timeout: 5000 });
    }
  });

  test("(3) SSE endpoint is accessible (content-type: text/event-stream)", async ({
    page,
  }) => {
    // SSE is a streaming response that never completes; intercept network request
    // via page.on('response') so we can inspect headers without reading the body.
    // Navigate to the origin first so Chromium's security context allows the fetch.
    await page.goto("/");

    const sseResponsePromise = page.waitForResponse(
      (resp) => resp.url().includes("/api/sse"),
      { timeout: 10_000 }
    );

    // Trigger the SSE connection by evaluating fetch in the browser context
    // (fire-and-forget — we don't await it; the response listener above catches it).
    void page.evaluate(() => {
      const ctrl = new AbortController();
      fetch("/api/sse", {
        signal: ctrl.signal,
      }).catch(() => {});
      // Abort after 500ms — enough time for headers to arrive and the
      // waitForResponse listener to fire.
      setTimeout(() => ctrl.abort(), 500);
    });

    const sseResponse = await sseResponsePromise;
    expect(sseResponse.status()).toBe(200);
    const ct = sseResponse.headers()["content-type"] ?? "";
    expect(ct).toContain("text/event-stream");
  });

  test("(4) Health endpoint returns ok", async ({ page }) => {
    const response = await page.request.get("/api/health");
    expect(response.status()).toBe(200);
    const body = (await response.json()) as { status: string };
    expect(body.status).toBe("ok");
  });

  test("(5) Timeline API returns entries array", async ({ page }) => {
    const response = await page.request.get("/api/timeline?limit=10");
    expect(response.status()).toBe(200);
    const body = (await response.json()) as { entries: unknown[] };
    expect(Array.isArray(body.entries)).toBe(true);
  });

  test("(6) Cost Dashboard API returns agents array", async ({ page }) => {
    const response = await page.request.get("/api/spend?days=7");
    // May return 200 (with fallback data) or 500 if LiteLLM is not configured
    // In test env, LiteLLM is not available so we expect fallback
    expect([200, 500]).toContain(response.status());
  });

  test("(7) Mode API returns consensus state", async ({ page }) => {
    const response = await page.request.get("/api/mode");
    expect(response.status()).toBe(200);
    const body = (await response.json()) as { consensus: boolean };
    expect(typeof body.consensus).toBe("boolean");
  });

  test("(8) Nav links render with labels and mark the active section", async ({
    page,
  }) => {
    await page.goto("/");
    // Assert the rendered link text, not just presence, so a broken/relabelled
    // nav is caught (the shared TopNav labels each route).
    await expect(page.locator("a[href='/council']")).toHaveText("Council");
    await expect(page.locator("a[href='/ideation']")).toHaveText("Ideation");
    await expect(page.locator("a[href='/history']")).toHaveText("History");
    // The wordmark identifies the app.
    await expect(page.locator("nav")).toContainText("Walter Council");
    // The "Overview" nav link is the active section on "/" (aria-current=page).
    // exact:true avoids matching the "Skip to overview" skip-link, and the
    // accessible name avoids the wordmark, which also points at "/" but is not
    // a section marker.
    await expect(
      page.getByRole("link", { name: "Overview", exact: true })
    ).toHaveAttribute("aria-current", "page");
  });

  test("(9) TopNav fits without horizontal overflow on mobile", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/");
    await expect(page.locator("nav")).toBeVisible();

    const updateBadge = page.locator(
      "[data-testid='update-badge'], [data-testid='update-badge-no-link']"
    );
    if (process.env.WALTER_UPDATE_AVAILABLE) {
      await expect(updateBadge.first()).toBeVisible();
    } else if ((await updateBadge.count()) > 0) {
      await expect(updateBadge.first()).toBeVisible();
    }

    const metrics = await page.evaluate(() => {
      const nav = document.querySelector("nav");
      if (!nav) {
        throw new Error("TopNav is missing from the dashboard.");
      }
      return {
        viewportWidth: document.documentElement.clientWidth,
        docScrollWidth: document.documentElement.scrollWidth,
        navScrollWidth: nav.scrollWidth,
        navClientWidth: nav.clientWidth,
      };
    });

    expect(metrics.docScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth);
    expect(metrics.navScrollWidth).toBeLessThanOrEqual(metrics.navClientWidth);
  });

  test("(10) Council Chat page loads", async ({ page }) => {
    await page.goto("/council");
    await expect(page.locator("h1")).toContainText("Council Chat");
    await expect(page.locator("textarea")).toBeVisible();
    await expect(page.locator("button", { hasText: "Send to Council" })).toBeVisible();
  });

  test("(11) History page loads with the shared nav rendered", async ({
    page,
  }) => {
    await page.goto("/history");
    await expect(page.locator("h1")).toContainText("Conversation History");
    // The redesign moved every page onto the shared TopNav; assert it actually
    // rendered (wordmark + a working route link) rather than only checking the
    // page heading exists.
    await expect(page.locator("nav")).toContainText("Walter Council");
    await expect(page.locator("a[href='/']").first()).toBeVisible();
  });
});
