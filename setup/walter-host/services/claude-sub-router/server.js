'use strict';

// claude-sub-router — Wraps `claude -p --output-format=json` (Claude Code CLI)
// as an OpenAI-compatible HTTP endpoint backed by the operator's Claude Max
// subscription. Mirrors the chatgpt-codex-router pattern.
//
// Auth: OAuth tokens live in /home/walter/.claude/.credentials.json
// (bind-mounted from host). The Claude Code CLI refreshes them automatically.

const express = require('express');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');

// nosemgrep: javascript.express.security.audit.express-check-csurf-middleware-usage.express-check-csurf-middleware-usage
// Bearer-token JSON API only; no browser session cookies are accepted.
const app = express(); // nosemgrep
app.use(express.json({ limit: '4mb' }));

const PORT = parseInt(process.env.PORT || '1457', 10);

// ---------------------------------------------------------------------------
// API key authentication middleware
// ---------------------------------------------------------------------------
const REQUIRED_API_KEY = process.env.CSR_APIKEY || '';
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
  console.warn('WARNING: claude-sub-router running without API key auth. Set CSR_APIKEY to require auth.');
}

// Model mapping: incoming OpenAI-style names → Claude CLI --model values.
// LiteLLM sends `openai/<name>`; we strip the prefix before matching.
// Aliases (sonnet/opus/haiku) are stable across point releases.
const DEFAULT_MODEL_MAP = {
  sonnet: 'sonnet',
  opus: 'opus',
  haiku: 'haiku',
  // Full-name passthrough — operator can opt into a pinned snapshot.
  'claude-sonnet-4-6': 'claude-sonnet-4-6',
  'claude-opus-4-5':   'claude-opus-4-5',
  'claude-haiku-4-5':  'claude-haiku-4-5',
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

const ACCEPTED_MODELS = new Set(Object.keys(MODEL_MAP));

function startupModelProbeEnabled() {
  const value = (process.env.ROUTER_STARTUP_MODEL_PROBE || '').trim().toLowerCase();
  return value === '1' || value === 'true' || value === 'yes' || value === 'on';
}

function startupModelProbeTimeoutMs() {
  const parsed = Number.parseInt(process.env.ROUTER_STARTUP_MODEL_PROBE_TIMEOUT_MS || '240000', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 240000;
}

const STARTUP_MODEL_PROBE_ENABLED = startupModelProbeEnabled();
const STARTUP_MODEL_PROBE_TIMEOUT_MS = startupModelProbeTimeoutMs();
const STARTUP_MODEL_PROBE_PROMPT = process.env.ROUTER_STARTUP_MODEL_PROBE_PROMPT ||
  'Reply with exactly: ok';
const STARTUP_MODEL_PROBE_HEADER = 'x-router-startup-model-probe';
const STARTUP_MODEL_PROBE_HEADER_VALUE = randomUUID();
let startupModelProbeStatus = STARTUP_MODEL_PROBE_ENABLED ? 'pending' : 'skipped';
let startupModelProbeFailure = null;

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

function flattenMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    const err = new Error('messages must be a non-empty array');
    err.statusCode = 400;
    throw err;
  }
  // Claude Code CLI accepts a single prompt string. We preserve role labels
  // to give the model context about who said what.
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
 * Spawns `claude -p --output-format=json --model <X>` with the prompt piped
 * on stdin. Returns { content, usage } shaped for OpenAI compatibility.
 * Hard timeout 180s (Claude can be slow for opus / long context).
 */
function invokeClaude(claudeModel, prompt) {
  return new Promise((resolve, reject) => {
    const args = [
      '-p',
      '--output-format', 'json',
      '--model', claudeModel,
      // Skip per-machine context to keep cache hot across requests.
      '--exclude-dynamic-system-prompt-sections',
      // No session persistence — bridge is stateless per request.
      '--no-session-persistence',
      // No setting sources from disk — keep behaviour identical across users.
      '--setting-sources', '',
    ];

    const child = spawn('claude', args, {
      env: { ...process.env },
      stdio: ['pipe', 'pipe', 'pipe'],
      // Run in a writable cwd that isn't a git repo to avoid trust prompts.
      cwd: '/tmp',
    });

    child.stdin.write(prompt, 'utf8');
    child.stdin.end();

    const stdoutChunks = [];
    const stderrChunks = [];
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
      const err = new Error('Claude CLI subprocess timed out after 180s');
      err.statusCode = 502;
      err.code = 'upstream_timeout';
      reject(err);
    }, 180_000);

    child.stdout.on('data', (chunk) => stdoutChunks.push(chunk.toString('utf8')));
    child.stderr.on('data', (chunk) => stderrChunks.push(chunk.toString('utf8')));

    child.on('close', (code) => {
      clearTimeout(timer);
      if (timedOut) return;

      const stderr = stderrChunks.join('');
      const stdout = stdoutChunks.join('').trim();

      if (code !== 0) {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'claude_nonzero_exit', code, stderr }) + '\n'
        );
        const err = new Error(`Claude CLI exited with code ${code}`);
        err.statusCode = 502;
        err.code = 'claude_subprocess_error';
        err.detail = stderr || stdout;
        return reject(err);
      }

      // Output shape from `claude -p --output-format=json`:
      //   { type: "result", subtype: "success", is_error, result, usage: {...}, ... }
      let payload;
      try {
        payload = JSON.parse(stdout);
      } catch (err) {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'claude_bad_json', stdout: stdout.slice(0, 500) }) + '\n'
        );
        const e = new Error('Claude CLI output is not valid JSON');
        e.statusCode = 502;
        e.code = 'claude_subprocess_error';
        e.detail = stdout.slice(0, 500);
        return reject(e);
      }

      if (payload.is_error === true || payload.subtype !== 'success') {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'claude_error_result', payload }) + '\n'
        );
        const e = new Error(`Claude CLI error: ${payload.result || 'unknown'}`);
        e.statusCode = 502;
        e.code = 'claude_subprocess_error';
        e.detail = payload.result || JSON.stringify(payload).slice(0, 500);
        return reject(e);
      }

      const content = String(payload.result || '');

      const u = payload.usage || {};
      const input = (u.input_tokens || 0)
        + (u.cache_read_input_tokens || 0)
        + (u.cache_creation_input_tokens || 0);
      const output = u.output_tokens || 0;

      resolve({
        content,
        usage: {
          prompt_tokens: input,
          completion_tokens: output,
          total_tokens: input + output,
        },
        cost_usd: payload.total_cost_usd ?? null,
        stop_reason: payload.stop_reason || null,
      });
    });

    child.on('error', (err) => {
      clearTimeout(timer);
      if (timedOut) return;
      process.stdout.write(
        JSON.stringify({ level: 'error', event: 'spawn_error', message: err.message }) + '\n'
      );
      err.statusCode = 502;
      err.code = 'claude_subprocess_error';
      reject(err);
    });
  });
}

async function postStartupModelProbe(alias) {
  const headers = { 'Content-Type': 'application/json' };
  headers[STARTUP_MODEL_PROBE_HEADER] = STARTUP_MODEL_PROBE_HEADER_VALUE;
  if (REQUIRED_API_KEY) {
    headers.Authorization = `Bearer ${REQUIRED_API_KEY}`;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), STARTUP_MODEL_PROBE_TIMEOUT_MS);

  try {
    const response = await fetch(`http://127.0.0.1:${PORT}/v1/chat/completions`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: `openai/${alias}`,
        messages: [{ role: 'user', content: STARTUP_MODEL_PROBE_PROMPT }],
        stream: false,
      }),
      signal: controller.signal,
    });
    const body = await response.text();
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${body.slice(0, 500)}`);
    }
    if (body.trim() === '') {
      throw new Error('empty completion response');
    }
    return body;
  } catch (err) {
    if (err.name === 'AbortError') {
      throw new Error(`probe timed out after ${STARTUP_MODEL_PROBE_TIMEOUT_MS}ms`);
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

function startupModelProbeReadinessError() {
  if (startupModelProbeStatus === 'pending') {
    return { code: 'startup_model_probe_pending', detail: 'startup model probe pending' };
  }
  if (startupModelProbeStatus === 'failed') {
    return { code: 'startup_model_probe_failed', detail: startupModelProbeFailure };
  }
  return null;
}

function isStartupModelProbeRequest(req) {
  return req.header(STARTUP_MODEL_PROBE_HEADER) === STARTUP_MODEL_PROBE_HEADER_VALUE;
}

async function runStartupModelProbes() {
  if (!STARTUP_MODEL_PROBE_ENABLED) {
    startupModelProbeStatus = 'skipped';
    process.stdout.write(
      JSON.stringify({ ts: new Date().toISOString(), event: 'startup_model_probe_skipped' }) + '\n'
    );
    return;
  }

  for (const [alias, targetModel] of Object.entries(MODEL_MAP)) {
    process.stdout.write(
      JSON.stringify({
        ts: new Date().toISOString(),
        event: 'startup_model_probe_started',
        alias,
        target_model: targetModel,
      }) + '\n'
    );

    try {
      await postStartupModelProbe(alias);
    } catch (err) {
      const message = `Startup model probe failed for advertised model slug "${alias}" mapped to "${targetModel}": ${err.message}`;
      startupModelProbeStatus = 'failed';
      startupModelProbeFailure = message;
      console.error(message);
      process.stdout.write(
        JSON.stringify({
          ts: new Date().toISOString(),
          level: 'error',
          event: 'startup_model_probe_failed',
          alias,
          target_model: targetModel,
          detail: err.message,
        }) + '\n'
      );
      throw new Error(message);
    }
  }

  startupModelProbeStatus = 'passed';
  process.stdout.write(
    JSON.stringify({
      ts: new Date().toISOString(),
      event: 'startup_model_probe_passed',
      models: Object.keys(MODEL_MAP),
    }) + '\n'
  );
}

// ---------------------------------------------------------------------------
// Request logger
// ---------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();
  const model = req.body?.model || req.query?.model || null;
  const promptChars = JSON.stringify(req.body?.messages || '').length;

  res.on('finish', () => {
    process.stdout.write(JSON.stringify({
      ts: new Date().toISOString(),
      method: req.method,
      path: req.path,
      model,
      prompt_chars: promptChars,
      duration_ms: Date.now() - start,
      status: res.statusCode,
    }) + '\n');
  });

  next();
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// GET /health — verifies the OAuth credentials file is readable. Avoids a
// live API call to keep this cheap. If the file is missing or empty, the
// container needs `claude /login` on the host volume.
// Unauthenticated endpoint — used by Docker healthcheck before auth is needed.
app.get('/health', (req, res) => {
  const probeError = startupModelProbeReadinessError();
  if (probeError) {
    return res.status(503).json({
      status: probeError.code === 'startup_model_probe_pending' ? 'starting' : 'failed',
      detail: probeError.detail,
    });
  }

  const fs = require('fs');
  const home = process.env.HOME || '/home/node';
  const path = `${home}/.claude/.credentials.json`;
  try {
    const stat = fs.statSync(path);
    if (stat.size < 50) {
      return res.status(503).json({ status: 'unauthenticated', detail: 'credentials file is empty' });
    }
    return res.status(200).json({ status: 'ok', credentials_bytes: stat.size });
  } catch (err) {
    return res.status(503).json({ status: 'unauthenticated', detail: err.message });
  }
});

// GET /v1/models — list supported models
app.get('/v1/models', (req, res) => {
  const models = Object.keys(MODEL_MAP).map((id) => ({
    id: `openai/${id}`,
    object: 'model',
    created: Math.floor(Date.now() / 1000),
    owned_by: 'claude-sub-router',
  }));
  res.json({ object: 'list', data: models });
});

// POST /v1/chat/completions — main endpoint
app.post('/v1/chat/completions', async (req, res) => {
  const { model, messages, tools, stream } = req.body || {};

  const probeError = startupModelProbeReadinessError();
  if (probeError && !isStartupModelProbeRequest(req)) {
    return res.status(503).json({ error: probeError.code, detail: probeError.detail });
  }

  if (tools && Array.isArray(tools) && tools.length > 0) {
    return res.status(400).json({ error: 'tool_use_not_supported' });
  }
  if (stream === true) {
    return res.status(400).json({ error: 'streaming_not_supported' });
  }

  let claudeModel;
  try {
    claudeModel = resolveModel(model);
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }

  let prompt;
  try {
    prompt = flattenMessages(messages);
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }

  let result;
  try {
    result = await invokeClaude(claudeModel, prompt);
  } catch (err) {
    return res.status(err.statusCode || 502).json({
      error: err.code || 'claude_subprocess_error',
      detail: err.detail || err.message,
    });
  }

  return res.status(200).json({
    id: `claude-${randomUUID()}`,
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model: model || 'unknown',
    choices: [
      {
        index: 0,
        message: { role: 'assistant', content: result.content },
        finish_reason: result.stop_reason === 'end_turn' ? 'stop' : (result.stop_reason || 'stop'),
      },
    ],
    usage: result.usage,
  });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
const server = app.listen(PORT, '0.0.0.0', () => {
  (async () => {
    try {
      await runStartupModelProbes();
      process.stdout.write(
        JSON.stringify({ ts: new Date().toISOString(), event: 'server_started', port: PORT }) + '\n'
      );
    } catch (err) {
      startupModelProbeStatus = 'failed';
      startupModelProbeFailure = startupModelProbeFailure || err.message;
      process.stdout.write(
        JSON.stringify({
          ts: new Date().toISOString(),
          level: 'error',
          event: 'server_started_with_failed_startup_model_probe',
          detail: startupModelProbeFailure,
        }) + '\n'
      );
    }
  })();
});
