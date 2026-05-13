#!/usr/bin/env bash
# scripts/agents/watchdog.sh — Zombie detection for stalled agent tasks.
#
# A "zombie" is a Plane issue in "claimed" state whose last heartbeat
# is older than heartbeat_dead_threshold seconds (default: 1800 = 30 min).
#
# For each zombie detected, this script:
#   1. Posts a Plane comment with the zombie declaration + last known step.
#   2. Moves the issue state to "ready" (releasing it for re-claim).
#   3. Emits a warn alert via alert_emit.
#   4. Logs a JSONL entry to WALTER_WATCHDOG_LOG.
#
# Idempotency: the script records zombie actions in the watchdog log with
# the issue ID. On re-run it skips issues already logged as zombie in the
# current epoch window (same issue ID within the last threshold seconds).
#
# Usage:
#   watchdog.sh [--dry-run] [--help]
#
# Environment variables:
#   WALTER_HEARTBEAT_DIR        Heartbeat files root (default: /var/lib/walter-council/heartbeats)
#   WALTER_WATCHDOG_LOG         Watchdog log path (default: /var/log/walter-council/watchdog.log)
#   WALTER_HEARTBEAT_DEAD_THRESHOLD  Seconds before declaring zombie (default: 1800)
#   PLANE_API_TOKEN, PLANE_API_URL, PLANE_WORKSPACE, PLANE_PROJECT  — required
#
# Spec: docs/specs/walter-council-v2.md — Improvement 5 (T-19)

set -uo pipefail

# ---- parse args ----

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "watchdog.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ---- env + lib ----

WALTER_OS_HOME="${WALTER_OS_HOME:?must be set; source ~/.config/walter-os/env}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="$SCRIPT_DIR/lib"

# ---- cron lock: prevent concurrent watchdog runs ----
# WALTER_WATCHDOG_LOCK allows tests to use an isolated lock path (avoids
# cross-test contamination from a stale lock held by a dying sleep process).
LOCK="${WALTER_WATCHDOG_LOCK:-/tmp/walter-watchdog.lock}"
exec 9>"$LOCK"
# R11: if flock is not installed (exit 127 = command not found), warn and continue.
# If flock fails because another instance holds the lock (exit non-127), exit on Linux.
_flock_rc=0
flock -n 9 2>/dev/null || _flock_rc=$?
if [ "$_flock_rc" -ne 0 ]; then
  if [ "$_flock_rc" -eq 127 ] || [ "$(uname)" = "Darwin" ]; then
    echo "watchdog: flock unavailable — running without exclusive lock (dev/macOS)" >&2
  else
    echo "watchdog: another instance running, exiting" >&2
    exit 0
  fi
fi

# shellcheck disable=SC1091
source "$LIB_DIR/heartbeat.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/alerts.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/plane.sh"

# ---- config ----

WALTER_WATCHDOG_LOG="${WALTER_WATCHDOG_LOG:-/var/log/walter-council/watchdog.log}"
THRESHOLD=$(heartbeat_dead_threshold)
NOW=$(date +%s)

# ---- helpers ----

_watchdog_log() {
  local event="$1" issue_id="$2" reason="$3"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local log_dir; log_dir="$(dirname "$WALTER_WATCHDOG_LOG")"
  [[ -d "$log_dir" ]] || mkdir -p "$log_dir"
  local entry
  entry="$(jq -nc \
    --arg ts "$ts" \
    --arg event "$event" \
    --arg issue_id "$issue_id" \
    --arg reason "$reason" \
    '{ts: $ts, event: $event, issue_id: $issue_id, reason: $reason}' 2>/dev/null \
    || printf '{"ts":"%s","event":"%s","issue_id":"%s","reason":"%s"}\n' \
        "$ts" "$event" "$issue_id" "$reason")"
  printf '%s\n' "$entry" >> "$WALTER_WATCHDOG_LOG"
}

# Build O(1) recently-logged zombie lookup table from the watchdog log.
# Populated once at script init; _already_logged_zombie is then O(1).
declare -A RECENTLY_LOGGED
_build_zombie_lookup() {
  [[ -f "$WALTER_WATCHDOG_LOG" ]] || return 0
  local cutoff=$(( NOW - THRESHOLD ))
  while IFS= read -r line; do
    local entry_event entry_issue entry_ts_str
    entry_event="$(echo "$line" | jq -r '.event // ""' 2>/dev/null)"
    entry_issue="$(echo "$line" | jq -r '.issue_id // ""' 2>/dev/null)"
    entry_ts_str="$(echo "$line" | jq -r '.ts // ""' 2>/dev/null)"
    if [[ "$entry_event" == "zombie_detected" && -n "$entry_issue" ]]; then
      local entry_epoch
      if command -v gdate >/dev/null 2>&1; then
        entry_epoch=$(gdate -d "$entry_ts_str" +%s 2>/dev/null || echo 0)
      elif date -j >/dev/null 2>&1; then
        entry_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$entry_ts_str" +%s 2>/dev/null || echo 0)
      else
        entry_epoch=$(date -d "$entry_ts_str" +%s 2>/dev/null || echo 0)
      fi
      if [[ "$entry_epoch" -gt "$cutoff" ]]; then
        RECENTLY_LOGGED["$entry_issue"]=1
      fi
    fi
  done < "$WALTER_WATCHDOG_LOG"
}

# _already_logged_zombie <issue_id> → 0 if already logged in last THRESHOLD seconds
# O(1) lookup after _build_zombie_lookup is called once.
_already_logged_zombie() {
  local issue_id="$1"
  [ -n "${RECENTLY_LOGGED[$issue_id]:-}" ]
}

# ---- main loop ----

# Prereq: PLANE_API_TOKEN must be set (checked by plane.sh, but let's give a clear message)
if [[ -z "${PLANE_API_TOKEN:-}" ]]; then
  echo "watchdog.sh: PLANE_API_TOKEN not set. Cannot query Plane for claimed issues." >&2
  echo "  Set PLANE_API_TOKEN, PLANE_API_URL, PLANE_WORKSPACE, PLANE_PROJECT env vars." >&2
  exit 2
fi

# Get all claimed issues
CLAIMED_ISSUES=()
while IFS= read -r issue_id; do
  [[ -n "$issue_id" ]] && CLAIMED_ISSUES+=("$issue_id")
done < <(plane_issues_list_by_state "claimed" 2>/dev/null || true)

if [[ ${#CLAIMED_ISSUES[@]} -eq 0 ]]; then
  echo "watchdog.sh: no claimed issues found. Nothing to check."
  _watchdog_log "scan_complete" "" "no claimed issues"
  exit 0
fi

echo "watchdog.sh: checking ${#CLAIMED_ISSUES[@]} claimed issue(s) for zombies..."

# Build O(1) lookup table once before the loop
_build_zombie_lookup

ZOMBIE_COUNT=0

for issue_id in "${CLAIMED_ISSUES[@]}"; do
  # Find heartbeat file: search all agents
  HEARTBEAT_FILE=""
  if [[ -d "$WALTER_HEARTBEAT_DIR" ]]; then
    HEARTBEAT_FILE=$(find "$WALTER_HEARTBEAT_DIR" -name "${issue_id}.heartbeat" 2>/dev/null | head -1)
  fi

  IS_ZOMBIE=0
  ZOMBIE_REASON=""
  LAST_STEP=""

  if [[ -z "$HEARTBEAT_FILE" || ! -f "$HEARTBEAT_FILE" ]]; then
    IS_ZOMBIE=1
    ZOMBIE_REASON="no heartbeat file found"
  else
    # Get last heartbeat timestamp
    local_last=$(tail -1 "$HEARTBEAT_FILE" 2>/dev/null)
    if [[ -z "$local_last" ]]; then
      IS_ZOMBIE=1
      ZOMBIE_REASON="heartbeat file is empty"
    else
      last_ts=$(echo "$local_last" | jq -r '.ts // 0' 2>/dev/null || echo 0)
      LAST_STEP=$(echo "$local_last" | jq -r '.step // "unknown"' 2>/dev/null || echo "unknown")
      last_status=$(echo "$local_last" | jq -r '.status // ""' 2>/dev/null || echo "")

      # If already done/failed, it's not a zombie (normal completion)
      if [[ "$last_status" == "done" || "$last_status" == "failed" ]]; then
        IS_ZOMBIE=0
      elif [[ $(( NOW - last_ts )) -gt "$THRESHOLD" ]]; then
        IS_ZOMBIE=1
        ZOMBIE_REASON="heartbeat stale: last seen $(( NOW - last_ts ))s ago (threshold: ${THRESHOLD}s). Last step: ${LAST_STEP}"
      fi
    fi
  fi

  if [[ "$IS_ZOMBIE" -eq 0 ]]; then
    continue
  fi

  # Idempotency check: skip if already declared zombie recently
  if _already_logged_zombie "$issue_id"; then
    echo "watchdog.sh: issue $issue_id already declared zombie recently, skipping."
    continue
  fi

  ZOMBIE_COUNT=$(( ZOMBIE_COUNT + 1 ))
  echo "watchdog.sh: ZOMBIE detected: issue=$issue_id reason=$ZOMBIE_REASON"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] Would: comment + set state=awaiting-resume + alert"
    _watchdog_log "zombie_detected" "$issue_id" "[dry-run] $ZOMBIE_REASON"
    continue
  fi

  # 1. Post Plane comment with zombie declaration
  local_comment="[watchdog] Zombie detected. Reason: ${ZOMBIE_REASON}. Releasing for re-claim."
  plane_issue_comment "$issue_id" "$local_comment" 2>/dev/null || \
    echo "watchdog.sh: failed to post comment to $issue_id" >&2

  # 2. Move to "awaiting-resume" state (releasing for re-claim) and clear assignee.
  # "awaiting-resume" is semantically correct: the task was abandoned mid-work,
  # not freshly created. Operators can distinguish zombies from new tasks.
  # Consistent with docs/operational/council-v2-prereqs.md.
  plane_issue_set_state "$issue_id" "awaiting-resume" 2>/dev/null || \
    echo "watchdog.sh: failed to set state=awaiting-resume for $issue_id" >&2
  plane_issue_clear_assignee "$issue_id" 2>/dev/null || \
    echo "watchdog.sh: failed to clear assignee for $issue_id" >&2

  # 3. Emit warn alert
  alert_emit warn "zombie detected: $issue_id" \
    "$(jq -nc --arg issue "$issue_id" --arg reason "$ZOMBIE_REASON" \
      '{event:"zombie_detected",issue_id:$issue,reason:$reason}')" 2>/dev/null || true

  # 4. Log to watchdog log
  _watchdog_log "zombie_detected" "$issue_id" "$ZOMBIE_REASON"
done

echo "watchdog.sh: scan complete. Zombies found: ${ZOMBIE_COUNT}."
_watchdog_log "scan_complete" "" "zombies_found=${ZOMBIE_COUNT}"
exit 0
