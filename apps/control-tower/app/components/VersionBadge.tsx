/**
 * VersionBadge — Server Component
 *
 * Reads WALTER_VERSION and WALTER_UPDATE_AVAILABLE env vars (set by
 * docker compose from the repo's VERSION file) and renders:
 *   - Current version: "v0.2.0"
 *   - When update available: "Update available: v0.3.0 → changelog" badge
 *
 * Visual only. No automatic update logic.
 * AC-5: docs/specs/phase-w-7-versioning-release.md
 */

import { getVersionInfo } from "@/lib/version";

const REPO_URL =
  process.env.NEXT_PUBLIC_WALTER_REPO_URL ??
  "https://github.com/xipher-labs/walter-os";
const CHANGELOG_URL = `${REPO_URL}/blob/main/CHANGELOG.md`;

export default function VersionBadge() {
  const { version, updateAvailable, showBadge } = getVersionInfo();

  if (!version) return null;

  return (
    <div className="flex items-center gap-2 text-xs font-mono">
      <span
        className="text-zinc-400 dark:text-zinc-500"
        data-testid="version-label"
      >
        v{version}
      </span>

      {showBadge && updateAvailable && (
        <a
          href={CHANGELOG_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full
                     bg-amber-100 dark:bg-amber-900/40
                     text-amber-800 dark:text-amber-300
                     border border-amber-300 dark:border-amber-700
                     hover:bg-amber-200 dark:hover:bg-amber-800/50
                     transition-colors"
          data-testid="update-badge"
        >
          Update available: v{updateAvailable} → changelog
        </a>
      )}
    </div>
  );
}
