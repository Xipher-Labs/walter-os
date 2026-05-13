#!/usr/bin/env bash
# generate-mcp-configs.sh — emit MCP configs for Claude Code + Codex from
# the canonical mcp/servers.json. Filters by context AND load profile.
#
# Usage:
#   generate-mcp-configs.sh <target> [context] [load]
#
# target:  claude | codex
# context: "all" (default — include universal + emit a hint to install per-context separately),
#          "work", "projects-personal", "personal"
# load:    "default" (auto-load profile, EXCLUDES manual),
#          "manual"  (high-risk profile only — destructive/money MCPs),
#          "all"     (everything regardless of load tag)
#
# Load profile rationale:
# - DEFAULT profile auto-loads in all sessions (~/.claude/settings.json).
#   Read-mostly, low-risk MCPs only (23 of 29).
# - MANUAL profile is opt-in (~/.claude/settings.high-risk.json).
#   For destructive / money-spending MCPs (hetzner, cloudflare, vercel,
#   stripe, railway, bitwarden). User swaps configs when actively
#   provisioning / paying / accessing secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SERVERS_JSON="${REPO_ROOT}/mcp/servers.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "generate-mcp-configs: jq required" >&2
  exit 2
fi

if [[ ! -f "$SERVERS_JSON" ]]; then
  echo "generate-mcp-configs: $SERVERS_JSON not found" >&2
  exit 2
fi

target="${1:-claude}"
context="${2:-all}"
load="${3:-default}"

# Filter servers: include if (context matches OR has "all" context)
# AND (load profile matches the request).
filtered() {
  jq --arg ctx "$context" --arg load "$load" '
    .servers
    | to_entries
    | map(select(
        (
          .value.contexts as $c
          | ($c | index("all"))
            or ($c | index($ctx))
            or ($ctx == "all" and (.value.contexts | length > 0))
        )
        and (
          $load == "all"
          or ((.value.load // "default") == $load)
        )
      ))
    | from_entries
  ' "$SERVERS_JSON"
}

emit_claude() {
  # Emit JSON suitable for ~/.claude/settings.json under .mcpServers.
  # Two shapes:
  #   - stdio (local process): {command, args, env}
  #   - http/sse (remote): {type, url, headers}
  filtered | jq '
    to_entries
    | map({
        key: .key,
        value: (
          if .value.type == "http" or .value.type == "sse" then
            {
              type: .value.type,
              url: .value.url,
              headers: (.value.headers // {})
            }
          else
            {
              command: .value.command,
              args: .value.args,
              env: (.value.env // {})
            }
          end
        )
      })
    | from_entries
  '
}

emit_codex() {
  # Emit TOML for ~/.codex/config.toml [mcp_servers.<name>].
  # Codex (as of 2026-05) supports stdio MCPs natively. Remote (http/sse)
  # MCPs are emitted as comments with instructions, since Codex doesn't
  # consume them yet — operator runs `claude mcp add` for those.
  filtered | jq -r '
    to_entries[] |
    if .value.type == "http" or .value.type == "sse" then
      "# [mcp_servers.\(.key)] — REMOTE \(.value.type | ascii_upcase) (Codex does not consume remote MCPs yet)\n" +
      "# url: \(.value.url)\n" +
      "# Add to Claude Code via: claude mcp add-json \(.key) ''{\"type\":\"\(.value.type)\",\"url\":\"\(.value.url)\"" +
      (if .value.headers then ",\"headers\":" + (.value.headers | tostring) else "" end) +
      "}''\n\n"
    else
      "[mcp_servers.\(.key)]\n" +
      "command = \"\(.value.command)\"\n" +
      "args = " + (.value.args | tostring) + "\n" +
      (if (.value.env // {} | length) > 0 then
        "[mcp_servers.\(.key).env]\n" +
        # SECURITY/CORRECTNESS: emit each env value via `tojson` so internal
        # double-quotes (e.g. JSON blobs like OPENAPI_MCP_HEADERS) are
        # properly escaped (`\"`). The previous naive `\"\(.value)\"` form
        # produced unescaped strings and broke TOML parsing of any value
        # containing a literal `"` — left codex CLI unable to load its
        # config until manually patched. JSON string escapes are a subset
        # of TOML basic-string escapes, so `tojson` output is valid TOML.
        (.value.env | to_entries | map("\(.key) = \(.value | tojson)") | join("\n")) + "\n"
      else "" end) +
      "\n"
    end
  '
}

case "$target" in
  claude) emit_claude ;;
  codex)  emit_codex ;;
  *) echo "Usage: $0 <claude|codex> [context] [load]" >&2; exit 2 ;;
esac
