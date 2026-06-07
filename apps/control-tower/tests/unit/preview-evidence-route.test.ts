import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { resolvePreviewRoot } from "../../app/api/preview-evidence/route";

describe("preview evidence route", () => {
  it("uses WALTER_PREVIEW_ROOT when the operator configures one", () => {
    expect(
      resolvePreviewRoot("/repo/apps/control-tower", "../previews")
    ).toBe(resolve("/repo/apps/previews"));
  });

  it("trims configured preview roots before resolving them", () => {
    expect(
      resolvePreviewRoot("/repo/apps/control-tower", "  ../previews  ")
    ).toBe(resolve("/repo/apps/previews"));
  });

  it("defaults to the repository .walter previews directory", () => {
    expect(
      resolvePreviewRoot("/repo/apps/control-tower", undefined, () => false)
    ).toBe(resolve("/repo/.walter/previews"));
  });

  it("uses cwd .walter previews when running from a packaged app root", () => {
    expect(
      resolvePreviewRoot("/app", undefined, (path) =>
        path === resolve("/app/.walter/previews")
      )
    ).toBe(resolve("/app/.walter/previews"));
  });

  it("does not fall back to the filesystem root from packaged app roots", () => {
    expect(resolvePreviewRoot("/app", undefined, () => false)).toBe(
      resolve("/app/.walter/previews")
    );
  });
});
