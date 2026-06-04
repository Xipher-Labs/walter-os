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
    await writeFile(join(bundle, "screenshots", "home.png"), "png", "utf8");
    await writeJson(join(bundle, "preview-report.json"), {
      schema_version: 1,
      pr: 235,
      url: "https://preview.example/pr-235",
      generated_at: "2026-06-04T12:00:00Z",
      bundle_dir: ".walter/previews/preview-pr-235",
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
      "preview report screenshot files missing on disk"
    );
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
