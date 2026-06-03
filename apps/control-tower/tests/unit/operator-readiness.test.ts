/**
 * Operator readiness panel tests.
 *
 * Covers: docs/specs/control-tower-team-readiness.md
 */
import { describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import {
  OPERATIONAL_READINESS_CHECKS,
  OPERATOR_READINESS_MODES,
} from "@/lib/operator-readiness";

const root = join(__dirname, "..", "..");
const repoRoot = join(root, "..", "..");

describe("operator readiness data", () => {
  it("distinguishes solo, second-device, and teammate paths", () => {
    expect(OPERATOR_READINESS_MODES.map((mode) => mode.id)).toEqual([
      "solo",
      "second-device",
      "teammate",
    ]);
  });

  it("keeps every readiness path read-only and documented", () => {
    for (const mode of OPERATOR_READINESS_MODES) {
      expect(mode.primaryCommand).toMatch(/--dry-run|doctor|status/);
      expect(mode.docs.length).toBeGreaterThan(0);
    }
  });

  it("surfaces service, post-merge, and model/tool readiness checks", () => {
    expect(OPERATIONAL_READINESS_CHECKS.map((check) => check.id)).toEqual([
      "service-health",
      "post-merge",
      "model-tools",
    ]);
  });

  it("links only to docs and commands available on main", () => {
    const commands = [
      ...OPERATOR_READINESS_MODES.map((mode) => mode.primaryCommand),
      ...OPERATIONAL_READINESS_CHECKS.map((check) => check.command),
    ];

    expect(commands).toContain("walter-os onboard device --dry-run");
    expect(commands).toContain("walter-os onboard teammate --dry-run");
    expect(commands).toContain("walter-os post-merge-check --commit <sha>");
    expect(commands).not.toContain("walter-os release doctor");
  });

  it("references documentation files that exist in the repository", () => {
    const docs = [
      ...OPERATOR_READINESS_MODES.flatMap((mode) => mode.docs),
      ...OPERATIONAL_READINESS_CHECKS.flatMap((check) => check.docs),
    ];

    for (const doc of docs) {
      expect(existsSync(join(repoRoot, doc.path)), doc.path).toBe(true);
    }
  });
});

describe("operator readiness dashboard wiring", () => {
  it("renders the panel on the overview dashboard", () => {
    const page = readFileSync(join(root, "app/page.tsx"), "utf8");
    expect(page).toContain("OperatorReadiness");
  });
});
