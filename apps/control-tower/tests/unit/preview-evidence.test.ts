import { chmod, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { describe, expect, it } from "vitest";
import { readPreviewEvidence } from "../../lib/preview-evidence";

const SHA256 = "a".repeat(64);

async function makeRoot() {
  return mkdtemp(join(tmpdir(), "walter-preview-evidence-"));
}

async function writeJson(path: string, payload: unknown) {
  await writeFile(path, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

async function writeSeed(bundle: string) {
  await mkdir(join(bundle, "seed"), { recursive: true });
  await writeFile(join(bundle, "seed", "seed.json"), "{}", "utf8");
}

describe("readPreviewEvidence", () => {
  it("returns an empty filesystem source when the preview root is absent", async () => {
    const root = join(await makeRoot(), "missing");

    await expect(readPreviewEvidence(root)).resolves.toEqual({
      root,
      source: "missing",
      previews: [],
    });
  });

  it("summarizes a valid preview report bundle as complete evidence", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-235");
    await mkdir(join(bundle, "screenshots"), { recursive: true });
    await writeSeed(bundle);
    await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 235,
      url: "https://preview.example/pr-235",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-235",
      seed_manifest: {
        path: ".walter/previews/preview-pr-235/seed/seed.json",
        sha256: SHA256,
      },
      screenshots: [
        {
          path: ".walter/previews/preview-pr-235/screenshots/home.png",
          sha256: SHA256,
        },
      ],
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.source).toBe("filesystem");
    expect(evidence.previews).toHaveLength(1);
    expect(evidence.previews[0]).toMatchObject({
      pr: 235,
      status: "complete",
      statusLabel: "Bundle ready",
      bundleDir: "preview-pr-235",
      url: "https://preview.example/pr-235",
      screenshots: 1,
      hasReport: true,
      hasPlan: false,
      safetyOk: true,
      findings: [],
    });
  });

  it("fails closed when the preview root cannot be read", async () => {
    const root = await makeRoot();
    await chmod(root, 0o000);

    try {
      await expect(readPreviewEvidence(root)).resolves.toEqual({
        root,
        source: "missing",
        previews: [],
      });
    } finally {
      await chmod(root, 0o700);
    }
  });

  it("invalidates reports whose screenshot files are missing on disk", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-240");
    await mkdir(bundle, { recursive: true });
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 240,
      url: "https://preview.example/pr-240",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-240",
      seed_manifest: { path: "seed/seed.json", sha256: SHA256 },
      screenshots: [{ path: "screenshots/home.png", sha256: SHA256 }],
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 240,
      status: "invalid",
      statusLabel: "Needs attention",
      screenshots: 0,
      hasReport: true,
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toContain(
      "preview report screenshot files missing or unreadable on disk"
    );
  });

  it("invalidates reports with malformed artifact paths", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-242");
    await mkdir(join(bundle, "screenshots"), { recursive: true });
    await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 242,
      url: "https://preview.example/pr-242",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-242",
      seed_manifest: { sha256: SHA256 },
      screenshots: [{ sha256: SHA256 }],
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 242,
      status: "invalid",
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toEqual(
      expect.arrayContaining([
        "preview report seed path is missing or invalid",
        "preview report screenshot path is missing or invalid",
      ])
    );
  });

  it("invalidates reports that reference missing screenshot basenames", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-243");
    await mkdir(join(bundle, "screenshots"), { recursive: true });
    await writeSeed(bundle);
    await writeFile(join(bundle, "screenshots", "other.png"), "png", "utf8");
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 243,
      url: "https://preview.example/pr-243",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-243",
      seed_manifest: { path: "seed/seed.json", sha256: SHA256 },
      screenshots: [{ path: "screenshots/home.png", sha256: SHA256 }],
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 243,
      status: "invalid",
      screenshots: 1,
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toContain(
      "preview report screenshot files missing or unreadable on disk"
    );
  });

  it("invalidates reports whose seed file is missing on disk", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-246");
    await mkdir(join(bundle, "screenshots"), { recursive: true });
    await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 246,
      url: "https://preview.example/pr-246",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-246",
      seed_manifest: { path: "seed/seed.json", sha256: SHA256 },
      screenshots: [{ path: "screenshots/home.png", sha256: SHA256 }],
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 246,
      status: "invalid",
      screenshots: 1,
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toContain(
      "preview report seed file missing or unreadable on disk"
    );
  });

  it("invalidates reports whose seed path escapes the seed directory", async () => {
    for (const [pr, seedPath] of [
      [247, "../seed.json"],
      [249, "/tmp/seed.json"],
    ] as const) {
      const root = await makeRoot();
      const bundle = join(root, `preview-pr-${pr}`);
      await mkdir(join(bundle, "screenshots"), { recursive: true });
      await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");
      await writeJson(join(bundle, "preview-report.json"), {
        schema_version: 1,
        pr,
        url: `https://preview.example/pr-${pr}`,
        generated_at: "2026-06-04T12:00:00Z",
        bundle_dir: `.walter/previews/preview-pr-${pr}`,
        seed_manifest: { path: seedPath, sha256: SHA256 },
        screenshots: [{ path: "screenshots/home.png", sha256: SHA256 }],
        safety: {
          production_secrets: "rejected",
          credentials: "not minted",
          deploy: "not performed",
          hard_limit_floor: "preserved",
        },
      });

      const evidence = await readPreviewEvidence(root);

      expect(evidence.previews[0]).toMatchObject({
        pr,
        status: "invalid",
        safetyOk: false,
      });
      expect(evidence.previews[0].findings).toContain(
        "preview report seed path escapes seed directory"
      );
    }
  });

  it("invalidates reports whose screenshot path escapes screenshots", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-248");
    await mkdir(join(bundle, "screenshots"), { recursive: true });
    await writeSeed(bundle);
    await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 248,
      url: "https://preview.example/pr-248",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-248",
      seed_manifest: { path: "seed/seed.json", sha256: SHA256 },
      screenshots: [{ path: "../screenshots/home.png", sha256: SHA256 }],
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 248,
      status: "invalid",
      screenshots: 1,
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toContain(
      "preview report screenshot path escapes screenshots directory"
    );
  });

  it("reports unreadable preview files separately from malformed JSON", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-241");
    const reportPath = join(bundle, "preview-report.json");
    await mkdir(bundle, { recursive: true });
    await writeFile(reportPath, "{}", "utf8");
    await chmod(reportPath, 0o000);

    try {
      const evidence = await readPreviewEvidence(root);

      expect(evidence.previews[0]).toMatchObject({
        pr: 241,
        status: "invalid",
        hasReport: true,
        safetyOk: false,
      });
      expect(evidence.previews[0].findings).toContain(
        "preview report cannot be read"
      );
      expect(evidence.previews[0].findings).not.toContain(
        "preview report is not valid JSON"
      );
    } finally {
      await chmod(reportPath, 0o600);
    }
  });

  it("reports unreadable screenshot directories", async () => {
    const root = await makeRoot();
    const screenshotsPath = join(root, "preview-pr-245", "screenshots");
    await mkdir(screenshotsPath, { recursive: true });
    await chmod(screenshotsPath, 0o000);

    try {
      const evidence = await readPreviewEvidence(root);

      expect(evidence.previews[0]).toMatchObject({
        pr: 245,
        status: "invalid",
        screenshots: 0,
        safetyOk: false,
      });
      expect(evidence.previews[0].findings).toContain(
        "screenshots directory cannot be read"
      );
    } finally {
      await chmod(screenshotsPath, 0o700);
    }
  });

  it("keeps a valid dry-run plan separate from captured report evidence", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-236");
    await mkdir(bundle, { recursive: true });
    await writeJson(join(bundle, "preview-plan.json"), {
      schema_version: 1,
      kind: "preview-plan",
      pr: 236,
      provider: "vercel",
      app: "control-tower",
      branch: "codex/preview",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-236",
      seed_manifest: { path: "seed/seed.json", sha256: SHA256 },
      actions: [
        "deploy_ephemeral_preview",
        "apply_seed_fixture",
        "capture_screenshots",
        "write_preview_bundle",
      ],
      safety: {
        dry_run: true,
        preview_deploy: true,
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 236,
      status: "planned",
      statusLabel: "Dry-run plan",
      provider: "vercel",
      app: "control-tower",
      branch: "codex/preview",
      screenshots: 0,
      hasReport: false,
      hasPlan: true,
      safetyOk: true,
      findings: ["preview report missing"],
    });
  });

  it("invalidates preview plans with malformed seed paths", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-244");
    await mkdir(bundle, { recursive: true });
    await writeJson(join(bundle, "preview-plan.json"), {
      schema_version: 1,
      kind: "preview-plan",
      pr: 244,
      provider: "vercel",
      app: "control-tower",
      branch: "codex/preview",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-244",
      seed_manifest: { sha256: SHA256 },
      actions: [
        "deploy_ephemeral_preview",
        "apply_seed_fixture",
        "capture_screenshots",
        "write_preview_bundle",
      ],
      safety: {
        dry_run: true,
        preview_deploy: true,
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 244,
      status: "invalid",
      hasPlan: true,
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toContain(
      "preview plan seed path is missing or invalid"
    );
  });

  it("invalidates preview plans with blank required strings", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-250");
    await mkdir(bundle, { recursive: true });
    await writeJson(join(bundle, "preview-plan.json"), {
      schema_version: 1,
      kind: "preview-plan",
      pr: 250,
      provider: "   ",
      app: "control-tower",
      branch: "codex/preview",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-250",
      seed_manifest: { path: "seed/seed.json", sha256: SHA256 },
      actions: [
        "deploy_ephemeral_preview",
        "apply_seed_fixture",
        "capture_screenshots",
        "write_preview_bundle",
      ],
      safety: {
        dry_run: true,
        preview_deploy: true,
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved",
      },
    });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 250,
      status: "invalid",
      provider: null,
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toContain(
      "preview plan provider is missing"
    );
  });

  it("surfaces screenshot-only captures as partial evidence", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-237");
    await mkdir(join(bundle, "screenshots"), { recursive: true });
    await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 237,
      status: "captured",
      statusLabel: "Screenshot only",
      screenshots: 1,
      hasReport: false,
      hasPlan: false,
      safetyOk: false,
      findings: ["preview report missing", "dry-run plan missing"],
    });
  });

  it("explains empty preview directories instead of showing no findings", async () => {
    const root = await makeRoot();
    await mkdir(join(root, "preview-pr-239"), { recursive: true });

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 239,
      status: "invalid",
      statusLabel: "Needs attention",
      screenshots: 0,
      hasReport: false,
      hasPlan: false,
      safetyOk: false,
      findings: ["preview evidence missing"],
    });
  });

  it("limits preview evidence to the most recent bundles", async () => {
    const root = await makeRoot();
    for (let pr = 1; pr <= 55; pr += 1) {
      await mkdir(join(root, `preview-pr-${pr}`), { recursive: true });
    }

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews).toHaveLength(50);
    expect(evidence.previews[0].pr).toBe(55);
    expect(evidence.previews[49].pr).toBe(6);
    expect(evidence.previews.map((preview) => preview.pr)).not.toContain(5);
  });

  it("marks malformed or mismatched evidence invalid without throwing", async () => {
    const root = await makeRoot();
    const bundle = join(root, "preview-pr-238");
    await mkdir(bundle, { recursive: true });
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 999,
      url: "https://preview.example/pr-999",
      safety: { production_secrets: "copied" },
    });
    await writeFile(join(bundle, "preview-plan.json"), "{not-json", "utf8");

    const evidence = await readPreviewEvidence(root);

    expect(evidence.previews[0]).toMatchObject({
      pr: 238,
      status: "invalid",
      statusLabel: "Needs attention",
      safetyOk: false,
    });
    expect(evidence.previews[0].findings).toEqual(
      expect.arrayContaining([
        "preview report PR does not match directory",
        "preview report safety invariants failed",
        "preview plan is not valid JSON",
      ])
    );
  });
});
