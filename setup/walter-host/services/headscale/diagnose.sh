#!/usr/bin/env bash
# Diagnose Headscale registration failures without changing VM state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${WALTER_HEADSCALE_COMPOSE:-${SCRIPT_DIR}/compose.yml}"
CONTAINER="${WALTER_HEADSCALE_CONTAINER:-headscale}"
SINCE="${WALTER_HEADSCALE_LOG_SINCE:-10m}"
MOCK_LOG=""
HEADSCALE_VERSION_OVERRIDE=""
TAILSCALE_VERSION_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: diagnose.sh [options]

Read-only diagnostic for Headscale client registration failures.

Options:
  --compose <path>              Compose file to inspect (default: service compose.yml)
  --container <name>            Headscale container name (default: headscale)
  --since <duration>            docker logs window (default: 10m)
  --mock-log <path>             Read log text from a file instead of docker logs
  --headscale-version <text>    Test override for detected Headscale version
  --tailscale-version <text>    Test override for detected Tailscale client version
  -h, --help                    Show this help

Exit codes:
  0  No known registration drift signature found
  1  Known Headscale/Tailscale capability-version drift signature found
  2  Invalid arguments or unreadable mock log
  3  Unable to inspect Headscale logs
EOF
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
    sed -nE 's/^[[:space:]]*image:[[:space:]]*headscale\/headscale:([^[:space:]]+).*/Headscale \1/p' "$COMPOSE_FILE" | head -1
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
      printf '%s\n' "$output" | head -1
    fi
  fi
}

headscale_version="$(detect_headscale_version)"
tailscale_version="$(detect_tailscale_version)"
logs="$(read_logs)"

echo "Headscale registration diagnostic"
echo "Headscale: ${headscale_version:-unknown}"
echo "Tailscale client: ${tailscale_version:-unknown}"
echo "Log window: ${MOCK_LOG:-docker logs ${CONTAINER} --since ${SINCE}}"

if grep -Fq "capability version must be set" <<<"$logs"; then
  cat <<'EOF'

RESULT: capability-version drift detected.

Headscale is rejecting client registration before the node joins the tailnet.
Do not keep retrying `tailscale up` as a break-glass path while this signature
is present.

Recommended recovery:
1. Use the Hetzner Cloud Firewall SSH allow-list break-glass path.
2. Decide whether to pin/downgrade Tailscale clients, upgrade Headscale after
   confirming compatibility, or keep Headscale non-critical.
3. Re-run this diagnostic and a live registration smoke test before treating
   Headscale as healthy.

Reference: setup/walter-host/services/headscale/RUNBOOK.md
EOF
  exit 1
fi

cat <<'EOF'

RESULT: no known capability-version drift signature found in the inspected logs.

This does not prove registration is healthy. Run a live client registration
smoke test and confirm `docker exec headscale headscale nodes list` shows the
joining device before relying on Headscale for private admin paths.
EOF
