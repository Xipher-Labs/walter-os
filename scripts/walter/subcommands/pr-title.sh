#!/usr/bin/env bash
# scripts/walter/subcommands/pr-title.sh
# Generate and validate a Walter-OS PR/issue title.
#
# Usage:
#   walter-os pr-title <TYPE> <CATEGORY> <title body>
# Example:
#   walter-os pr-title FEAT BUSINESS "saas-metrics-dashboard skill"
# Output:
#   [FEAT] -BUSINESS- saas-metrics-dashboard skill
# Exit codes:
#   0 — title generated and printed (validate separately if needed)
#   1 — invalid TYPE or CATEGORY
#   2 — missing arguments

set -euo pipefail

readonly VALID_TYPES="FEAT FIX DOCS CHORE TEST"
readonly VALID_CATEGORIES="SECURITY BUSINESS COMPLIANCE OPERATIONS TECHNICAL CUSTOMER CONTENT LEARNING"

print_usage() {
  cat >&2 <<EOF
Usage: walter-os pr-title <TYPE> <CATEGORY> <title body>

  TYPE     : FEAT / FIX / DOCS / CHORE / TEST
  CATEGORY : SECURITY / BUSINESS / COMPLIANCE / OPERATIONS / TECHNICAL / CUSTOMER / CONTENT / LEARNING

Examples:
  walter-os pr-title FEAT BUSINESS "saas-metrics-dashboard skill"
  walter-os pr-title FIX SECURITY "enforce CCR_APIKEY on sub-router /v1 routes"
  walter-os pr-title CHORE OPERATIONS "bump hcloud-cli to v1.45"
EOF
}

if [[ $# -lt 3 ]]; then
  echo "walter-os pr-title: missing arguments" >&2
  print_usage
  exit 2
fi

TYPE="${1^^}"
CATEGORY="${2^^}"
BODY="${*:3}"

if ! echo "$VALID_TYPES" | grep -qw "$TYPE"; then
  echo "walter-os pr-title: unknown TYPE '$TYPE'" >&2
  echo "Allowed: $VALID_TYPES" >&2
  exit 1
fi

if ! echo "$VALID_CATEGORIES" | grep -qw "$CATEGORY"; then
  echo "walter-os pr-title: unknown CATEGORY '$CATEGORY'" >&2
  echo "Allowed: $VALID_CATEGORIES" >&2
  exit 1
fi

# Construct the title and run it through the same validator CI uses.
# This prevents the helper from emitting titles that the workflow will reject.
TITLE="[$TYPE] -$CATEGORY- $BODY"
VALIDATOR_PATH="$(dirname "${BASH_SOURCE[0]}")/../../../hooks/pr-title-validator.sh"
if [[ -x "$VALIDATOR_PATH" ]]; then
  if ! "$VALIDATOR_PATH" "$TITLE" >/dev/null 2>&1; then
    echo "walter-os pr-title: generated title fails validator (body >60 chars or trailing period?)" >&2
    "$VALIDATOR_PATH" "$TITLE" >&2 || true
    exit 1
  fi
fi

echo "$TITLE"
