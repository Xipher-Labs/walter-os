#!/usr/bin/env node
// Snapshot stdio MCP tool definitions from Claude Code settings.
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
    transport: "stdio",
    servers: {},
    errors: {},
    skipped: {},
  };

  const { entries, denied } = stdioServers(settings, approvedRegistry);
  result.errors = denied;
  const configured = settings.mcpServers || {};
  for (const [name, config] of Object.entries(configured)) {
    if (config && (config.type === "http" || config.type === "sse")) {
      result.skipped[name] = { reason: `remote ${config.type}` };
    }
  }

  for (const [name, config] of entries) {
    try {
      const snapshot = await probeServer(name, config, args.timeoutMs);
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
