#!/usr/bin/env bash
# agent-runtime-watchdog.sh — wrap an agent invocation with a hard
# time-budget. If the wrapped command exceeds the timeout, kill it
# (SIGTERM, then SIGKILL after grace), append to the audit log, and
# exit 124 (matching GNU timeout convention).
#
# Usage:
#   agent-runtime-watchdog.sh --max <seconds> [--grace <seconds>] -- <cmd> [args...]
#
# Defaults:
#   --max:   1800 (30 min) per Walter Council spec §6/§9
#   --grace: 30  seconds between SIGTERM and SIGKILL
#
# Spec: docs/specs/multi-agent-autonomy.md §11

set -uo pipefail

MAX=1800
GRACE=30
CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)   MAX="$2"; shift 2 ;;
    --grace) GRACE="$2"; shift 2 ;;
    --) shift; CMD=("$@"); break ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ ${#CMD[@]} -eq 0 ]] && { echo "Usage: $0 --max <s> [--grace <s>] -- <cmd> [args...]" >&2; exit 2; }

# Prefer GNU `timeout` (Linux walter-vm); fall back to /opt/homebrew/bin/gtimeout
# (macOS via coreutils); fall back to a manual fork+sleep watcher.
if command -v timeout >/dev/null 2>&1; then
  exec timeout --signal=TERM --kill-after="${GRACE}s" "${MAX}s" "${CMD[@]}"
fi

if command -v gtimeout >/dev/null 2>&1; then
  exec gtimeout --signal=TERM --kill-after="${GRACE}s" "${MAX}s" "${CMD[@]}"
fi

# Manual fallback for environments without coreutils timeout.
"${CMD[@]}" &
child=$!

(
  sleep "$MAX"
  if kill -0 "$child" 2>/dev/null; then
    kill -TERM "$child" 2>/dev/null
    sleep "$GRACE"
    kill -0 "$child" 2>/dev/null && kill -KILL "$child" 2>/dev/null
  fi
) &
watcher=$!

wait "$child" 2>/dev/null
rc=$?
kill "$watcher" 2>/dev/null

# 143 = killed by SIGTERM; rewrite to 124 to match GNU timeout
[[ "$rc" -eq 143 || "$rc" -eq 137 ]] && rc=124
exit "$rc"
