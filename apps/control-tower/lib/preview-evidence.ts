import { lstat, readFile, readdir } from "node:fs/promises";
import { join, posix } from "node:path";

export type PreviewEvidenceStatus =
  | "complete"
  | "planned"
  | "captured"
  | "invalid";

export interface PreviewEvidenceItem {
  pr: number;
  status: PreviewEvidenceStatus;
  statusLabel: string;
  bundleDir: string;
  url: string | null;
  provider: string | null;
  app: string | null;
  branch: string | null;
  generatedAt: string | null;
  screenshots: number;
  hasPlan: boolean;
  hasReport: boolean;
  safetyOk: boolean;
  findings: string[];
}

export interface PreviewEvidenceResponse {
  root: string;
  source: "filesystem" | "missing";
  previews: PreviewEvidenceItem[];
}

type JsonObject = Record<string, unknown>;

const PREVIEW_DIR_RE = /^preview-pr-([1-9][0-9]*)$/;
const MAX_PREVIEW_EVIDENCE_ITEMS = 50;
const SHA256_RE = /^[A-Fa-f0-9]{64}$/;
const REQUIRED_PLAN_ACTIONS = [
  "deploy_ephemeral_preview",
  "apply_seed_fixture",
  "capture_screenshots",
  "write_preview_bundle",
];

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function isHttpUrl(value: unknown): value is string {
  return typeof value === "string" && /^https?:\/\//.test(value);
}

function isSha256(value: unknown): value is string {
  return typeof value === "string" && SHA256_RE.test(value);
}

function normalizeArtifactPath(
  value: unknown,
  expectedDir: "screenshots" | "seed",
  finding: string,
  findings: string[]
): string | null {
  const path = stringValue(value);
  if (path === null) return null;
  if (path.startsWith("/") || path.includes("\\")) {
    findings.push(finding);
    return null;
  }

  const normalized = posix.normalize(path);
  if (
    normalized === "." ||
    normalized === ".." ||
    normalized.startsWith("../") ||
    !normalized.startsWith(`${expectedDir}/`) ||
    normalized === `${expectedDir}/`
  ) {
    findings.push(finding);
    return null;
  }

  return normalized;
}

function hasSafetyInvariants(safety: unknown): boolean {
  if (!isObject(safety)) return false;
  return (
    safety.production_secrets === "rejected" &&
    safety.credentials === "not minted" &&
    safety.deploy === "not performed" &&
    safety.hard_limit_floor === "preserved"
  );
}

async function readJson(
  path: string,
  label: string,
  findings: string[]
): Promise<{ exists: boolean; payload: unknown | null }> {
  let content: string;
  try {
    content = await readFile(path, "utf8");
  } catch (error) {
    if (
      isObject(error) &&
      "code" in error &&
      (error as { code?: unknown }).code === "ENOENT"
    ) {
      return { exists: false, payload: null };
    }
    findings.push(`${label} cannot be read`);
    return { exists: true, payload: null };
  }

  try {
    return { exists: true, payload: JSON.parse(content) as unknown };
  } catch {
    findings.push(`${label} is not valid JSON`);
    return { exists: true, payload: null };
  }
}

async function listScreenshotBasenames(
  path: string,
  findings: string[]
): Promise<Set<string>> {
  try {
    const entries = await readdir(path, { withFileTypes: true });
    return new Set(
      entries.flatMap((entry) =>
        entry.isFile() && /\.(png|jpe?g|webp)$/i.test(entry.name)
          ? [entry.name]
          : []
      )
    );
  } catch (error) {
    if (
      isObject(error) &&
      "code" in error &&
      (error as { code?: unknown }).code === "ENOENT"
    ) {
      return new Set();
    }
    findings.push("screenshots directory cannot be read");
    return new Set();
  }
}

function validatePreviewReport(
  payload: unknown,
  expectedPr: number,
  findings: string[]
): {
  valid: boolean;
  safetyOk: boolean;
  url: string | null;
  generatedAt: string | null;
  screenshots: number;
  seedPath: string | null;
  screenshotPaths: string[];
} {
  if (!isObject(payload)) {
    findings.push("preview report is not an object");
    return {
      valid: false,
      safetyOk: false,
      url: null,
      generatedAt: null,
      screenshots: 0,
      seedPath: null,
      screenshotPaths: [],
    };
  }

  let valid = true;
  const seed = payload.seed_manifest;
  const screenshots = Array.isArray(payload.screenshots)
    ? payload.screenshots
    : [];
  const safetyOk = hasSafetyInvariants(payload.safety);

  if (payload.schema_version !== 1) {
    findings.push("preview report schema version is unsupported");
    valid = false;
  }
  if (payload.pr !== expectedPr) {
    findings.push("preview report PR does not match directory");
    valid = false;
  }
  if (!isHttpUrl(payload.url)) {
    findings.push("preview report URL is missing or invalid");
    valid = false;
  }
  if (!isObject(seed) || !isSha256(seed.sha256)) {
    findings.push("preview report seed hash is missing or invalid");
    valid = false;
  }
  if (!isObject(seed) || !stringValue(seed.path)) {
    findings.push("preview report seed path is missing or invalid");
    valid = false;
  }
  if (screenshots.length === 0) {
    findings.push("preview report screenshots are missing");
    valid = false;
  }
  if (
    screenshots.some(
      (screenshot) =>
        !isObject(screenshot) || !isSha256(screenshot.sha256)
    )
  ) {
    findings.push("preview report screenshot hash is missing or invalid");
    valid = false;
  }
  if (
    screenshots.some(
      (screenshot) =>
        !isObject(screenshot) || !stringValue(screenshot.path)
    )
  ) {
    findings.push("preview report screenshot path is missing or invalid");
    valid = false;
  }
  if (!safetyOk) {
    findings.push("preview report safety invariants failed");
    valid = false;
  }

  const seedPath = isObject(seed)
    ? normalizeArtifactPath(
        seed.path,
        "seed",
        "preview report seed path escapes seed directory",
        findings
      )
    : null;
  if (isObject(seed) && stringValue(seed.path) !== null && seedPath === null) {
    valid = false;
  }

  const screenshotPaths = screenshots.flatMap((screenshot) => {
    if (!isObject(screenshot)) return [];
    const path = normalizeArtifactPath(
      screenshot.path,
      "screenshots",
      "preview report screenshot path escapes screenshots directory",
      findings
    );
    if (stringValue(screenshot.path) !== null && path === null) {
      valid = false;
    }
    return path === null ? [] : [path];
  });

  return {
    valid,
    safetyOk,
    url: isHttpUrl(payload.url) ? payload.url : null,
    generatedAt: stringValue(payload.generated_at),
    screenshots: screenshots.length,
    seedPath,
    screenshotPaths,
  };
}

async function isExistingFile(path: string): Promise<boolean> {
  try {
    return (await lstat(path)).isFile();
  } catch {
    return false;
  }
}

function validatePreviewPlan(
  payload: unknown,
  expectedPr: number,
  findings: string[]
): {
  valid: boolean;
  safetyOk: boolean;
  provider: string | null;
  app: string | null;
  branch: string | null;
  generatedAt: string | null;
} {
  if (!isObject(payload)) {
    findings.push("preview plan is not an object");
    return {
      valid: false,
      safetyOk: false,
      provider: null,
      app: null,
      branch: null,
      generatedAt: null,
    };
  }

  let valid = true;
  const seed = payload.seed_manifest;
  const actions = Array.isArray(payload.actions) ? payload.actions : [];
  const safety = payload.safety;
  const safetyOk =
    hasSafetyInvariants(safety) &&
    isObject(safety) &&
    safety.dry_run === true &&
    safety.preview_deploy === true;

  if (payload.schema_version !== 1 || payload.kind !== "preview-plan") {
    findings.push("preview plan schema is unsupported");
    valid = false;
  }
  if (payload.pr !== expectedPr) {
    findings.push("preview plan PR does not match directory");
    valid = false;
  }
  if (!stringValue(payload.provider)) {
    findings.push("preview plan provider is missing");
    valid = false;
  }
  if (!stringValue(payload.app)) {
    findings.push("preview plan app is missing");
    valid = false;
  }
  if (!stringValue(payload.branch)) {
    findings.push("preview plan branch is missing");
    valid = false;
  }
  if (!isObject(seed) || !isSha256(seed.sha256)) {
    findings.push("preview plan seed hash is missing or invalid");
    valid = false;
  }
  if (!isObject(seed) || !stringValue(seed.path)) {
    findings.push("preview plan seed path is missing or invalid");
    valid = false;
  }
  for (const action of REQUIRED_PLAN_ACTIONS) {
    if (!actions.includes(action)) {
      findings.push(`preview plan action missing: ${action}`);
      valid = false;
    }
  }
  if (!safetyOk) {
    findings.push("preview plan safety invariants failed");
    valid = false;
  }

  return {
    valid,
    safetyOk,
    provider: stringValue(payload.provider),
    app: stringValue(payload.app),
    branch: stringValue(payload.branch),
    generatedAt: stringValue(payload.generated_at),
  };
}

async function readPreviewItem(
  root: string,
  dirName: string,
  pr: number
): Promise<PreviewEvidenceItem> {
  const bundlePath = join(root, dirName);
  const findings: string[] = [];
  const screenshotsOnDisk = await listScreenshotBasenames(
    join(bundlePath, "screenshots"),
    findings
  );

  const report = await readJson(
    join(bundlePath, "preview-report.json"),
    "preview report",
    findings
  );
  const plan = await readJson(
    join(bundlePath, "preview-plan.json"),
    "preview plan",
    findings
  );

  let reportValid = false;
  let planValid = false;
  let reportSafetyOk = false;
  let planSafetyOk = false;
  let url: string | null = null;
  let provider: string | null = null;
  let app: string | null = null;
  let branch: string | null = null;
  let generatedAt: string | null = null;
  let screenshots = screenshotsOnDisk.size;

  if (report.exists && report.payload !== null) {
    const result = validatePreviewReport(report.payload, pr, findings);
    reportValid = result.valid;
    reportSafetyOk = result.safetyOk;
    url = result.url;
    generatedAt = result.generatedAt;
    if (result.seedPath !== null && !(await isExistingFile(join(bundlePath, result.seedPath)))) {
      findings.push("preview report seed file missing on disk");
      reportValid = false;
    }
    let missingScreenshots = false;
    for (const screenshot of result.screenshotPaths) {
      if (!(await isExistingFile(join(bundlePath, screenshot)))) {
        missingScreenshots = true;
      }
    }
    if (missingScreenshots || result.screenshots > screenshotsOnDisk.size) {
      findings.push("preview report screenshot files missing on disk");
      reportValid = false;
    }
  }

  if (plan.exists && plan.payload !== null) {
    const result = validatePreviewPlan(plan.payload, pr, findings);
    planValid = result.valid;
    planSafetyOk = result.safetyOk;
    provider = result.provider;
    app = result.app;
    branch = result.branch;
    generatedAt = generatedAt ?? result.generatedAt;
  }

  if (!report.exists && (plan.exists || screenshots > 0)) {
    findings.push("preview report missing");
  }
  if (!plan.exists && !report.exists && screenshots > 0) {
    findings.push("dry-run plan missing");
  }
  if (!plan.exists && !report.exists && screenshots === 0) {
    findings.push("preview evidence missing");
  }

  const hasInvalidEvidence =
    (report.exists && !reportValid) || (plan.exists && !planValid);
  const status: PreviewEvidenceStatus = hasInvalidEvidence
    ? "invalid"
    : reportValid
      ? "complete"
      : planValid
        ? "planned"
        : screenshots > 0
          ? "captured"
          : "invalid";

  const statusLabel =
    status === "complete"
      ? "Bundle ready"
      : status === "planned"
        ? "Dry-run plan"
        : status === "captured"
          ? "Screenshot only"
          : "Needs attention";

  const safetyOk =
    status === "complete"
      ? reportSafetyOk && (!plan.exists || planSafetyOk)
      : status === "planned"
        ? planSafetyOk
        : false;

  return {
    pr,
    status,
    statusLabel,
    bundleDir: dirName,
    url,
    provider,
    app,
    branch,
    generatedAt,
    screenshots,
    hasPlan: plan.exists,
    hasReport: report.exists,
    safetyOk,
    findings,
  };
}

export async function readPreviewEvidence(
  root: string
): Promise<PreviewEvidenceResponse> {
  try {
    const rootStat = await lstat(root);
    if (!rootStat.isDirectory()) {
      return { root, source: "missing", previews: [] };
    }
  } catch (error) {
    if (
      isObject(error) &&
      "code" in error &&
      (error as { code?: unknown }).code === "ENOENT"
    ) {
      return { root, source: "missing", previews: [] };
    }
    return { root, source: "missing", previews: [] };
  }

  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {
    return { root, source: "missing", previews: [] };
  }
  const previewDirs = entries
    .flatMap((entry) => {
      const match = PREVIEW_DIR_RE.exec(entry.name);
      if (!entry.isDirectory() || match === null) return [];
      return [{ dirName: entry.name, pr: Number(match[1]) }];
    })
    .sort((a, b) => b.pr - a.pr)
    .slice(0, MAX_PREVIEW_EVIDENCE_ITEMS);

  const previews = await Promise.all(
    previewDirs.map((entry) => readPreviewItem(root, entry.dirName, entry.pr))
  );
  return { root, source: "filesystem", previews };
}
