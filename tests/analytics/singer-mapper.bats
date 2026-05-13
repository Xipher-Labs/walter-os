#!/usr/bin/env bats
# Tests for Singer stream processor — singer_to_analytics.py
#
# Covers:
#   BLOCKER 1 — STATE messages forwarded to stdout
#   WARN 4    — flock prevents concurrent run-tap.sh instances
#
# Refs: docs/specs/devrel-analytics-stack.md

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SINGER_PY="${REPO_ROOT}/setup/walter-host/singer/singer_to_analytics.py"
RUN_TAP="${REPO_ROOT}/setup/walter-host/singer/run-tap.sh"

# ─────────────────────────────────────────────────────────────────────────────
# BLOCKER 1: STATE forwarding
# ─────────────────────────────────────────────────────────────────────────────

@test "STATE message is forwarded to stdout" {
  # Feed a Singer stream with a RECORD then a STATE message
  stream='{"type":"RECORD","stream":"campaigns","record":{"campaign_id":"c1","date":"2026-01-01","cost_micros":1000000,"impressions":100,"clicks":10,"conversions":1}}
{"type":"STATE","value":{"bookmarks":{"campaigns":{"date":"2026-01-01"}}}}'

  # Run in dry-run mode so no DB needed; capture stdout and stderr separately
  stdout_out=$(echo "$stream" | python3 "$SINGER_PY" --tap google_ads --dry-run 2>/dev/null)

  # stdout should contain the state JSON value
  echo "stdout: $stdout_out"
  [[ "$stdout_out" == *'"bookmarks"'* ]]
}

@test "STATE message value appears on stdout as JSON" {
  state_value='{"bookmarks":{"campaigns":{"since_id":"abc123"}}}'
  stream='{"type":"STATE","value":'"$state_value"'}'

  stdout_out=$(echo "$stream" | python3 "$SINGER_PY" --tap google_ads --dry-run 2>/dev/null)

  echo "stdout: $stdout_out"
  # The state value dict should appear on stdout
  [[ "$stdout_out" == *'abc123'* ]]
}

@test "SCHEMA message does not appear on stdout" {
  stream='{"type":"SCHEMA","stream":"campaigns","schema":{"properties":{}},"key_properties":["id"]}'

  stdout_out=$(echo "$stream" | python3 "$SINGER_PY" --tap google_ads --dry-run 2>/dev/null)

  echo "stdout: $stdout_out"
  # SCHEMA should be silently ignored — stdout should be empty
  [[ -z "$stdout_out" ]]
}

@test "RECORD processing still works alongside STATE forwarding" {
  stream='{"type":"RECORD","stream":"campaigns","record":{"campaign_id":"c1","date":"2026-01-01","cost_micros":2000000,"impressions":200,"clicks":20,"conversions":2}}
{"type":"STATE","value":{"position":42}}'

  # stderr should contain mapper done message with counts
  stderr_out=$(echo "$stream" | python3 "$SINGER_PY" --tap google_ads --dry-run 2>&1 1>/dev/null)
  stdout_out=$(echo "$stream" | python3 "$SINGER_PY" --tap google_ads --dry-run 2>/dev/null)

  echo "stderr: $stderr_out"
  echo "stdout: $stdout_out"
  # State forwarded to stdout
  [[ "$stdout_out" == *'42'* ]]
  # Done message on stderr
  [[ "$stderr_out" == *'Done'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# WARN 4: flock — concurrent run prevention
# ─────────────────────────────────────────────────────────────────────────────

@test "run-tap.sh exits early if another instance appears to be running" {
  # Create a state dir
  state_dir="$(mktemp -d)"
  pid_file="${state_dir}/google_ads.pid"

  # Write current PID to simulate a running instance (self, always alive)
  echo "$$" > "$pid_file"

  # run-tap.sh should detect the running PID and exit 0 with warning
  result=$(SINGER_STATE_DIR="$state_dir" \
    ANALYTICS_DB_URL="postgres://fake" \
    TAP_CONFIG_DIR="$(mktemp -d)" \
    bash "$RUN_TAP" google_ads 2>&1) || exit_code=$?

  rm -rf "$state_dir"

  echo "result: $result"
  # Should warn about another instance running
  [[ "$result" == *"Another instance"* ]] || [[ "$result" == *"running"* ]]
}
