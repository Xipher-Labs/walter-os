#!/usr/bin/env bash
# Diagnose Headscale registration failures without changing VM state.

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != "bash" && "$SCRIPT_SOURCE" != "-bash" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  SCRIPT_DIR="$(pwd -P)"
fi
COMPOSE_FILE="${WALTER_HEADSCALE_COMPOSE:-${SCRIPT_DIR}/compose.yml}"
CONTAINER="${WALTER_HEADSCALE_CONTAINER:-headscale}"
SINCE="${WALTER_HEADSCALE_LOG_SINCE:-10m}"
RUNBOOK_PATH="${SCRIPT_DIR}/RUNBOOK.md"
MOCK_LOG=""
HEADSCALE_VERSION_OVERRIDE=""
TAILSCALE_VERSION_OVERRIDE=""

usage() {
  printf '%s\n' \
    'Usage: diagnose.sh [options]' \
    '' \
    'Read-only diagnostic for Headscale client registration failures.' \
    '' \
    'Options:' \
    '  --compose <path>              Compose file to inspect (default: service compose.yml)' \
    '  --container <name>            Headscale container name (default: headscale)' \
    '  --since <duration>            docker logs window (default: 10m)' \
    '  --mock-log <path>             Read log text from a file instead of docker logs' \
    '  --headscale-version <text>    Test override for detected Headscale version' \
    '  --tailscale-version <text>    Test override for detected Tailscale client version' \
    '  -h, --help                    Show this help' \
    '' \
    'Exit codes:' \
    '  0  No known runtime or registration blocker found' \
    '  1  Known Headscale runtime or registration blocker found' \
    '  2  Invalid arguments or unreadable mock log' \
    '  3  Unable to inspect Headscale logs'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose)
      [[ -n "${2:-}" ]] || { echo "ERROR: --compose requires a value" >&2; exit 2; }
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --container)
      [[ -n "${2:-}" ]] || { echo "ERROR: --container requires a value" >&2; exit 2; }
      CONTAINER="$2"
      shift 2
      ;;
    --since)
      [[ -n "${2:-}" ]] || { echo "ERROR: --since requires a value" >&2; exit 2; }
      SINCE="$2"
      shift 2
      ;;
    --mock-log)
      [[ -n "${2:-}" ]] || { echo "ERROR: --mock-log requires a value" >&2; exit 2; }
      MOCK_LOG="$2"
      shift 2
      ;;
    --headscale-version)
      [[ -n "${2:-}" ]] || { echo "ERROR: --headscale-version requires a value" >&2; exit 2; }
      HEADSCALE_VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --tailscale-version)
      [[ -n "${2:-}" ]] || { echo "ERROR: --tailscale-version requires a value" >&2; exit 2; }
      TAILSCALE_VERSION_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

read_logs() {
  if [[ -n "$MOCK_LOG" ]]; then
    [[ -r "$MOCK_LOG" ]] || { echo "ERROR: mock log is not readable: $MOCK_LOG" >&2; exit 2; }
    cat "$MOCK_LOG"
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    local output
    if output="$(docker logs "$CONTAINER" --since "$SINCE" 2>&1)"; then
      printf '%s\n' "$output"
      return
    fi

    echo "ERROR: could not inspect Headscale logs from container '${CONTAINER}'." >&2
    echo "$output" >&2
    exit 3
  fi

  echo "ERROR: docker not available; cannot inspect Headscale logs." >&2
  exit 3
}

detect_headscale_version() {
  if [[ -n "$HEADSCALE_VERSION_OVERRIDE" ]]; then
    printf '%s\n' "$HEADSCALE_VERSION_OVERRIDE"
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    local output
    if output="$(docker exec "$CONTAINER" headscale version 2>/dev/null)"; then
      printf '%s\n' "$output"
      return
    fi
  fi

  if [[ -r "$COMPOSE_FILE" ]]; then
    awk '
      /^[[:space:]]*image:[[:space:]]*headscale\/headscale:/ {
        sub(/^[[:space:]]*image:[[:space:]]*headscale\/headscale:/, "")
        sub(/[[:space:]].*$/, "")
        print "Headscale " $0
        exit
      }
    ' "$COMPOSE_FILE"
  fi
}

detect_tailscale_version() {
  if [[ -n "$TAILSCALE_VERSION_OVERRIDE" ]]; then
    printf '%s\n' "$TAILSCALE_VERSION_OVERRIDE"
    return
  fi

  if command -v tailscale >/dev/null 2>&1; then
    local output
    if output="$(tailscale version 2>/dev/null)"; then
      printf '%s\n' "${output%%$'\n'*}"
    fi
  fi
}

detect_container_state() {
  if [[ -n "$MOCK_LOG" ]]; then
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    local state
    if state="$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>&1)"; then
      printf '%s\n' "$state"
      return
    fi
    if grep -Eqi 'No such (object|container)' <<<"$state"; then
      printf '%s\n' "missing"
    fi
  fi
}

headscale_version="$(detect_headscale_version)"
tailscale_version="$(detect_tailscale_version)"
container_state="$(detect_container_state)"

echo "Headscale registration diagnostic"
echo "Headscale: ${headscale_version:-unknown}"
echo "Tailscale client: ${tailscale_version:-unknown}"
if [[ -n "$container_state" ]]; then
  echo "Container state: $container_state"
fi
echo "Log window: ${MOCK_LOG:-docker logs ${CONTAINER} --since ${SINCE}}"

if [[ -n "$container_state" && "$container_state" != "running" ]]; then
  printf '%s\n' \
    '' \
    'RESULT: Headscale container is not running.' \
    '' \
    'The tailnet cannot accept client registration while the service is stopped,' \
    'even if stale logs do not show a current capability-version signature.' \
    '' \
    'Recommended recovery:' \
    "1. Start or redeploy the service: docker compose -f ${COMPOSE_FILE} up -d" \
    '2. Re-run: deploy.sh --diagnose' \
    '3. Retry a live client registration smoke test before relying on Headscale.' \
    '' \
    "Reference: ${RUNBOOK_PATH}"
  exit 1
fi

logs="$(read_logs)"

if grep -Fq "capability version must be set" <<<"$logs"; then
  printf '%s\n' \
    '' \
    'RESULT: capability-version rejection signature detected.' \
    '' \
    'Headscale logged "capability version must be set". During a real' \
    'tailscale up attempt, this usually means the server rejected client' \
    'registration before the node joined the tailnet.' \
    '' \
    'Important: a manual curl to /key without a capver query can produce the' \
    'same log line. If you just probed /key manually, clear the log window,' \
    'run a live tailscale up registration attempt, and re-run this diagnostic' \
    'before treating the finding as confirmed client/server drift.' \
    '' \
    'Recommended recovery:' \
    '1. Use the Hetzner Cloud Firewall SSH allow-list break-glass path.' \
    '2. Decide whether to pin/downgrade Tailscale clients, upgrade Headscale after' \
    '   confirming compatibility, or keep Headscale non-critical.' \
    '3. Re-run this diagnostic and a live registration smoke test before treating' \
    '   Headscale as healthy.' \
    '' \
    "Reference: ${RUNBOOK_PATH}"
  exit 1
fi

if grep -Fq "No Upgrade header in TS2021 request" <<<"$logs"; then
  printf '%s\n' \
    '' \
    'RESULT: TS2021 WebSocket proxy warning detected.' \
    '' \
    'Headscale is receiving TS2021 registration traffic without an Upgrade' \
    'header. This usually means the reverse proxy is not passing WebSocket upgrade headers through to Headscale.' \
    '' \
    'Recommended recovery:' \
    "1. Inspect the Cloudflare Tunnel/Caddy route for headscale.\${WALTER_DOMAIN}" \
    '2. Verify WebSocket upgrade headers reach the Headscale container.' \
    '3. Re-run this diagnostic and a live registration smoke test.' \
    '' \
    "Reference: ${RUNBOOK_PATH}"
  exit 1
fi

printf '%s\n' \
  '' \
  'RESULT: no known runtime or registration blocker found in the inspected state.' \
  '' \
  'This does not prove registration is healthy. Run a live client registration' \
  'smoke test and confirm docker exec headscale headscale nodes list shows the' \
  'joining device before relying on Headscale for private admin paths.'
