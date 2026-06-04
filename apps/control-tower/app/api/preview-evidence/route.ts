import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { readPreviewEvidence } from "@/lib/preview-evidence";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export function resolvePreviewRoot(
  cwd = process.cwd(),
  configuredRoot = process.env.WALTER_PREVIEW_ROOT,
  pathExists: (path: string) => boolean = existsSync
): string {
  if (configuredRoot && configuredRoot.trim().length > 0) {
    return resolve(cwd, configuredRoot);
  }
  const cwdRoot = resolve(cwd, ".walter", "previews");
  if (pathExists(cwdRoot)) {
    return cwdRoot;
  }
  return resolve(cwd, "..", "..", ".walter", "previews");
}

export async function GET(): Promise<Response> {
  const root = resolvePreviewRoot();
  const evidence = await readPreviewEvidence(root);
  return Response.json(evidence);
}
