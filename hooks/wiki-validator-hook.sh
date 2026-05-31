#!/usr/bin/env bash
# hooks/wiki-validator-hook.sh — PreToolUse JSON wrapper for wiki-validator.sh.
#
# Claude Code PreToolUse hooks receive JSON on stdin and must emit JSON:
#   {"decision": "allow"} or {"decision": "block", "reason": "..."}
#
# This wrapper:
#   1. Reads PreToolUse JSON from stdin
#   2. Extracts .tool_input.file_path
#   3. Only validates paths under wiki/ (others pass through immediately)
#   4. Runs scripts/wiki/wiki-validator.sh <path>
#   5. Emits JSON decision
#
# The bare wiki-validator.sh exits 0/1 with plain text errors — not a valid
# PreToolUse hook response format. This wrapper translates between the two.
#
# Refs: docs/specs/walter-council-v2.md — R7

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALTER_HOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WALTER_OS_HOME="$WALTER_HOOK_REPO_ROOT"
VALIDATOR="${SCRIPT_DIR}/../scripts/wiki/wiki-validator.sh"

if [[ -f "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" ]]; then
  # shellcheck source=/dev/null
  source "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" || true
fi

json_string() {
  local value="$1" s
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$value" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip()))"
  else
    s="$value"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s=$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
    printf '"%s"\n' "$s"
  fi
}

audit_wiki_decision() {
  local audit_tool="${1:-unknown}" audit_input="${2:-}" audit_decision="$3" audit_reason="${4:-}"
  if declare -F walter_audit_append >/dev/null 2>&1; then
    walter_audit_append "$audit_tool" "$audit_input" "$audit_decision" "wiki-validator-hook" "$audit_reason" >/dev/null 2>&1 || {
      echo '{"decision":"block","reason":"wiki-validator-hook: audit-chain append failed; refusing unaudited decision"}'
      exit 0
    }
  else
    echo '{"decision":"block","reason":"wiki-validator-hook: audit-chain writer unavailable; refusing unaudited decision"}'
    exit 0
  fi
}

emit_allow() {
  audit_wiki_decision "${tool_name:-unknown}" "${file_path:-}" allow "${1:-}"
  echo '{"decision":"allow"}'
  exit 0
}

emit_block() {
  local reason="$1"
  audit_wiki_decision "${tool_name:-unknown}" "${file_path:-}" block "$reason"
  printf '{"decision":"block","reason":%s}\n' "$(json_string "$reason")"
  exit 0
}

# Read stdin JSON (may be empty if not invoked as hook)
input="$(cat 2>/dev/null || echo '')"

# Fast-path: no input → allow
if [[ -z "$input" ]]; then
  echo '{"decision":"allow"}'
  exit 0
fi

tool_name="unknown"
file_path=""

# Extract file_path from hook JSON
if ! command -v jq >/dev/null 2>&1; then
  # No jq means we cannot determine whether the write targets ~/sync/wiki.
  # Fail closed so missing tooling cannot bypass the wiki integrity gate.
  file_path="$input"
  emit_block "wiki-validator-hook: jq missing, failing closed"
fi

tool_name="$(echo "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")"

# Only validate files under wiki/ paths; everything else passes through.
if [[ -z "$file_path" ]] || ! [[ "$file_path" =~ /wiki/|^wiki/ ]]; then
  emit_allow
fi

# Run the validator
if [[ ! -x "$VALIDATOR" ]]; then
  emit_block "wiki-validator-hook: validator not found, failing closed"
fi

validator_output="$("$VALIDATOR" "$file_path" 2>&1)"
validator_rc=$?

if [[ "$validator_rc" -eq 0 ]]; then
  emit_allow
else
  raw_reason=""
  raw_reason="$(echo "$validator_output" | head -3 | tr '\n' ' ')"
  emit_block "wiki-validator: ${raw_reason}"
fi
