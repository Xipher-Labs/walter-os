/**
 * Council Chat — Round 1: Parallel groupthink.
 *
 * POST /api/council-chat/round1
 * Body: { message: string, session_id: string, session_type?: "chat" | "ideation" }
 *
 * Fans out to 6 parallel LLM calls, one per agent persona.
 * Each agent responds independently (≤300 tokens), without seeing others.
 * Streams NDJSON: each line is {agent, content, done, round: 1}
 *
 * Persists session with round1 results to council-chat-history.jsonl.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-7, AC-10)
 * Task: T-44a
 */
import { COUNCIL_PERSONAS } from "@/lib/council-personas";
import { persistSession } from "@/server/council/history";
import type { R1Response } from "@/server/council/history";
import { isValidCouncilSessionId } from "@/server/council/session-safety";
import { sanitizeForPrompt } from "@/lib/sanitize";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const LITELLM_BASE_URL = process.env.LITELLM_BASE_URL ?? "http://litellm:4000";
const LITELLM_API_KEY = process.env.LITELLM_API_KEY ?? "";
const R1_MAX_TOKENS = 300;
const R1_TIMEOUT_MS = 25_000;

interface R1RequestBody {
  message: string;
  session_id: string;
  session_type?: "chat" | "ideation";
}

async function callAgentR1(
  agentId: string,
  systemPrompt: string,
  userMessage: string
): Promise<R1Response> {
  const start = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), R1_TIMEOUT_MS);

  try {
    const res = await fetch(`${LITELLM_BASE_URL}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${LITELLM_API_KEY}`,
        // LiteLLM metadata for spend attribution (T-6 pattern)
        "x-litellm-tags": JSON.stringify({
          agent_id: agentId,
          context: "council-chat",
          round: 1,
        }),
      },
      body: JSON.stringify({
        model: "claude-haiku", // Cheap/fast for R1 groupthink
        max_tokens: R1_MAX_TOKENS,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        metadata: {
          agent_id: agentId,
          context: "council-chat-r1",
        },
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const errText = await res.text();
      return {
        agent: agentId,
        content: `[${agentId} error: ${res.status} ${errText.slice(0, 100)}]`,
        elapsed_ms: Date.now() - start,
      };
    }

    const data = (await res.json()) as {
      choices: { message: { content: string } }[];
      usage?: { total_tokens?: number };
    };
    const content = data.choices?.[0]?.message?.content ?? `[${agentId}: no response]`;

    return {
      agent: agentId,
      content,
      elapsed_ms: Date.now() - start,
      token_count: data.usage?.total_tokens,
    };
  } catch (err) {
    return {
      agent: agentId,
      content: `[${agentId} timeout or error: ${String(err).slice(0, 100)}]`,
      elapsed_ms: Date.now() - start,
    };
  } finally {
    clearTimeout(timeout);
  }
}

export async function POST(request: Request): Promise<Response> {
  let body: R1RequestBody;
  try {
    body = (await request.json()) as R1RequestBody;
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { message, session_id, session_type = "chat" } = body;
  if (
    typeof message !== "string" ||
    typeof session_id !== "string" ||
    !message.trim() ||
    !session_id.trim()
  ) {
    return Response.json(
      { error: "message and session_id are required" },
      { status: 400 }
    );
  }
  if (!isValidCouncilSessionId(session_id)) {
    return Response.json({ error: "invalid session_id" }, { status: 400 });
  }

  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      // Sanitize operator message before sending to any LLM.
      // Strips control chars, result markers, and special tokens.
      const safeMessage = sanitizeForPrompt(message);

      // Fan out to all 6 agents in parallel
      const promises = COUNCIL_PERSONAS.map((persona) =>
        callAgentR1(persona.id, persona.systemPrompt, safeMessage)
      );

      // Collect all results (Promise.allSettled so one failure doesn't block others)
      const settled = await Promise.allSettled(promises);
      const results: R1Response[] = settled.map((r, i) => {
        if (r.status === "fulfilled") return r.value;
        return {
          agent: COUNCIL_PERSONAS[i].id,
          content: `[${COUNCIL_PERSONAS[i].id}: failed]`,
          elapsed_ms: 0,
        };
      });

      // Stream each result as NDJSON
      for (const r1 of results) {
        const line = JSON.stringify({
          agent: r1.agent,
          content: r1.content,
          done: true,
          round: 1,
          elapsed_ms: r1.elapsed_ms,
        });
        controller.enqueue(encoder.encode(line + "\n"));
      }

      // Persist session with R1 results.
      // Defense in depth: store safeMessage (sanitized), not the raw operator
      // input, so history is clean regardless of how it is later consumed.
      // Reviewer round 2 finding: raw message stored to history.
      persistSession({
        session_id,
        session_type,
        ts: new Date().toISOString(),
        message: safeMessage,
        round1: results,
      });

      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "application/x-ndjson",
      "Cache-Control": "no-cache",
      "X-Accel-Buffering": "no",
    },
  });
}
