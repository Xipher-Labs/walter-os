/**
 * version-badge-url.test.ts
 * Regression guard: CHANGELOG_URL in VersionBadge must be configurable via
 * NEXT_PUBLIC_WALTER_REPO_URL, not hardcoded to any specific repo owner.
 *
 * Refs: PR-47-copilot-round-2 (R2-3)
 * Refs: docs/specs/walter-oss-launch.md (W-5 depersonalization)
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve } from "path";

const BADGE_PATH = resolve(
  __dirname,
  "../../app/components/VersionBadge.tsx"
);

describe("VersionBadge — CHANGELOG_URL depersonalization [R2-3]", () => {
  // Hoist the file read into a once-per-suite constant so each test is
  // independent of execution order and `source` is never read before
  // assignment (TS strict mode flagged the previous source ??= pattern
  // — Copilot R2 of #73).
  const source = readFileSync(BADGE_PATH, "utf-8");

  it("loads VersionBadge.tsx", () => {
    expect(source).toBeTruthy();
  });

  it("does not hardcode any github.com/<owner>/walter-os URL", () => {
    // Reject hardcoded github.com paths for the walter-os repo, regardless
    // of owner. The component must read the URL from
    // NEXT_PUBLIC_WALTER_REPO_URL at runtime. This catches both the
    // legacy pre-OSS owner string and any future regression that hardcodes
    // a different fork URL.
    const hardcodedRepoPath = /github\.com\/[A-Za-z0-9_-]+\/walter-os/;
    expect(source).not.toMatch(hardcodedRepoPath);
  });

  it("references NEXT_PUBLIC_WALTER_REPO_URL env var", () => {
    expect(source).toContain("NEXT_PUBLIC_WALTER_REPO_URL");
  });

  it("normalizes empty-string env to null (Copilot R2 of #73)", () => {
    // Empty NEXT_PUBLIC_WALTER_REPO_URL='' must NOT produce
    // CHANGELOG_URL='/blob/main/CHANGELOG.md' (a broken relative link).
    // The fix is in _normalizeRepoUrl() — verify the helper exists.
    expect(source).toContain("_normalizeRepoUrl");
    expect(source).toMatch(/trimmed\s*===\s*""/);
  });

  it("strips trailing slash so REPO_URL=...foo/ doesn't double-slash", () => {
    // Trailing-slash normalization avoids '/foo//blob/main/CHANGELOG.md'.
    expect(source).toMatch(/replace\(\s*\/\\\/\+\$\/\s*,\s*""\s*\)/);
  });
});
