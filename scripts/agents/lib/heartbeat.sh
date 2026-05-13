#!/usr/bin/env bash
# scripts/agents/lib/heartbeat.sh — Heartbeat protocol for agent liveness.
# Sourced (not exec'd) by run.sh and watchdog.sh.
#
# Functions:
#   heartbeat_write <agent> <issue_id> <step> [status]
#       Append a JSONL heartbeat line to the agent's heartbeat file.
#       Optional status field: "done" | "failed" (omit for in-progress beats).
#
#   heartbeat_read_last <agent> <issue_id>
#       Print the last JSONL line from the heartbeat file, or empty string.
#
#   heartbeat_checkpoint_steps <agent> <issue_id> <step_name>
#       Append a new JSONL line that includes completed_steps (accumulated).
#
#   heartbeat_read_checkpoint <agent> <issue_id>
#       Return the completed_steps JSON array from the most recent heartbeat,
#       or "[]" if no file / no steps recorded.
#
#   heartbeat_dead_threshold
#       Return the number of seconds after which a silent agent is a zombie.
#       Default: 1800 (30 min). Override with WALTER_HEARTBEAT_DEAD_THRESHOLD.
#
# Storage layout:
#   $WALTER_HEARTBEAT_DIR/<agent>/<issue_id>.heartbeat  (JSONL, one entry/line)
#
# Spec: docs/specs/walter-council-v2.md — Improvement 5 (T-18)

# shellcheck disable=SC2034
WALTER_HEARTBEAT_LIB_VERSION=1

WALTER_HEARTBEAT_DIR="${WALTER_HEARTBEAT_DIR:-/var/lib/walter-council/heartbeats}"
WALTER_HEARTBEAT_INTERVAL="${WALTER_HEARTBEAT_INTERVAL:-60}"
WALTER_HEARTBEAT_DEAD_THRESHOLD="${WALTER_HEARTBEAT_DEAD_THRESHOLD:-1800}"

# _heartbeat_file <agent> <issue_id> → print path; create parent dirs.
_heartbeat_file() {
  local agent="$1" issue_id="$2"
  local dir="$WALTER_HEARTBEAT_DIR/$agent"
  mkdir -p "$dir"
  printf '%s/%s.heartbeat\n' "$dir" "$issue_id"
}

# heartbeat_write <agent> <issue_id> <step> [status]
heartbeat_write() {
  local agent="$1" issue_id="$2" step="$3" status_val="${4:-}"
  local ts; ts="$(date -u +%s)"
  local file; file="$(_heartbeat_file "$agent" "$issue_id")"

  local entry
  # TODO Phase U: populate files_touched from tool-call instrumentation (currently stub [])
  if [[ -n "$status_val" ]]; then
    entry="$(jq -nc \
      --argjson ts "$ts" \
      --arg agent "$agent" \
      --arg issue_id "$issue_id" \
      --arg step "$step" \
      --arg status "$status_val" \
      '{ts: $ts, agent: $agent, issue_id: $issue_id, step: $step, status: $status, files_touched: [], tests_run: 0}')"
  else
    entry="$(jq -nc \
      --argjson ts "$ts" \
      --arg agent "$agent" \
      --arg issue_id "$issue_id" \
      --arg step "$step" \
      '{ts: $ts, agent: $agent, issue_id: $issue_id, step: $step, files_touched: [], tests_run: 0}')"
  fi

  # Atomic append via flock when available (Linux); fallback for macOS dev.
  local lock_file="${file}.lock"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 200
      printf '%s\n' "$entry" >> "$file"
    ) 200>"$lock_file"
  else
    printf '%s\n' "$entry" >> "$file"
  fi
}

# heartbeat_read_last <agent> <issue_id> → last line or empty
heartbeat_read_last() {
  local agent="$1" issue_id="$2"
  local file="$WALTER_HEARTBEAT_DIR/$agent/$issue_id.heartbeat"
  [[ -f "$file" ]] || { echo ""; return 0; }
  tail -1 "$file"
}

# heartbeat_checkpoint_steps <agent> <issue_id> <step_name>
# Reads the existing completed_steps from the last heartbeat line,
# adds the new step, and writes a new JSONL line.
heartbeat_checkpoint_steps() {
  local agent="$1" issue_id="$2" new_step="$3"
  local file="$WALTER_HEARTBEAT_DIR/$agent/$issue_id.heartbeat"
  local ts; ts="$(date -u +%s)"

  # Get current completed_steps from last line (default to empty array)
  local prev_steps="[]"
  if [[ -f "$file" ]]; then
    local last; last=$(tail -1 "$file")
    if [[ -n "$last" ]]; then
      local extracted
      extracted=$(echo "$last" | jq -c '.completed_steps // []' 2>/dev/null)
      [[ -n "$extracted" ]] && prev_steps="$extracted"
    fi
  fi

  local new_steps
  new_steps="$(jq -nc --argjson arr "$prev_steps" --arg step "$new_step" \
    '$arr + [$step]')"

  local entry
  entry="$(jq -nc \
    --argjson ts "$ts" \
    --arg agent "$agent" \
    --arg issue_id "$issue_id" \
    --arg step "$new_step" \
    --argjson completed_steps "$new_steps" \
    '{ts: $ts, agent: $agent, issue_id: $issue_id, step: $step, completed_steps: $completed_steps, files_touched: [], tests_run: 0}')"

  local lock_file="${file}.lock"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 200
      printf '%s\n' "$entry" >> "$file"
    ) 200>"$lock_file"
  else
    printf '%s\n' "$entry" >> "$file"
  fi
}

# heartbeat_read_checkpoint <agent> <issue_id> → JSON array of completed steps
heartbeat_read_checkpoint() {
  local agent="$1" issue_id="$2"
  local file="$WALTER_HEARTBEAT_DIR/$agent/$issue_id.heartbeat"
  [[ -f "$file" ]] || { echo "[]"; return 0; }

  # Scan from last line backwards to find most recent line with completed_steps
  local steps="[]"
  local line
  while IFS= read -r line; do
    local candidate
    candidate=$(echo "$line" | jq -c '.completed_steps // empty' 2>/dev/null)
    if [[ -n "$candidate" ]]; then
      steps="$candidate"
    fi
  done < "$file"

  echo "$steps"
}

# heartbeat_dead_threshold → integer seconds
heartbeat_dead_threshold() {
  echo "${WALTER_HEARTBEAT_DEAD_THRESHOLD:-1800}"
}
