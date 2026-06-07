import { sanitizeForPrompt } from "@/lib/sanitize";
import type { ChatSession, R1Response, R2Response } from "./history";

const SESSION_ID_RE =
  /^(chat|ideation)-([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;

const MAX_MESSAGE_CHARS = 2000;
const MAX_AGENT_CHARS = 64;
const MAX_RESPONSE_CHARS = 2000;
const MAX_RESPONSES_PER_ROUND = 8;

export interface LLMSessionResponse {
  agent: string;
  content: string;
}

export interface LLMSessionSnapshot {
  session_id: string;
  message: string;
  round1: LLMSessionResponse[];
  round2: LLMSessionResponse[];
}

export function isValidCouncilSessionId(sessionId: unknown): sessionId is string {
  return typeof sessionId === "string" && SESSION_ID_RE.test(sessionId);
}

function safeAgentId(agent: unknown): string {
  if (typeof agent !== "string") return "unknown-agent";
  const safe = sanitizeForPrompt(agent, MAX_AGENT_CHARS).trim();
  return /^[a-z0-9_-]{1,64}$/i.test(safe) ? safe : "unknown-agent";
}

function safeResponse(response: R1Response | R2Response): LLMSessionResponse {
  return {
    agent: safeAgentId(response.agent),
    content: sanitizeForPrompt(
      typeof response.content === "string" ? response.content : "",
      MAX_RESPONSE_CHARS
    ),
  };
}

function safeResponses(
  responses: (R1Response | R2Response)[] | undefined
): LLMSessionResponse[] {
  if (!Array.isArray(responses)) return [];
  return responses.slice(0, MAX_RESPONSES_PER_ROUND).map(safeResponse);
}

export function createLLMSessionSnapshot(session: ChatSession): LLMSessionSnapshot {
  return {
    session_id: session.session_id,
    message: sanitizeForPrompt(
      typeof session.message === "string" ? session.message : "",
      MAX_MESSAGE_CHARS
    ),
    round1: safeResponses(session.round1),
    round2: safeResponses(session.round2),
  };
}
