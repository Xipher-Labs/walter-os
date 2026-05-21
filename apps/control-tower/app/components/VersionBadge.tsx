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

// Repo URL is provided by the operator's deployment via
// NEXT_PUBLIC_WALTER_REPO_URL. We intentionally avoid a hardcoded fallback
// to any specific GitHub org so the Control Tower doesn't ship a personal
// identifier or a wrong-fork URL — see W-5 / R2-3 in the OSS launch spec
// and the depersonalization re-audit. If the env var is unset OR empty,
// the update badge is rendered without a link target.
//
// Normalization (Copilot R2 of #73):
//   1. Treat empty-string / whitespace-only as unset (.env files commonly
//      ship `KEY=` which becomes `""`, not `undefined`).
//   2. Strip trailing slash so `https://example.com/foo/` and
//      `https://example.com/foo` produce the same CHANGELOG_URL — avoids
//      the `.../foo//blob/main/CHANGELOG.md` double-slash artifact.
function _normalizeRepoUrl(raw: string | undefined | null): string | null {
  if (raw === undefined || raw === null) return null;
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  return trimmed.replace(/\/+$/, "");
}
const REPO_URL = _normalizeRepoUrl(process.env.NEXT_PUBLIC_WALTER_REPO_URL);
const CHANGELOG_URL = REPO_URL ? `${REPO_URL}/blob/main/CHANGELOG.md` : null;

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
        CHANGELOG_URL ? (
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
        ) : (
          // Operator hasn't set NEXT_PUBLIC_WALTER_REPO_URL. Render the
          // text badge without a link so the user still sees the update
          // notice; no hardcoded URL leaks into the page.
          <span
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full
                       bg-amber-100 dark:bg-amber-900/40
                       text-amber-800 dark:text-amber-300
                       border border-amber-300 dark:border-amber-700"
            data-testid="update-badge-no-link"
            title="Set NEXT_PUBLIC_WALTER_REPO_URL to enable the changelog link"
          >
            Update available: v{updateAvailable}
          </span>
        )
      )}
    </div>
  );
}
