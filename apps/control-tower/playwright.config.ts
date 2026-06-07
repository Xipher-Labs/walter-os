import { defineConfig, devices } from "@playwright/test";

const controlTowerE2EToken =
  process.env.CONTROL_TOWER_ADMIN_TOKEN ?? "control-tower-e2e-token";
const webServerPort = process.env.PORT ?? "3000";
const baseURL = process.env.BASE_URL ?? `http://localhost:${webServerPort}`;

/**
 * Playwright config for Control Tower E2E smoke tests.
 * Tests run against a locally started Next.js server.
 *
 * Tailscale enforcement is disabled via TAILSCALE_ENFORCE=false in the
 * test environment so localhost connections are allowed.
 */
export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 30_000,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "github" : "list",

  use: {
    baseURL,
    extraHTTPHeaders: {
      Authorization: `Bearer ${controlTowerE2EToken}`,
    },
    trace: "on-first-retry",
  },

  // Start the Next.js standalone server for smoke tests.
  // - output:"standalone" writes server.js under the workspace-relative
  //   .next/standalone/apps/control-tower/ directory.
  // - Check SKIP_WEBSERVER === "true" (not just truthy) so that
  //   SKIP_WEBSERVER=false (CI default) correctly starts the server.
  webServer: process.env.SKIP_WEBSERVER === "true"
    ? undefined
    : {
        command:
          "rm -rf .next/standalone/apps/control-tower/.next/static .next/standalone/apps/control-tower/public && " +
          "mkdir -p .next/standalone/apps/control-tower/.next && " +
          "cp -R .next/static .next/standalone/apps/control-tower/.next/static && " +
          "cp -R public .next/standalone/apps/control-tower/public && " +
          "node .next/standalone/apps/control-tower/server.js",
        url: `${baseURL}/api/health`,
        reuseExistingServer: !process.env.CI,
        timeout: 60_000,
        env: {
          NODE_ENV: "production",
          PORT: webServerPort,
          HOSTNAME: "0.0.0.0",
          CONTROL_TOWER_ADMIN_TOKEN: controlTowerE2EToken,
          TAILSCALE_ENFORCE: "false",
          WALTER_COUNCIL_DATA_DIR: "/tmp/test-council-data",
          WALTER_COUNCIL_LOG_DIR: "/tmp/test-council-logs",
          WALTER_CONFIG_DIR: "/tmp/test-walter-config",
          WALTER_VERSION: "0.0.0-test",
          WALTER_UPDATE_AVAILABLE: "0.0.1-test",
        },
      },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
