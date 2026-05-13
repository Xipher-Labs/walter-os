#!/usr/bin/env bash
# agent-audit-log.sh — append a structured event to the agent audit log
# at ~/sync/agent-memory/audit/<YYYY-MM-DD>.log AND (if Plane configured
# + WALTER_AGENT_PLANE_ISSUE set) post the same event as a Plane comment.
#
# The audit log is the operator's grep-friendly trail of what every
# agent did on every invocation, separate from the Plane state machine.
# Lives in ~/sync/agent-memory/ so it replicates cross-device.
#
# Usage:
#   agent-audit-log.sh \
#     --agent <name> --event <kind> [--issue <id>] [--exit <code>] \
#     [--message <text>]
#
# Event kinds (per §11 of the spec):
#   start            agent claimed an issue, beginning work
#   tool             agent invoked a tool (capture command/path)
#   blocked          approval-gate blocked an op (capture reason)
#   approved         operator approved a previously-blocked op
#   needs-operator   agent escalated (capture reason)
#   retry            transient failure, retrying once
#   end              agent finished (success or terminal failure)
#   ckpt             checkpoint for long-horizon work (resume point)
#
# Spec: docs/specs/multi-agent-autonomy.md §11

set -uo pipefail

AGENT=""
EVENT=""
ISSUE=""
EXIT_CODE=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT="$2"; shift 2 ;;
    --event)   EVENT="$2"; shift 2 ;;
    --issue)   ISSUE="$2"; shift 2 ;;
    --exit)    EXIT_CODE="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$AGENT" || -z "$EVENT" ]] && { echo "--agent and --event required" >&2; exit 2; }

ISSUE="${ISSUE:-${WALTER_AGENT_PLANE_ISSUE:-}}"
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
DAY=$(date '+%Y-%m-%d')

AUDIT_DIR="${WALTER_AGENT_AUDIT_DIR:-$HOME/sync/agent-memory/audit}"
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$DAY.log"

# Redact secrets from the message before logging (defense in depth).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REDACTOR="$SCRIPT_DIR/agent-secret-redactor.sh"
if [[ -x "$REDACTOR" && -n "$MESSAGE" ]]; then
  MESSAGE=$(printf '%s' "$MESSAGE" | "$REDACTOR")
fi

# JSONL line for the local audit log
LINE=$(jq -nc \
  --arg ts "$TS" \
  --arg agent "$AGENT" \
  --arg event "$EVENT" \
  --arg issue "$ISSUE" \
  --arg exit "$EXIT_CODE" \
  --arg msg "$MESSAGE" \
  '{ts:$ts, agent:$agent, event:$event, issue:$issue, exit:$exit, msg:$msg}' 2>/dev/null \
  || printf '{"ts":"%s","agent":"%s","event":"%s","issue":"%s","exit":"%s","msg":"%s"}\n' \
       "$TS" "$AGENT" "$EVENT" "$ISSUE" "$EXIT_CODE" "${MESSAGE//\"/\\\"}")

printf '%s\n' "$LINE" >> "$LOGFILE"

# Best-effort Plane comment (don't fail audit if Plane unreachable)
if [[ -n "$ISSUE" \
   && -n "${PLANE_API_TOKEN:-}" \
   && -n "${PLANE_API_URL:-}" \
   && -n "${PLANE_WORKSPACE:-}" \
   && -n "${PLANE_PROJECT:-}" ]] && command -v curl >/dev/null 2>&1; then

  # shellcheck disable=SC2016 # printf format-string, single quotes intentional
  COMMENT_BODY=$(printf '**[%s]** event=`%s`%s%s\n\n%s' \
    "$AGENT" "$EVENT" \
    "${EXIT_CODE:+ exit=\`$EXIT_CODE\`}" \
    " ts=\`$TS\`" \
    "$MESSAGE")

  PAYLOAD=$(jq -nc --arg c "$COMMENT_BODY" \
    '{comment_html: $c, comment_stripped: $c}' 2>/dev/null) || PAYLOAD="{\"comment_html\":\"posted by $AGENT\"}"

  curl -fsS -m 5 -X POST \
    -H "X-Api-Key: $PLANE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${PLANE_API_URL}/workspaces/${PLANE_WORKSPACE}/projects/${PLANE_PROJECT}/issues/${ISSUE}/comments/" \
    >/dev/null 2>&1 || true
fi

# stdout for callers that pipe events
printf '%s\n' "$LINE"
