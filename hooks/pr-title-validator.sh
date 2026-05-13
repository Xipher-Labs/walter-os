#!/usr/bin/env bash
# hooks/pr-title-validator.sh — validate PR title before `gh pr create` runs.
# Walter-OS convention: [TYPE] -CATEGORY- title
#
# Hook target: pre-`gh pr create` (sourced or invoked by the wrapper)
# Usage:
#   ./hooks/pr-title-validator.sh "$PR_TITLE"
# Exit codes:
#   0  — title is valid
#   1  — title is invalid (prints error + format reference)
#   2  — missing argument

set -euo pipefail

readonly TITLE="${1:-}"
readonly REGEX='^\[(FEAT|FIX|DOCS|CHORE|TEST)\] -(SECURITY|BUSINESS|COMPLIANCE|OPERATIONS|TECHNICAL|CUSTOMER|CONTENT|LEARNING)- [^[:space:]].{0,58}[^[:space:].]$'

if [[ -z "$TITLE" ]]; then
  echo "Usage: $0 \"<PR title>\"" >&2
  exit 2
fi

if echo "$TITLE" | grep -qE "$REGEX"; then
  exit 0
fi

cat >&2 <<EOF
PR title does not match Walter-OS convention.

Required format: [TYPE] -CATEGORY- title

  TYPE       : FEAT / FIX / DOCS / CHORE / TEST
  CATEGORY   : SECURITY / BUSINESS / COMPLIANCE / OPERATIONS / TECHNICAL / CUSTOMER / CONTENT / LEARNING
  Title body : sentence case, ≤60 chars, no trailing period

Examples:
  [FEAT] -BUSINESS- pricing-experiment skill (Van Westendorp + tier struct)
  [FIX] -SECURITY- enforce CCR_APIKEY on sub-router /v1 routes
  [CHORE] -OPERATIONS- bump hcloud-cli to v1.45 + audit baseline

Your title:
  $TITLE

See CONTRIBUTING.md -> "Title convention" for full rules.
EOF
exit 1
