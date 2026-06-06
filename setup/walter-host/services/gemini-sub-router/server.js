'use strict';

// gemini-sub-router — Wraps `gemini -p --output-format=json` (Google Gemini
// CLI, https://github.com/google-gemini/gemini-cli) as an OpenAI-compatible
// HTTP endpoint backed by the operator's Google AI Pro subscription.
//
// Auth: OAuth creds live in /home/walter/.gemini/oauth_creds.json
// (bind-mounted from host). The CLI refreshes tokens automatically.

const express = require('express');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');

// nosemgrep: javascript.express.security.audit.express-check-csurf-middleware-usage.express-check-csurf-middleware-usage
// Bearer-token JSON API only; no browser session cookies are accepted.
const app = express(); // nosemgrep
app.use(express.json({ limit: '4mb' }));

const PORT = parseInt(process.env.PORT || '1458', 10);

// ---------------------------------------------------------------------------
// API key authentication middleware
// ---------------------------------------------------------------------------
const REQUIRED_API_KEY = process.env.GSR_APIKEY || '';
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
  console.warn('WARNING: gemini-sub-router running without API key auth. Set GSR_APIKEY to require auth.');
}

// Model mapping: incoming OpenAI-style names → Gemini CLI --model values.
// LiteLLM sends `openai/<name>`; strip prefix before matching.
const DEFAULT_MODEL_MAP = {
  'gemini-2.5-flash':      'gemini-2.5-flash',
  'gemini-2.5-pro':        'gemini-2.5-pro',
  'gemini-2.5-flash-lite': 'gemini-2.5-flash-lite',
  // Friendly aliases
  flash:      'gemini-2.5-flash',
  pro:        'gemini-2.5-pro',
  'flash-lite': 'gemini-2.5-flash-lite',
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
 * Spawns `gemini -p --output-format=json --model <X>` with the prompt fed
 * via stdin (avoids argv length limits for long prompts).
 * Returns { content, usage }.
 */
function invokeGemini(geminiModel, prompt) {
  return new Promise((resolve, reject) => {
    // -p "" forces non-interactive mode; stdin is appended to the prompt
    // per gemini-cli's documented behaviour.
    const args = [
      '-p', '',
      '--output-format', 'json',
      '--model', geminiModel,
      '--skip-trust',
      '--approval-mode', 'plan',
    ];

    const child = spawn('gemini', args, {
      env: { ...process.env, NO_COLOR: '1', TERM: 'dumb' },
      stdio: ['pipe', 'pipe', 'pipe'],
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
      const err = new Error('Gemini CLI subprocess timed out after 180s');
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
      let stdout = stdoutChunks.join('').trim();

      if (code !== 0) {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'gemini_nonzero_exit', code, stderr }) + '\n'
        );
        const err = new Error(`Gemini CLI exited with code ${code}`);
        err.statusCode = 502;
        err.code = 'gemini_subprocess_error';
        err.detail = stderr || stdout;
        return reject(err);
      }

      // gemini-cli prints terminal warnings (true-color, ripgrep) BEFORE the
      // JSON payload on stdout when the env detects them. Strip everything
      // before the first `{`.
      const firstBrace = stdout.indexOf('{');
      if (firstBrace > 0) stdout = stdout.slice(firstBrace);

      let payload;
      try {
        payload = JSON.parse(stdout);
      } catch (err) {
        process.stdout.write(
          JSON.stringify({ level: 'error', event: 'gemini_bad_json', stdout: stdout.slice(0, 500) }) + '\n'
        );
        const e = new Error('Gemini CLI output is not valid JSON');
        e.statusCode = 502;
        e.code = 'gemini_subprocess_error';
        e.detail = stdout.slice(0, 500);
        return reject(e);
      }

      // Expected shape:
      //   { session_id, response, stats: { models: { <model>: { tokens: {...} } } } }
      const content = String(payload.response || '');
      if (!content) {
        const e = new Error('Gemini CLI returned empty response');
        e.statusCode = 502;
        e.code = 'gemini_subprocess_error';
        e.detail = JSON.stringify(payload).slice(0, 500);
        return reject(e);
      }

      // Sum tokens across all models that fired (usually one).
      const modelStats = payload.stats?.models || {};
      let input = 0;
      let output = 0;
      for (const m of Object.values(modelStats)) {
        const t = m?.tokens || {};
        input += t.input || t.prompt || 0;
        // Gemini's `candidates` counts response tokens (1+ candidates); the
        // `total` already includes thoughts. Prefer output = total - input.
        const total = t.total || 0;
        const localInput = t.input || t.prompt || 0;
        output += Math.max(0, total - localInput);
      }

      resolve({
        content,
        usage: {
          prompt_tokens: input,
          completion_tokens: output,
          total_tokens: input + output,
        },
      });
    });

    child.on('error', (err) => {
      clearTimeout(timer);
      if (timedOut) return;
      process.stdout.write(
        JSON.stringify({ level: 'error', event: 'spawn_error', message: err.message }) + '\n'
      );
      err.statusCode = 502;
      err.code = 'gemini_subprocess_error';
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

// GET /health — verifies the OAuth credentials file is readable.
// Unauthenticated endpoint — used by Docker healthcheck.
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
  const path = `${home}/.gemini/oauth_creds.json`;
  try {
    const stat = fs.statSync(path);
    if (stat.size < 50) {
      return res.status(503).json({ status: 'unauthenticated', detail: 'creds file too small' });
    }
    return res.status(200).json({ status: 'ok', credentials_bytes: stat.size });
  } catch (err) {
    return res.status(503).json({ status: 'unauthenticated', detail: err.message });
  }
});

app.get('/v1/models', (req, res) => {
  const models = Object.keys(MODEL_MAP).map((id) => ({
    id: `openai/${id}`,
    object: 'model',
    created: Math.floor(Date.now() / 1000),
    owned_by: 'gemini-sub-router',
  }));
  res.json({ object: 'list', data: models });
});

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

  let geminiModel;
  try {
    geminiModel = resolveModel(model);
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
    result = await invokeGemini(geminiModel, prompt);
  } catch (err) {
    return res.status(err.statusCode || 502).json({
      error: err.code || 'gemini_subprocess_error',
      detail: err.detail || err.message,
    });
  }

  return res.status(200).json({
    id: `gemini-${randomUUID()}`,
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
  });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, '0.0.0.0', () => {
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
