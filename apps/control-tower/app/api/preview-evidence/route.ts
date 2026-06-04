import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { readPreviewEvidence } from "@/lib/preview-evidence";
import type { PreviewEvidenceResponse } from "@/lib/preview-evidence";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export function resolvePreviewRoot(
  cwd = process.cwd(),
  configuredRoot = process.env.WALTER_PREVIEW_ROOT,
  pathExists: (path: string) => boolean = existsSync
): string {
  const trimmedRoot = configuredRoot?.trim() ?? "";
  if (trimmedRoot.length > 0) {
    return resolve(cwd, trimmedRoot);
  }
  const cwdRoot = resolve(cwd, ".walter", "previews");
  if (pathExists(cwdRoot)) {
    return cwdRoot;
  }
  return resolve(cwd, "..", "..", ".walter", "previews");
}

export function redactPreviewEvidenceRoot(
  evidence: PreviewEvidenceResponse
): PreviewEvidenceResponse {
  return { ...evidence, root: "[redacted]" };
}

export async function GET(): Promise<Response> {
  const root = resolvePreviewRoot();
  const evidence = await readPreviewEvidence(root);
  return Response.json(redactPreviewEvidenceRoot(evidence));
}
