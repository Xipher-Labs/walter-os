'use strict';

const express = require('express');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');

// nosemgrep: javascript.express.security.audit.express-check-csurf-middleware-usage.express-check-csurf-middleware-usage
// Bearer-token JSON API only; no browser session cookies are accepted.
const app = express(); // nosemgrep
app.use(express.json({ limit: '4mb' }));

const PORT = parseInt(process.env.PORT || '1456', 10);

// ---------------------------------------------------------------------------
// API key authentication middleware
// ---------------------------------------------------------------------------
const REQUIRED_API_KEY = process.env.CCR_APIKEY || '';
if (REQUIRED_API_KEY) {
  app.use('/v1', (req, res, next) => {
    const auth = req.header('authorization') || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    if (!token || token !== REQUIRED_API_KEY) {
      return res.status(401).json({ error: { message: 'unauthorized', type: 'authentication_error' } });
    }
    next();
  });
} else {
  console.warn('WARNING: chatgpt-codex-router running without API key auth. Set CCR_APIKEY to require auth.');
}

// Model mapping: LiteLLM sends openai/<name>, we strip prefix and map to
// actual Codex CLI slug. Codex CLI with ChatGPT account only supports the
// slugs listed here (verified 2026-05-11 against /home/walter/.codex/models_cache.json).
const DEFAULT_MODEL_MAP = {
  'gpt-5':      'gpt-5.5',
  'gpt-5-mini': 'gpt-5.4-mini',
  'o4-mini':    'gpt-5.5',  // gpt-5.3-codex rejected by ChatGPT account ("not supported when using Codex with a ChatGPT account"); gpt-5.5 is the strongest model the account accepts (2026-06-06)
};

function loadModelMap(defaultMap) {
  const raw = process.env.MODEL_MAP_JSON;
  if (!raw || raw.trim() === '') {
    return Object.freeze({ ...defaultMap });
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    console.error(`Invalid MODEL_MAP_JSON: expected a JSON object (${err.message})`);
    process.exit(78);
  }

  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    console.error('Invalid MODEL_MAP_JSON: expected a JSON object mapping request aliases to CLI model slugs');
    process.exit(78);
  }

  const normalizedMap = Object.create(null);
  for (const [alias, model] of Object.entries(parsed)) {
    const normalizedAlias = alias.trim();
    const normalizedModel = typeof model === 'string' ? model.trim() : '';
    if (normalizedAlias === '' || normalizedModel === '') {
      console.error(`Invalid MODEL_MAP_JSON: alias "${alias}" and its model slug must be non-empty strings`);
      process.exit(78);
    }
    normalizedMap[normalizedAlias] = normalizedModel;
  }

  return Object.freeze({ ...defaultMap, ...normalizedMap });
}

const MODEL_MAP = loadModelMap(DEFAULT_MODEL_MAP);

// Accepted request-body model values (after stripping openai/ prefix)
const ACCEPTED_MODELS = new Set(Object.keys(MODEL_MAP));

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/**
 * Resolves the incoming model string to the Codex CLI --model flag value.
 * Strips the optional "openai/" prefix LiteLLM prepends.
 * Throws an Error with statusCode=400 for unrecognised models.
 */
function resolveModel(requestedModel) {
  if (typeof requestedModel !== 'string') {
    const err = new Error('model field must be a string');
    err.statusCode = 400;
    throw err;
  }
  const stripped = requestedModel.replace(/^openai\//, '');
  if (!ACCEPTED_MODELS.has(stripped)) {
    const err = new Error(
      `Unsupported model: ${requestedModel}. Accepted: ${[...ACCEPTED_MODELS].join(', ')}`
    );
    err.statusCode = 400;
    throw err;
  }
  return MODEL_MAP[stripped];
}

/**
 * Flattens OpenAI messages[] into a single plaintext prompt with role labels.
 */
function flattenMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    const err = new Error('messages must be a non-empty array');
    err.statusCode = 400;
    throw err;
  }
  return messages
    .map((m) => {
      const role = (m.role || 'user').charAt(0).toUpperCase() + (m.role || 'user').slice(1);
      const content = Array.isArray(m.content)
        ? m.content.map((c) => (typeof c === 'string' ? c : c.text || '')).join('\n')
        : String(m.content || '');
      return `${role}: ${content}`;
    })
    .join('\n');
}

/**
 * Invokes `codex exec --json` as a subprocess and returns the assistant text.
 * Returns: { content: string, usage: { input_tokens, output_tokens } }
 * Throws an error with statusCode=502 on subprocess failure.
 */
function invokeCodex(codexModel, prompt) {
  return new Promise((resolve, reject) => {
    const args = [
      'exec',
      '--json',
      '--model', codexModel,
      '--skip-git-repo-check',
      '-',
    ];

    const child = spawn('codex', args, {
      env: { ...process.env },
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    // Write prompt to stdin, then close
    child.stdin.write(prompt, 'utf8');
    child.stdin.end();

    const stdoutLines = [];
    const stderrChunks = [];
    let timedOut = false;

    // 120s timeout
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
      const err = new Error('Codex CLI subprocess timed out after 120s');
      err.statusCode = 502;
      err.code = 'upstream_timeout';
      reject(err);
    }, 120_000);

    child.stdout.on('data', (chunk) => {
      stdoutLines.push(...chunk.toString('utf8').split('\n').filter(Boolean));
    });

    child.stderr.on('data', (chunk) => {
      stderrChunks.push(chunk.toString('utf8'));
    });

    child.on('close', (code) => {
      clearTimeout(timer);
      if (timedOut) return;

      const stderr = stderrChunks.join('');

      // Parse NDJSON events
      const events = [];
      for (const line of stdoutLines) {
        try {
          events.push(JSON.parse(line));
        } catch {
          // skip malformed lines
        }
      }

      // Check for explicit error events before checking exit code
      const errorEvent = events.find((e) => e.type === 'turn.failed' || e.type === 'error');
      if (errorEvent) {
        const detail = errorEvent.error?.message || errorEvent.message || 'unknown error';
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'codex_error', detail, stderr }) + '\n'
        );
        const err = new Error(`Codex CLI error: ${detail}`);
        err.statusCode = 502;
        err.code = 'codex_subprocess_error';
        err.detail = detail;
        return reject(err);
      }

      if (code !== 0) {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'codex_nonzero_exit', code, stderr }) + '\n'
        );
        const err = new Error(`Codex CLI exited with code ${code}`);
        err.statusCode = 502;
        err.code = 'codex_subprocess_error';
        err.detail = stderr;
        return reject(err);
      }

      // Accumulate agent_message texts from item.completed events
      const textParts = events
        .filter((e) => e.type === 'item.completed' && e.item?.type === 'agent_message')
        .map((e) => e.item.text || '');

      if (textParts.length === 0) {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'no_assistant_event', events: events.map(e => e.type) }) + '\n'
        );
        const err = new Error('No assistant message found in Codex CLI output');
        err.statusCode = 502;
        err.code = 'codex_subprocess_error';
        err.detail = 'no agent_message event produced';
        return reject(err);
      }

      const content = textParts.join('\n');

      // Extract usage from turn.completed
      const turnCompleted = events.find((e) => e.type === 'turn.completed');
      const usage = {
        prompt_tokens: turnCompleted?.usage?.input_tokens ?? 0,
        completion_tokens: (turnCompleted?.usage?.output_tokens ?? 0) +
                           (turnCompleted?.usage?.reasoning_output_tokens ?? 0),
        total_tokens: (turnCompleted?.usage?.input_tokens ?? 0) +
                      (turnCompleted?.usage?.output_tokens ?? 0) +
                      (turnCompleted?.usage?.reasoning_output_tokens ?? 0),
      };

      resolve({ content, usage });
    });

    child.on('error', (err) => {
      clearTimeout(timer);
      if (timedOut) return;
      process.stdout.write(
        JSON.stringify({ level: 'error', event: 'spawn_error', message: err.message }) + '\n'
      );
      err.statusCode = 502;
      err.code = 'codex_subprocess_error';
      reject(err);
    });
  });
}

// ---------------------------------------------------------------------------
// Request logger middleware
// ---------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();
  const model = req.body?.model || req.query?.model || null;
  const promptChars = JSON.stringify(req.body?.messages || '').length;

  res.on('finish', () => {
    const log = {
      ts: new Date().toISOString(),
      method: req.method,
      path: req.path,
      model,
      prompt_chars: promptChars,
      duration_ms: Date.now() - start,
      status: res.statusCode,
    };
    process.stdout.write(JSON.stringify(log) + '\n');
  });

  next();
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// GET /health — checks Codex CLI auth state (unauthenticated — used by Docker healthcheck)
app.get('/health', (req, res) => {
  const child = spawn('codex', ['login', 'status'], {
    env: { ...process.env, HOME: process.env.HOME || '/home/node' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let output = '';
  child.stdout.on('data', (d) => { output += d.toString(); });
  child.stderr.on('data', (d) => { output += d.toString(); });

  child.on('close', (code) => {
    if (code === 0) {
      res.status(200).json({ status: 'ok', codex_output: output.trim() });
    } else {
      res.status(503).json({ status: 'unauthenticated', codex_output: output.trim() });
    }
  });

  child.on('error', () => {
    res.status(503).json({ status: 'error', detail: 'codex binary not found' });
  });
});

// GET /v1/models — list supported models
app.get('/v1/models', (req, res) => {
  const models = Object.keys(MODEL_MAP).map((id) => ({
    id: `openai/${id}`,
    object: 'model',
    created: Math.floor(Date.now() / 1000),
    owned_by: 'chatgpt-codex-router',
  }));
  res.json({ object: 'list', data: models });
});

// POST /v1/chat/completions — main endpoint
app.post('/v1/chat/completions', async (req, res) => {
  const { model, messages, tools, stream } = req.body || {};

  // Reject tool use (v1 limitation)
  if (tools && Array.isArray(tools) && tools.length > 0) {
    return res.status(400).json({ error: 'tool_use_not_supported' });
  }

  // Reject streaming (v1 limitation)
  if (stream === true) {
    return res.status(400).json({ error: 'streaming_not_supported' });
  }

  // Validate and resolve model
  let codexModel;
  try {
    codexModel = resolveModel(model);
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }

  // Flatten messages
  let prompt;
  try {
    prompt = flattenMessages(messages);
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }

  // Invoke Codex CLI
  let result;
  try {
    result = await invokeCodex(codexModel, prompt);
  } catch (err) {
    return res.status(err.statusCode || 502).json({
      error: err.code || 'codex_subprocess_error',
      detail: err.detail || err.message,
    });
  }

  const response = {
    id: `codex-${randomUUID()}`,
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model: model || 'unknown',
    choices: [
      {
        index: 0,
        message: { role: 'assistant', content: result.content },
        finish_reason: 'stop',
      },
    ],
    usage: result.usage,
  };

  return res.status(200).json(response);
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, '0.0.0.0', () => {
  process.stdout.write(
    JSON.stringify({ ts: new Date().toISOString(), event: 'server_started', port: PORT }) + '\n'
  );
});
