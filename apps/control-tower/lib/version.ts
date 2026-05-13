/**
 * lib/version.ts
 *
 * Reads WALTER_VERSION and WALTER_UPDATE_AVAILABLE environment variables
 * and returns structured data for the Control Tower version badge display.
 *
 * WALTER_VERSION    — set by docker compose or start script from the repo's
 *                     VERSION file: WALTER_VERSION=$(cat VERSION)
 * WALTER_UPDATE_AVAILABLE — set by an optional background check script when
 *                     a newer GitHub release is detected. Contains the new
 *                     version string (e.g. "0.3.0"). Visual only — no auto-update.
 *
 * AC-5: Control Tower reads VERSION (via env var) and displays it in header.
 *       Shows "Update available: vX.Y.Z → changelog" badge when update available.
 */

export interface VersionInfo {
  /** Current version string (e.g. "0.2.0"), or null if env var not set. */
  version: string | null;
  /** New version string if an update is available, or null. */
  updateAvailable: string | null;
  /** True when updateAvailable is non-null — convenience flag for badge visibility. */
  showBadge: boolean;
}

/**
 * getVersionInfo reads env vars and returns badge display data.
 * Works in both server components (Node.js process.env) and during tests.
 */
export function getVersionInfo(): VersionInfo {
  const version = process.env.WALTER_VERSION ?? null;
  const updateAvailable = process.env.WALTER_UPDATE_AVAILABLE ?? null;

  return {
    version: version || null,
    updateAvailable: updateAvailable || null,
    showBadge: Boolean(updateAvailable),
  };
}
