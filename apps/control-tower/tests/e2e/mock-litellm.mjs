/**
 * Minimal mock LiteLLM server for CI smoke tests.
 *
 * Listens on PORT (default 4000) and responds to POST /v1/chat/completions
 * with a valid OpenAI-compatible completion response. Used by the smoke tests
 * so the Next.js route handlers don't fail with ECONNREFUSED.
 *
 * Run: node tests/e2e/mock-litellm.mjs &
 */
import { createServer } from "node:http";

const PORT = process.env.LITELLM_MOCK_PORT ?? 4000;

function makeCompletion(content) {
  return JSON.stringify({
    id: "chatcmpl-mock",
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model: "claude-3-haiku",
    choices: [
      {
        index: 0,
        message: { role: "assistant", content },
        finish_reason: "stop",
      },
    ],
    usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 },
  });
}

const mockSynthesisContent = JSON.stringify({
  summary: "Council reached agreement on the test question.",
  convergences: ["All agents agreed on approach A"],
  disagreements: [],
  recommended_path: "Proceed with approach A.",
  next_steps: ["Step 1: Define scope", "Step 2: Execute"],
});

const server = createServer((req, res) => {
  if (req.method === "POST" && req.url === "/v1/chat/completions") {
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      let parsed = {};
      try { parsed = JSON.parse(body); } catch {}
      const isSynthesis = parsed?.metadata?.context === "council-chat-synthesis";
      const content = isSynthesis
        ? mockSynthesisContent
        : "Mock agent response. This is a test.";
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(makeCompletion(content));
    });
  } else {
    res.writeHead(404);
    res.end("Not found");
  }
});

server.listen(PORT, () => {
  process.stdout.write(`mock-litellm listening on :${PORT}\n`);
});
