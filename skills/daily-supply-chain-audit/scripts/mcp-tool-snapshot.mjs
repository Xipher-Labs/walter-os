#!/usr/bin/env node
// Snapshot MCP tool definitions from Claude Code settings.
// Uses only Node built-ins and never invokes a shell.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { spawn } from "node:child_process";

const DEFAULT_TIMEOUT_MS = Number.parseInt(
  process.env.WALTER_MCP_TOOL_PROBE_TIMEOUT_MS || "5000",
  10,
);
const PROTOCOL_VERSION = "2025-11-25";
const SAFE_TEMPLATE_VARS = new Set(["HOME", "WALTER_OS_HOME", "WALTER_CONFIG"]);

function usage() {
  console.error(
    "Usage: mcp-tool-snapshot.mjs [--settings <path>] --approved-registry <path> [--timeout-ms <ms>]",
  );
}

function parseArgs(argv) {
  const args = {
    settings: path.join(os.homedir(), ".claude", "settings.json"),
    approvedRegistry: "",
    timeoutMs: Number.isFinite(DEFAULT_TIMEOUT_MS) ? DEFAULT_TIMEOUT_MS : 5000,
  };

  function requireValue(flag, index) {
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      usage();
      process.exit(2);
    }
    return value;
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--settings") {
      args.settings = requireValue(arg, i);
      i += 1;
    } else if (arg === "--approved-registry") {
      args.approvedRegistry = requireValue(arg, i);
      i += 1;
    } else if (arg === "--timeout-ms") {
      args.timeoutMs = Number.parseInt(requireValue(arg, i), 10);
      i += 1;
    } else if (arg === "-h" || arg === "--help") {
      usage();
      process.exit(0);
    } else {
      usage();
      process.exit(2);
    }
  }

  if (
    !args.settings ||
    !args.approvedRegistry ||
    !Number.isFinite(args.timeoutMs) ||
    args.timeoutMs <= 0
  ) {
    usage();
    process.exit(2);
  }
  return args;
}

function sortJson(value) {
  if (Array.isArray(value)) {
    return value.map(sortJson);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, sortJson(value[key])]),
    );
  }
  return value;
}

function normalizeTools(tools) {
  return tools
    .map((tool) => sortJson(tool))
    .sort((a, b) => {
      const aName = typeof a.name === "string" ? a.name : "";
      const bName = typeof b.name === "string" ? b.name : "";
      if (aName !== bName) return aName.localeCompare(bName);
      return JSON.stringify(a).localeCompare(JSON.stringify(b));
    });
}

function stringifyConfigValue(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

function expandSafeTemplateString(value) {
  return stringifyConfigValue(value).replace(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g, (match, name) => {
    if (SAFE_TEMPLATE_VARS.has(name) && Object.prototype.hasOwnProperty.call(process.env, name)) {
      return process.env[name];
    }
    return match;
  });
}

function compareEnv(envConfig) {
  const expanded = {};
  for (const [key, value] of Object.entries(envConfig || {})) {
    expanded[key] = expandSafeTemplateString(value);
  }
  return expanded;
}

function launchConfig(config) {
  return {
    command: stringifyConfigValue(config.command),
    args: Array.isArray(config.args) ? config.args.map(expandSafeTemplateString) : [],
    env: compareEnv(config.env || {}),
  };
}

function materializeEnv(envConfig) {
  const env = {};
  for (const [key, value] of Object.entries(envConfig || {})) {
    const stringValue = expandSafeTemplateString(value);
    if (
      (stringValue === `$${key}` || stringValue === `\${${key}}`) &&
      Object.prototype.hasOwnProperty.call(process.env, key)
    ) {
      env[key] = process.env[key];
    } else {
      env[key] = stringValue;
    }
  }
  return env;
}

function normalizeHeaders(headersConfig) {
  const headers = {};
  for (const [key, value] of Object.entries(headersConfig || {})) {
    headers[key] = expandSafeTemplateString(value);
  }
  return headers;
}

function materializeHeaders(headersConfig) {
  const headers = {};
  for (const [key, value] of Object.entries(headersConfig || {})) {
    headers[key] = stringifyConfigValue(value).replace(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g, (match, name) => {
      if (Object.prototype.hasOwnProperty.call(process.env, name)) {
        return process.env[name];
      }
      return match;
    });
  }
  return headers;
}

function spawnLaunchConfig(config) {
  return {
    command: stringifyConfigValue(config.command),
    args: Array.isArray(config.args) ? config.args.map(expandSafeTemplateString) : [],
    env: materializeEnv(config.env || {}),
  };
}

function sameLaunchConfig(left, right) {
  return JSON.stringify(sortJson(left)) === JSON.stringify(sortJson(right));
}

function remoteType(config) {
  const type = stringifyConfigValue(config.type || config.transport);
  return type === "http" || type === "sse" ? type : "";
}

function remoteCompareConfig(config) {
  return {
    type: remoteType(config),
    url: expandSafeTemplateString(config.url),
    headers: normalizeHeaders(config.headers || {}),
  };
}

function remoteRuntimeConfig(config) {
  return {
    type: remoteType(config),
    url: expandSafeTemplateString(config.url),
    headers: materializeHeaders(config.headers || {}),
  };
}

function stdioServers(settings, approvedRegistry) {
  const mcpServers = settings.mcpServers || {};
  const entries = [];
  const denied = {};

  for (const [name, config] of Object.entries(mcpServers)) {
    if (!config || config.disabled === true) continue;
    if (typeof config.command !== "string" || config.command.length === 0) continue;

    const runtimeLaunch = launchConfig(config);
    if (approvedRegistry) {
      const approved = approvedRegistry[name];
      if (!approved) {
        denied[name] = { message: "stdio MCP is not present in approved server registry baseline" };
        continue;
      }
      if (approved.disabled === true) {
        denied[name] = { message: "approved server registry baseline marks this stdio MCP disabled" };
        continue;
      }
      if ((approved.load || "default") !== "default") {
        denied[name] = {
          message: "approved server registry baseline marks this stdio MCP outside the default load profile",
        };
        continue;
      }
      const approvedLaunch = launchConfig(approved);
      if (!sameLaunchConfig(runtimeLaunch, approvedLaunch)) {
        denied[name] = {
          message: "runtime command, args, or env do not match approved server registry baseline",
        };
        continue;
      }
    }

    entries.push([name, spawnLaunchConfig(config)]);
  }

  return { entries, denied };
}

function remoteServers(settings, approvedRegistry) {
  const mcpServers = settings.mcpServers || {};
  const entries = [];
  const denied = {};

  for (const [name, config] of Object.entries(mcpServers)) {
    if (!config || config.disabled === true) continue;
    const type = remoteType(config);
    if (!type) continue;
    if (typeof config.url !== "string" || config.url.length === 0) {
      denied[name] = { message: `${type} MCP is missing url` };
      continue;
    }

    const runtimeLaunch = remoteCompareConfig(config);
    if (approvedRegistry) {
      const approved = approvedRegistry[name];
      if (!approved) {
        denied[name] = { message: `${type} MCP is not present in approved server registry baseline` };
        continue;
      }
      if (approved.disabled === true) {
        denied[name] = { message: `approved server registry baseline marks this ${type} MCP disabled` };
        continue;
      }
      if ((approved.load || "default") !== "default") {
        denied[name] = {
          message: `approved server registry baseline marks this ${type} MCP outside the default load profile`,
        };
        continue;
      }
      const approvedLaunch = remoteCompareConfig(approved);
      if (!sameLaunchConfig(runtimeLaunch, approvedLaunch)) {
        denied[name] = {
          message: "runtime type, url, or headers do not match approved server registry baseline",
        };
        continue;
      }
    }

    entries.push([name, remoteRuntimeConfig(config)]);
  }

  return { entries, denied };
}

function withTimeout(promise, timeoutMs, onTimeout) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      try {
        onTimeout();
      } finally {
        reject(new Error(`timeout after ${timeoutMs}ms`));
      }
    }, timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function fetchWithTimeout(url, options, timeoutMs) {
  if (typeof fetch !== "function") {
    throw new Error("global fetch API unavailable; Node.js 18+ required for HTTP/SSE MCP probing");
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, redirect: "error", signal: controller.signal });
  } catch (error) {
    if (error && error.name === "AbortError") {
      throw new Error(`timeout after ${timeoutMs}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

async function readResponseText(response, timeoutMs, label) {
  return withTimeout(response.text(), timeoutMs, () => {
    response.body?.cancel().catch(() => {});
  }).catch((error) => {
    throw new Error(`${label}: ${error.message}`);
  });
}

async function drainResponseBody(response, timeoutMs) {
  if (!response.body) return;
  try {
    await withTimeout(response.arrayBuffer(), timeoutMs, () => {
      response.body?.cancel().catch(() => {});
    });
  } catch {
    await response.body.cancel().catch(() => {});
  }
}

function parseSseText(text) {
  const events = [];
  let eventName = "message";
  let data = [];
  for (const rawLine of text.split(/\r?\n/)) {
    if (rawLine === "") {
      if (data.length > 0) {
        events.push({ event: eventName, data: data.join("\n") });
      }
      eventName = "message";
      data = [];
      continue;
    }
    if (rawLine.startsWith(":")) continue;
    if (rawLine.startsWith("event:")) {
      eventName = rawLine.slice("event:".length).trim();
    } else if (rawLine.startsWith("data:")) {
      data.push(rawLine.slice("data:".length).trimStart());
    }
  }
  if (data.length > 0) {
    events.push({ event: eventName, data: data.join("\n") });
  }
  return events;
}

function parseJsonRpcResponseBody(text, contentType) {
  if (contentType.includes("text/event-stream")) {
    for (const event of parseSseText(text)) {
      if (!event.data) continue;
      return JSON.parse(event.data);
    }
    throw new Error("empty SSE JSON-RPC response");
  }
  return JSON.parse(text);
}

function validateJsonRpcResponse(message, expectedId, method) {
  if (!message || typeof message !== "object" || Array.isArray(message)) {
    throw new Error(`${method} response is not a JSON-RPC object`);
  }
  if (String(message.id) !== String(expectedId)) {
    throw new Error(`${method} response id mismatch`);
  }
  return message;
}

async function probeHttpServer(name, config, timeoutMs) {
  let nextId = 1;
  let sessionId = "";

  async function sendRequest(method, params) {
    const id = nextId;
    nextId += 1;
    const payload = { jsonrpc: "2.0", id, method };
    if (params !== undefined) payload.params = params;
    const headers = {
      accept: "application/json, text/event-stream",
      "content-type": "application/json",
      ...config.headers,
    };
    if (sessionId) headers["mcp-session-id"] = sessionId;
    const response = await fetchWithTimeout(
      config.url,
      {
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      },
      timeoutMs,
    );
    if (!response.ok) {
      await drainResponseBody(response, timeoutMs);
      throw new Error(`${name} ${method} failed with HTTP ${response.status}`);
    }
    const responseSession = response.headers.get("mcp-session-id");
    if (responseSession) sessionId = responseSession;
    const message = validateJsonRpcResponse(
      parseJsonRpcResponseBody(
        await readResponseText(response, timeoutMs, `${name} ${method} response body`),
        response.headers.get("content-type") || "",
      ),
      id,
      method,
    );
    if (message.error) throw new Error(message.error.message || "JSON-RPC error");
    return message.result ?? {};
  }

  async function sendNotification(method) {
    const headers = {
      accept: "application/json, text/event-stream",
      "content-type": "application/json",
      ...config.headers,
    };
    if (sessionId) headers["mcp-session-id"] = sessionId;
    const response = await fetchWithTimeout(
      config.url,
      {
        method: "POST",
        headers,
        body: JSON.stringify({ jsonrpc: "2.0", method }),
      },
      timeoutMs,
    );
    if (!response.ok) {
      await drainResponseBody(response, timeoutMs);
      throw new Error(`${name} ${method} notification failed with HTTP ${response.status}`);
    }
    const responseSession = response.headers.get("mcp-session-id");
    if (responseSession) sessionId = responseSession;
    await drainResponseBody(response, timeoutMs);
  }

  await sendRequest("initialize", {
    protocolVersion: PROTOCOL_VERSION,
    capabilities: {},
    clientInfo: {
      name: "walter-os-mcp-tool-snapshot",
      version: "1.0.0",
    },
  });
  await sendNotification("notifications/initialized");

  const tools = [];
  let cursor;
  do {
    const result = await sendRequest("tools/list", cursor ? { cursor } : undefined);
    if (Array.isArray(result.tools)) tools.push(...result.tools);
    cursor = result.nextCursor;
  } while (cursor);

  return { tools: normalizeTools(tools) };
}

function createSseClient(response, name) {
  const decoder = new TextDecoder();
  const reader = response.body?.getReader();
  if (!reader) throw new Error(`${name} SSE response has no readable body`);

  let buffer = "";
  let eventName = "message";
  let data = [];
  const events = [];
  const waiters = [];

  function resolveWaiters() {
    for (let i = waiters.length - 1; i >= 0; i -= 1) {
      const waiter = waiters[i];
      const index = events.findIndex(waiter.predicate);
      if (index !== -1) {
        const [event] = events.splice(index, 1);
        waiters.splice(i, 1);
        clearTimeout(waiter.timer);
        waiter.resolve(event);
      }
    }
  }

  function dispatchEvent() {
    if (data.length === 0) return;
    events.push({ event: eventName, data: data.join("\n") });
    eventName = "message";
    data = [];
    resolveWaiters();
  }

  function consumeLine(line) {
    const cleanLine = line.endsWith("\r") ? line.slice(0, -1) : line;
    if (cleanLine === "") {
      dispatchEvent();
      return;
    }
    if (cleanLine.startsWith(":")) return;
    if (cleanLine.startsWith("event:")) {
      eventName = cleanLine.slice("event:".length).trim();
    } else if (cleanLine.startsWith("data:")) {
      data.push(cleanLine.slice("data:".length).trimStart());
    }
  }

  function consumeChunk(chunk) {
    buffer += decoder.decode(chunk, { stream: true });
    let newlineIndex;
    while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, newlineIndex);
      buffer = buffer.slice(newlineIndex + 1);
      consumeLine(line);
    }
  }

  (async () => {
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        consumeChunk(value);
      }
      buffer += decoder.decode();
      if (buffer.length > 0) consumeLine(buffer);
      dispatchEvent();
    } catch (error) {
      for (const waiter of waiters.splice(0)) {
        clearTimeout(waiter.timer);
        waiter.reject(error);
      }
    }
  })();

  function waitFor(predicate, timeoutMs, label) {
    const index = events.findIndex(predicate);
    if (index !== -1) {
      const [event] = events.splice(index, 1);
      return Promise.resolve(event);
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const waiterIndex = waiters.findIndex((waiter) => waiter.timer === timer);
        if (waiterIndex !== -1) waiters.splice(waiterIndex, 1);
        reject(new Error(`timeout after ${timeoutMs}ms waiting for ${label}`));
      }, timeoutMs);
      waiters.push({ predicate, resolve, reject, timer });
    });
  }

  return {
    waitFor,
    close: () => reader.cancel().catch(() => {}),
  };
}

async function probeSseServer(name, config, timeoutMs) {
  const response = await fetchWithTimeout(
    config.url,
    {
      method: "GET",
      headers: {
        accept: "text/event-stream",
        ...config.headers,
      },
    },
    timeoutMs,
  );
  if (!response.ok) {
    await drainResponseBody(response, timeoutMs);
    throw new Error(`${name} SSE connect failed with HTTP ${response.status}`);
  }
  const client = createSseClient(response, name);
  let nextId = 1;

  try {
    const endpointEvent = await client.waitFor(
      (event) => event.event === "endpoint",
      timeoutMs,
      "SSE endpoint",
    );
    const postUrl = new URL(endpointEvent.data, config.url).toString();

    async function postMessage(payload) {
      const postResponse = await fetchWithTimeout(
        postUrl,
        {
          method: "POST",
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            ...config.headers,
          },
          body: JSON.stringify(payload),
        },
        timeoutMs,
      );
      if (!postResponse.ok) {
        await drainResponseBody(postResponse, timeoutMs);
        throw new Error(`${name} SSE POST failed with HTTP ${postResponse.status}`);
      }
      await drainResponseBody(postResponse, timeoutMs);
    }

    async function sendRequest(method, params) {
      const id = nextId;
      nextId += 1;
      const payload = { jsonrpc: "2.0", id, method };
      if (params !== undefined) payload.params = params;
      const responsePromise = client.waitFor((event) => {
        if (event.event !== "message" || !event.data) return false;
        try {
          const message = JSON.parse(event.data);
          return String(message.id) === String(id);
        } catch {
          return false;
        }
      }, timeoutMs, `${method} response`);
      await postMessage(payload);
      const event = await responsePromise;
      const message = JSON.parse(event.data);
      if (message.error) throw new Error(message.error.message || "JSON-RPC error");
      return message.result || {};
    }

    function sendNotification(method) {
      return postMessage({ jsonrpc: "2.0", method });
    }

    await sendRequest("initialize", {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: {
        name: "walter-os-mcp-tool-snapshot",
        version: "1.0.0",
      },
    });
    await sendNotification("notifications/initialized");

    const tools = [];
    let cursor;
    do {
      const result = await sendRequest("tools/list", cursor ? { cursor } : undefined);
      if (Array.isArray(result.tools)) tools.push(...result.tools);
      cursor = result.nextCursor;
    } while (cursor);

    return { tools: normalizeTools(tools) };
  } finally {
    await client.close();
  }
}

async function probeServer(name, config, timeoutMs) {
  let child;
  const run = new Promise((resolve, reject) => {
    child = spawn(config.command, config.args, {
      env: { ...process.env, ...config.env },
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let nextId = 1;
    let stderr = "";
    const pending = new Map();
    const rl = readline.createInterface({ input: child.stdout });

    function rejectAll(error) {
      for (const { reject: rejectPending } of pending.values()) {
        rejectPending(error);
      }
      pending.clear();
    }

    child.on("error", (error) => {
      rejectAll(error);
      reject(error);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("exit", (code, signal) => {
      if (pending.size > 0) {
        rejectAll(
          new Error(
            `server exited before response (code=${code ?? "null"}, signal=${signal ?? "null"}, stderr=${stderr.trim()})`,
          ),
        );
      }
    });

    rl.on("line", (line) => {
      if (!line.trim()) return;
      let message;
      try {
        message = JSON.parse(line);
      } catch (error) {
        rejectAll(new Error(`invalid JSON-RPC message from ${name}: ${error.message}`));
        return;
      }

      if (!Object.prototype.hasOwnProperty.call(message, "id")) return;
      const pendingRequest = pending.get(String(message.id));
      if (!pendingRequest) return;
      pending.delete(String(message.id));
      if (message.error) {
        pendingRequest.reject(new Error(message.error.message || "JSON-RPC error"));
      } else {
        pendingRequest.resolve(message.result || {});
      }
    });

    function sendRequest(method, params) {
      const id = nextId;
      nextId += 1;
      const payload = { jsonrpc: "2.0", id, method };
      if (params !== undefined) payload.params = params;
      return new Promise((resolveRequest, rejectRequest) => {
        pending.set(String(id), { resolve: resolveRequest, reject: rejectRequest });
        child.stdin.write(`${JSON.stringify(payload)}\n`, (error) => {
          if (error) {
            pending.delete(String(id));
            rejectRequest(error);
          }
        });
      });
    }

    function sendNotification(method) {
      const payload = { jsonrpc: "2.0", method };
      child.stdin.write(`${JSON.stringify(payload)}\n`);
    }

    (async () => {
      await sendRequest("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {
          name: "walter-os-mcp-tool-snapshot",
          version: "1.0.0",
        },
      });
      sendNotification("notifications/initialized");

      const tools = [];
      let cursor;
      do {
        const result = await sendRequest("tools/list", cursor ? { cursor } : undefined);
        if (Array.isArray(result.tools)) {
          tools.push(...result.tools);
        }
        cursor = result.nextCursor;
      } while (cursor);

      child.stdin.end();
      child.kill();
      resolve({ tools: normalizeTools(tools) });
    })().catch(reject);
  });

  return withTimeout(run, timeoutMs, () => {
    if (child && !child.killed) child.kill("SIGTERM");
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const settings = JSON.parse(fs.readFileSync(args.settings, "utf8"));
  const approvedRegistry = JSON.parse(fs.readFileSync(args.approvedRegistry, "utf8"));
  const result = {
    version: 1,
    source: args.settings,
    transport: "mixed",
    servers: {},
    errors: {},
    skipped: {},
  };

  const stdio = stdioServers(settings, approvedRegistry);
  const remote = remoteServers(settings, approvedRegistry);
  result.errors = { ...stdio.denied, ...remote.denied };

  for (const [name, config] of stdio.entries) {
    try {
      const snapshot = await probeServer(name, config, args.timeoutMs);
      result.servers[name] = { tools: snapshot.tools };
    } catch (error) {
      result.errors[name] = { message: error.message };
    }
  }

  for (const [name, config] of remote.entries) {
    try {
      const snapshot =
        config.type === "sse"
          ? await probeSseServer(name, config, args.timeoutMs)
          : await probeHttpServer(name, config, args.timeoutMs);
      result.servers[name] = { tools: snapshot.tools };
    } catch (error) {
      result.errors[name] = { message: error.message };
    }
  }

  process.stdout.write(`${JSON.stringify(sortJson(result), null, 2)}\n`);
}

main().catch((error) => {
  console.error(`mcp-tool-snapshot: ${error.message}`);
  process.exit(2);
});
