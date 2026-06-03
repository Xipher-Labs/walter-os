/**
 * Copilot round-4 critical fixes — unit / static analysis tests.
 *
 * U-r2-1: history/route.ts — s.synthesis?.summary may be undefined
 *          (synthesis present but summary field missing due to partial/corrupt JSONL)
 *          Fix: optional chain s.synthesis?.summary?.toLowerCase()
 *
 * U-r2-2: mode/route.ts — exec() passes command to shell, WALTER_OS_BIN env var
 *          could contain shell metacharacters. Fix: execFile with path validation.
 *
 * U-r2-3: ha-status/route.ts — standby_healthy returns `true` for unconfigured
 *          standby instead of `null` (N/A). Fix: return null when no standby_url.
 *
 * U-r2-4: control-tower.yml — CI workflow missing `main` in push branches.
 *          Merges to main do not trigger the build. Fix: add main.
 *
 * U-r2-5: control-tower.yml — smoke tests assert the update badge, so the
 *          version env must be present during both smoke build and run.
 *
 * Refs: docs/specs/walter-council-v2.md
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const routesDir = resolve(__dirname, "../../app/api");
const workflowsDir = resolve(__dirname, "../../.github/workflows");

// ---- U-r2-1: history/route.ts — optional chain on synthesis.summary ----

describe("U-r2-1: history route synthesis fields use optional chaining", () => {
  it("s.synthesis?.summary?.toLowerCase() uses double optional chain", () => {
    const src = readFileSync(resolve(routesDir, "history/route.ts"), "utf-8");
    // Must NOT access .summary directly without optional chain after synthesis
    // Broken pattern: synthesis?.summary.toLowerCase()
    const hasBrokenPattern = /synthesis\?\.summary\.toLowerCase/.test(src);
    expect(hasBrokenPattern).toBe(false);
  });

  it("s.synthesis?.recommended_path?.toLowerCase() uses double optional chain", () => {
    const src = readFileSync(resolve(routesDir, "history/route.ts"), "utf-8");
    const hasBrokenPattern =
      /synthesis\?\.recommended_path\.toLowerCase/.test(src);
    expect(hasBrokenPattern).toBe(false);
  });
});

// ---- U-r2-2: mode/route.ts — execFile not exec (shell injection prevention) ----

describe("U-r2-2: mode route uses execFile not exec", () => {
  it("mode route imports execFile, not exec", () => {
    const src = readFileSync(resolve(routesDir, "mode/route.ts"), "utf-8");
    // Must import execFile (not exec) from child_process
    expect(src).toMatch(/import.*execFile.*from ['"]child_process['"]/);
  });

  it("mode route does not use exec() for the walter-os CLI call", () => {
    const src = readFileSync(resolve(routesDir, "mode/route.ts"), "utf-8");
    // Must not call execAsync with a template-string command
    // The broken pattern: execAsync(`${walterBin} mode consensus ${action}`)
    const hasShellExec =
      /execAsync\s*\(\s*`\$\{walterBin\}/.test(src) ||
      /= promisify\(exec\)/.test(src);
    expect(hasShellExec).toBe(false);
  });
});

// ---- U-r2-3: ha-status/route.ts — standby_healthy null not true when no standby ----

describe("U-r2-3: ha-status route returns null for unconfigured standby", () => {
  it("standby_healthy uses null not true as the N/A fallback", () => {
    const src = readFileSync(resolve(routesDir, "ha-status/route.ts"), "utf-8");
    // Broken pattern: standby_healthy: target.standby_url ? standby.healthy : true
    const hasTrueFallback =
      /standby_healthy\s*:.*\?\s*standby\.healthy\s*:\s*true/.test(src);
    expect(hasTrueFallback).toBe(false);
  });

  it("ServiceStatus type allows null for standby_healthy", () => {
    const src = readFileSync(resolve(routesDir, "ha-status/route.ts"), "utf-8");
    // The interface must allow null: standby_healthy: boolean | null
    expect(src).toMatch(/standby_healthy\s*:\s*boolean\s*\|\s*null/);
  });
});

// ---- U-r2-4: CI workflow includes main branch ----

describe("U-r2-4: control-tower CI workflow covers main branch", () => {
  it("control-tower.yml push trigger includes main branch", () => {
    // The workflow file is at repo root .github/workflows, not in apps/
    const workflowPath = resolve(
      __dirname,
      "../../../../.github/workflows/control-tower.yml"
    );
    const src = readFileSync(workflowPath, "utf-8");
    // branches list must include main
    expect(src).toMatch(/branches\s*:[\s\S]*main/);
  });
});

// ---- U-r2-5: CI smoke workflow sets version env before build and run ----

describe("U-r2-5: control-tower smoke workflow carries version env", () => {
  it("sets version/update env for both smoke build and test execution", () => {
    const workflowPath = resolve(
      __dirname,
      "../../../../.github/workflows/control-tower.yml"
    );
    const src = readFileSync(workflowPath, "utf-8");
    const requiredEnvKeys = ["WALTER_VERSION:", "WALTER_UPDATE_AVAILABLE:"];

    const smokeJobStart = src.indexOf("  smoke-tests:");
    expect(smokeJobStart).toBeGreaterThanOrEqual(0);
    const smokeJob = src.slice(smokeJobStart);
    const beforeSteps = smokeJob.slice(0, smokeJob.indexOf("    steps:"));
    const hasJobLevelEnv = requiredEnvKeys.every((key) =>
      beforeSteps.includes(key)
    );

    const buildStepStart = smokeJob.indexOf("- name: Build for smoke tests");
    const runStepStart = smokeJob.indexOf("- name: Run smoke tests");
    expect(buildStepStart).toBeGreaterThanOrEqual(0);
    expect(runStepStart).toBeGreaterThanOrEqual(0);
    const stepBlock = (start: number) => {
      const block = smokeJob.slice(start);
      const nextStep = block.indexOf("\n      - name:", 1);
      return nextStep === -1 ? block : block.slice(0, nextStep);
    };
    const buildStep = stepBlock(buildStepStart);
    const runStep = stepBlock(runStepStart);
    const hasStepLevelEnv = requiredEnvKeys.every(
      (key) => buildStep.includes(key) && runStep.includes(key)
    );

    expect(hasJobLevelEnv || hasStepLevelEnv).toBe(true);
  });
});
