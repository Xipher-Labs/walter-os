#!/usr/bin/env bash
# Walter-VM Singer tap runner
#
# Runs a Singer tap with state management and pipes output through
# singer_to_analytics.py into Postgres analytics DB.
#
# Usage:
#   ./run-tap.sh google_ads
#   ./run-tap.sh facebook
#   ./run-tap.sh google_analytics
#   ./run-tap.sh linkedin_ads    # Tier 3 — requires LinkedIn approval
#
# Required env vars (set in .env or via Infisical):
#   ANALYTICS_DB_URL       Postgres connection URL
#   SINGER_STATE_DIR       Dir for state files (default: ~/.config/walter-os/singer-state)
#   TAP_CONFIG_DIR         Dir for tap config JSON files (default: ~/.config/walter-os/singer-configs)
#
# Prereqs per tap (see docs/specs/devrel-analytics-stack.md):
#   google_ads:    GOOGLE_ADS_DEVELOPER_TOKEN, OAuth credentials (V-prereq-1, 3-5 days)
#   facebook:      META_APP_ID, META_ACCESS_TOKEN (V-prereq-2, 5-15 days)
#   google_analytics: GA4_PROPERTY_ID, OAuth credentials
#   linkedin_ads:  LINKEDIN_ACCESS_TOKEN (V-prereq-3, Tier 3)
#
# Refs: docs/specs/devrel-analytics-stack.md (Decision 2 — Singer integration pattern)

set -euo pipefail

TAP="${1:-}"
if [[ -z "$TAP" ]]; then
  echo "Usage: $0 <tap_name>" >&2
  echo "  Available: google_ads, facebook, google_analytics, linkedin_ads" >&2
  exit 1
fi

ANALYTICS_DB_URL="${ANALYTICS_DB_URL:-}"
SINGER_STATE_DIR="${SINGER_STATE_DIR:-${HOME}/.config/walter-os/singer-state}"
TAP_CONFIG_DIR="${TAP_CONFIG_DIR:-${HOME}/.config/walter-os/singer-configs}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$ANALYTICS_DB_URL" ]]; then
  echo "[run-tap] ERROR: ANALYTICS_DB_URL not set." >&2
  echo "  Set it in your .env or Infisical workspace 'walter-os'." >&2
  exit 1
fi

# Ensure state dir exists (gitignored)
mkdir -p "$SINGER_STATE_DIR"
mkdir -p "$TAP_CONFIG_DIR"

# Prevent concurrent runs of the same tap via file lock (early, before tap checks)
# Uses flock on Linux; PID-file fallback on macOS (no flock available)
LOCK_FILE="${SINGER_STATE_DIR}/${TAP:-unknown}.lock"
exec 200>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  # Linux: non-blocking exclusive lock on fd 200
  flock -n 200 || {
    echo "[run-tap] Another instance of ${TAP:-unknown} running, exiting." >&2
    exit 0
  }
else
  # macOS fallback: PID file best-effort guard
  PID_FILE="${SINGER_STATE_DIR}/${TAP:-unknown}.pid"
  if [[ -f "$PID_FILE" ]]; then
    existing_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "[run-tap] Another instance of ${TAP:-unknown} running (PID $existing_pid), exiting." >&2
      exit 0
    fi
  fi
  echo "$$" > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT
fi

# Map tap name to pip package + config file
case "$TAP" in
  google_ads|google-ads)
    TAP_BIN="tap-google-ads"
    TAP_PACKAGE="tap-google-ads"
    CONFIG_FILE="${TAP_CONFIG_DIR}/google-ads.json"
    STATE_FILE="${SINGER_STATE_DIR}/google-ads.json"
    PREREQ_VAR="GOOGLE_ADS_DEVELOPER_TOKEN"
    ;;
  facebook|meta|tap-facebook)
    TAP_BIN="tap-facebook"
    TAP_PACKAGE="tap-facebook"
    CONFIG_FILE="${TAP_CONFIG_DIR}/facebook.json"
    STATE_FILE="${SINGER_STATE_DIR}/facebook.json"
    PREREQ_VAR="META_ACCESS_TOKEN"
    ;;
  google_analytics|ga4|tap-google-analytics)
    TAP_BIN="tap-google-analytics"
    TAP_PACKAGE="tap-google-analytics"
    CONFIG_FILE="${TAP_CONFIG_DIR}/google-analytics.json"
    STATE_FILE="${SINGER_STATE_DIR}/google-analytics.json"
    PREREQ_VAR="GA4_PROPERTY_ID"
    ;;
  linkedin_ads|linkedin|tap-linkedin-ads)
    TAP_BIN="tap-linkedin-ads"
    TAP_PACKAGE="tap-linkedin-ads"
    CONFIG_FILE="${TAP_CONFIG_DIR}/linkedin-ads.json"
    STATE_FILE="${SINGER_STATE_DIR}/linkedin-ads.json"
    PREREQ_VAR="LINKEDIN_ACCESS_TOKEN"
    ;;
  *)
    echo "[run-tap] ERROR: Unknown tap: $TAP" >&2
    echo "  Known: google_ads, facebook, google_analytics, linkedin_ads" >&2
    exit 1
    ;;
esac

# Check that the tap is installed
if ! command -v "$TAP_BIN" >/dev/null 2>&1; then
  echo "[run-tap] ERROR: $TAP_BIN not found. Install with:" >&2
  echo "  pip install $TAP_PACKAGE" >&2
  echo "  (see V-prereq-9 in docs/operational/council-v2-prereqs.md)" >&2
  exit 1
fi

# Check prereq env var is set (not necessarily approved, but at least configured)
if [[ -z "${!PREREQ_VAR:-}" ]]; then
  echo "[run-tap] ERROR: $PREREQ_VAR not set." >&2
  echo "  This tap requires operator-approved API access." >&2
  echo "  See docs/specs/devrel-analytics-stack.md for prereqs." >&2
  exit 1
fi

# Check config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[run-tap] ERROR: Config file not found: $CONFIG_FILE" >&2
  echo "  Create it from the template: setup/walter-host/singer/configs/${TAP}/config.json.example" >&2
  exit 1
fi

echo "[run-tap] Starting $TAP_BIN ..."
echo "[run-tap] Config: $CONFIG_FILE"
echo "[run-tap] State:  ${STATE_FILE} ($([ -f "$STATE_FILE" ] && echo "exists" || echo "new sync"))"

# Build state args
STATE_ARGS=()
if [[ -f "$STATE_FILE" ]]; then
  STATE_ARGS=(--state "$STATE_FILE")
fi

# Run: tap → mapper → Postgres
# The mapper reads from stdin (Singer JSON), writes to Postgres, outputs state to stdout.
# We capture the state output and update the state file for next run.
TMP_STATE="$(mktemp)"
trap 'rm -f "$TMP_STATE"' EXIT

"$TAP_BIN" --config "$CONFIG_FILE" "${STATE_ARGS[@]}" \
  | python3 "${SCRIPT_DIR}/singer_to_analytics.py" --tap "$TAP" --db-url "$ANALYTICS_DB_URL" \
  > "$TMP_STATE"

# Update state file if tap emitted a new state
if [[ -s "$TMP_STATE" ]]; then
  mv "$TMP_STATE" "$STATE_FILE"
  echo "[run-tap] State updated: $STATE_FILE"
fi

echo "[run-tap] Done: $TAP_BIN"
