import { resolve } from "node:path";
import { readPreviewEvidence } from "@/lib/preview-evidence";

export const dynamic = "force-dynamic";

export function resolvePreviewRoot(
  cwd = process.cwd(),
  configuredRoot = process.env.WALTER_PREVIEW_ROOT
): string {
  if (configuredRoot && configuredRoot.trim().length > 0) {
    return resolve(cwd, configuredRoot);
  }
  return resolve(cwd, "..", "..", ".walter", "previews");
}

export async function GET(): Promise<Response> {
  const root = resolvePreviewRoot();
  const evidence = await readPreviewEvidence(root);
  return Response.json(evidence);
}
