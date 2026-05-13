/**
 * version-badge-url.test.ts
 * Regression guard: CHANGELOG_URL in VersionBadge must be configurable via
 * NEXT_PUBLIC_WALTER_REPO_URL, not hardcoded to the operator's personal repo.
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
  let source: string;

  it("loads VersionBadge.tsx", () => {
    source = readFileSync(BADGE_PATH, "utf-8");
    expect(source).toBeTruthy();
  });

  it("does not hardcode the operator personal GitHub URL (nicofernandez)", () => {
    source = source ?? readFileSync(BADGE_PATH, "utf-8");
    expect(source).not.toContain("nicofernandez");
  });

  it("references NEXT_PUBLIC_WALTER_REPO_URL env var", () => {
    source = source ?? readFileSync(BADGE_PATH, "utf-8");
    expect(source).toContain("NEXT_PUBLIC_WALTER_REPO_URL");
  });
});
