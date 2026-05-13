/**
 * Spin-spec API — creates a Plane issue from Council synthesis.
 * Called when operator clicks "Spin as spec + plan" after a Council session.
 *
 * POST /api/ideation/spin-spec
 * Body: { session_id, synthesis, original_message }
 *
 * Creates a Plane issue in lane:code with the synthesis as description.
 * The architect agent picks this up on the next polling cycle.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-8)
 * Task: T-46
 */
import type { SynthesisResult } from "@/server/council/history";
import { buildIssueDescription } from "@/lib/spin-spec-html";
export const dynamic = "force-dynamic";
export const runtime = "nodejs";

interface SpinSpecBody {
  session_id: string;
  synthesis: SynthesisResult;
  original_message: string;
}

export async function POST(request: Request): Promise<Response> {
  let body: SpinSpecBody;
  try {
    body = (await request.json()) as SpinSpecBody;
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { session_id, synthesis, original_message } = body;
  if (!synthesis?.summary || !original_message) {
    return Response.json(
      { error: "synthesis and original_message are required" },
      { status: 400 }
    );
  }

  const planeUrl = process.env.PLANE_API_URL ?? "http://plane:8080";
  const planeToken = process.env.PLANE_API_TOKEN;
  const workspaceSlug = process.env.PLANE_WORKSPACE_SLUG ?? "walter-os";
  const projectId = process.env.PLANE_PROJECT_ID;

  if (!planeToken || !projectId) {
    return Response.json(
      { error: "Plane not configured (PLANE_API_TOKEN or PLANE_PROJECT_ID missing)" },
      { status: 503 }
    );
  }

  // Build the issue description from the synthesis.
  // buildIssueDescription HTML-escapes all user-controlled and LLM-sourced
  // strings before interpolation, preventing stored XSS in Plane.
  const description_html = buildIssueDescription(
    original_message,
    synthesis,
    session_id
  );

  const title = `Spec request: ${original_message.slice(0, 60)}${
    original_message.length > 60 ? "..." : ""
  }`;

  try {
    const res = await fetch(
      `${planeUrl}/api/v1/workspaces/${workspaceSlug}/projects/${projectId}/issues/`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-API-Key": planeToken,
        },
        body: JSON.stringify({
          name: title,
          description_html,
          label_ids: [], // architect can tag appropriately
          metadata: {
            source: "council-chat",
            session_id,
          },
        }),
        signal: AbortSignal.timeout(10000),
      }
    );

    if (!res.ok) {
      const errText = await res.text();
      return Response.json(
        { error: `Plane API error: ${res.status}`, detail: errText.slice(0, 200) },
        { status: 502 }
      );
    }

    const issue = (await res.json()) as { id: string; sequence_id: number };
    const issueUrl = `${planeUrl}/${workspaceSlug}/projects/${projectId}/issues/${issue.id}`;

    return Response.json({ issue_id: issue.id, issue_url: issueUrl });
  } catch (err) {
    return Response.json(
      { error: "Failed to create Plane issue", detail: String(err) },
      { status: 500 }
    );
  }
}
