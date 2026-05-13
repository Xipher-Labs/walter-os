#!/usr/bin/env bash
# scripts/agents/lib/metrics.sh — Prometheus text-format metrics writer.
# Sourced (not exec'd) by the agent runner and any script that emits metrics.
#
# Metrics are written to a textfile_collector-compatible .prom file that
# Node Exporter picks up and exposes at :9100/metrics. This avoids adding
# an HTTP server to the agent runner.
#
# Usage:
#   source metrics.sh
#   metrics_init                                  # idempotent; writes HELP/TYPE headers if file new
#   metric_inc <name> <labels> <delta>            # increment counter by delta
#   metric_set <name> <labels> <value>            # set gauge to value
#
# File locking via flock(1) prevents corruption from concurrent agent runs.
#
# Spec: docs/specs/walter-council-v2.md — Improvement 1 (T-1)
# Refs: T-1

# shellcheck disable=SC2034
WALTER_METRICS_LIB_VERSION=1

# Default metrics file path; override via env for tests.
WALTER_METRICS_FILE="${WALTER_METRICS_FILE:-/var/lib/walter-council/metrics.prom}"
WALTER_METRICS_LOCK="${WALTER_METRICS_LOCK:-${WALTER_METRICS_FILE}.lock}"

# Known metric definitions used by metrics_init.
# Format: "TYPE name help_string"
_WALTER_METRICS_DEFS=(
  "counter walter_council_tasks_total       'Tasks completed by the Walter Council agents'"
  "counter walter_council_tokens_total      'Tokens consumed by Walter Council agents'"
  "counter walter_council_approvals_total   'Approval-gate events (blocked/allowed)'"
  "gauge   walter_council_task_duration_seconds 'Task duration from claim to done/failed'"
  "gauge   walter_council_agent_state        'Current state of each agent (0=idle, 1=working, 2=blocked)'"
  "gauge   walter_council_heartbeat_age_seconds 'Seconds since last agent heartbeat'"
)

# _metrics_ensure_dir — create the metrics directory if it doesn't exist.
# Sets directory permissions so node-exporter (runs as nobody) can read
# the .prom files written here.
_metrics_ensure_dir() {
  local dir; dir="$(dirname "$WALTER_METRICS_FILE")"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    chmod 755 "$dir"
  fi
}

# _metrics_lock <cmd> — run <cmd> under an exclusive flock on WALTER_METRICS_LOCK.
# Timeout: 5 seconds to avoid deadlocks.
# Falls back to no-locking on macOS (where flock is unavailable); single-process
# dev runs are fine without it.
_metrics_lock() {
  _metrics_ensure_dir
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 5 200 || {
        echo "metrics.sh: failed to acquire lock within 5s" >&2
        exit 1
      }
      "$@"
    ) 200>"$WALTER_METRICS_LOCK"
    return $?
  else
    # No flock available (macOS dev) — run without locking.
    "$@"
  fi
}

# _metrics_get_value <name> <labels> — read current value from file, default 0.
_metrics_get_value() {
  local name="$1" labels="$2"
  if [[ -f "$WALTER_METRICS_FILE" ]]; then
    local pattern="${name}{${labels}}"
    grep -F "$pattern " "$WALTER_METRICS_FILE" 2>/dev/null | awk '{print $NF}' | tail -1
  fi
}

# _metrics_set_raw <name> <labels> <value> — write metric line to file (must be called under lock).
_metrics_set_raw() {
  local name="$1" labels="$2" value="$3"
  local tmp; tmp="$(mktemp "$WALTER_METRICS_FILE.XXXXXX")"

  if [[ -f "$WALTER_METRICS_FILE" ]]; then
    # Remove any existing line for this name+label combo, then append new value.
    if [[ -n "$labels" ]]; then
      grep -vF "${name}{${labels}}" "$WALTER_METRICS_FILE" > "$tmp" 2>/dev/null || true
    else
      grep -vF "${name} " "$WALTER_METRICS_FILE" > "$tmp" 2>/dev/null || true
    fi
  else
    : > "$tmp"
  fi

  if [[ -n "$labels" ]]; then
    printf '%s{%s} %s\n' "$name" "$labels" "$value" >> "$tmp"
  else
    printf '%s %s\n' "$name" "$value" >> "$tmp"
  fi

  chmod 644 "$tmp"
  mv "$tmp" "$WALTER_METRICS_FILE"
}

# metrics_init — idempotent initialization.
# Writes HELP/TYPE headers for all known metrics if the file is new or
# headers are missing. Existing metric values are preserved; no initial
# samples are written (metrics appear in Prometheus only after the first
# real emission via metric_inc / metric_set).
metrics_init() {
  _metrics_ensure_dir

  _metrics_lock _metrics_init_locked
}

_metrics_init_locked() {
  local file="$WALTER_METRICS_FILE"

  # Build list of names already in file (if file exists)
  local existing_names=()
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      # Skip comment lines and blank lines
      [[ "$line" =~ ^#.*$ ]] && continue
      [[ -z "$line" ]] && continue
      local n; n="${line%%{*}"; n="${n%% *}"
      existing_names+=("$n")
    done < "$file"
  fi

  # Write HELP/TYPE headers once (to a header file used by textfile_collector convention).
  # Note: does NOT write initial 0-value samples — Prometheus will show "no data"
  # until the first emission. Panels should use `or vector(0)` for zero-safe display.
  local tmp; tmp="$(mktemp "$file.XXXXXX")"

  # Preserve existing content
  if [[ -f "$file" ]]; then
    cp "$file" "$tmp"
  else
    : > "$tmp"
  fi

  for def in "${_WALTER_METRICS_DEFS[@]}"; do
    local mtype mname mhelp
    read -r mtype mname mhelp <<< "$def"
    mhelp="${mhelp//\'/}"

    # Write HELP/TYPE if not already in file
    if ! grep -qF "# HELP $mname" "$tmp" 2>/dev/null; then
      {
        printf '# HELP %s %s\n' "$mname" "$mhelp"
        printf '# TYPE %s %s\n' "$mtype" "$mname"
      } >> "$tmp"
    fi
  done

  mv "$tmp" "$file"
  chmod 644 "$file"
}

# metric_inc <name> <labels> <delta> — increment a counter by delta.
# Creates the metric at 0 first if not present, then adds delta.
metric_inc() {
  local name="$1" labels="$2" delta="${3:-1}"
  _metrics_lock _metric_inc_locked "$name" "$labels" "$delta"
}

_metric_inc_locked() {
  local name="$1" labels="$2" delta="${3:-1}"
  local current; current="$(_metrics_get_value "$name" "$labels")"
  current="${current:-0}"
  local new_val; new_val=$(( ${current%.*} + ${delta%.*} ))
  _metrics_set_raw "$name" "$labels" "$new_val"
}

# metric_set <name> <labels> <value> — set a gauge to value.
metric_set() {
  local name="$1" labels="$2" value="$3"
  _metrics_lock _metrics_set_raw "$name" "$labels" "$value"
}
