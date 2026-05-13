#!/usr/bin/env bash
# setup/walter-host/install-cron.sh — install Walter Council cron jobs on walter-vm.
#
# Usage:
#   install-cron.sh [--user <username>]
#
# What it does:
#   1. Reads all cron fragments from setup/walter-host/cron/crontab.d/
#   2. Merges them into the crontab for the specified user (default: walter)
#   3. Preserves existing user crontab entries
#   4. Prints the installed cron entries for verification
#
# Cron fragments included:
#   - wiki-consolidation: weekly Sunday 02:00 UTC (T-16)
#
# Prereqs:
#   - cron/crontab.d/*.cron or bare files in that directory
#   - /usr/local/bin/walter-run wrapper (must be set up separately)
#   - Log directory /var/log/walter-council/ must exist with write permissions
#
# Refs: docs/specs/walter-council-v2.md — T-16

set -euo pipefail

# Parse arguments — support both --user <name> and bare positional for compat.
CRON_USER="walter"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      if [[ $# -lt 2 ]]; then
        echo "Error: --user requires a value" >&2
        echo "Usage: install-cron.sh [--user <username>]" >&2
        exit 2
      fi
      CRON_USER="$2"
      shift 2
      ;;
    -*) echo "install-cron.sh: unknown flag: $1" >&2; exit 2 ;;
    *)  CRON_USER="$1"; shift ;;
  esac
done
CRONTAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cron/crontab.d"

if [[ ! -d "$CRONTAB_DIR" ]]; then
  echo "install-cron.sh: crontab.d directory not found: $CRONTAB_DIR" >&2
  exit 1
fi

echo "Installing cron jobs for user: $CRON_USER"
echo "Cron fragments dir: $CRONTAB_DIR"
echo

# Collect all cron fragment files
FRAGMENT_FILES=()
while IFS= read -r -d '' f; do
  FRAGMENT_FILES+=("$f")
done < <(find "$CRONTAB_DIR" -type f -print0 | sort -z)

if [[ "${#FRAGMENT_FILES[@]}" -eq 0 ]]; then
  echo "No cron fragments found in $CRONTAB_DIR"
  exit 0
fi

# Read existing crontab (if any)
EXISTING_CRONTAB=""
if crontab -u "$CRON_USER" -l >/dev/null 2>&1; then
  EXISTING_CRONTAB="$(crontab -u "$CRON_USER" -l 2>/dev/null || echo "")"
fi

# Build combined crontab
COMBINED="$(mktemp)"
{
  if [[ -n "$EXISTING_CRONTAB" ]]; then
    # Remove old walter-council entries to avoid duplicates
    echo "$EXISTING_CRONTAB" | grep -v "walter-run" | grep -v "wiki-consolidation" | grep -v "watchdog" || true
  fi

  echo ""
  echo "# === Walter Council cron jobs (managed by install-cron.sh) ==="
  for fragment in "${FRAGMENT_FILES[@]}"; do
    fragment_name="$(basename "$fragment")"
    echo ""
    echo "# --- $fragment_name ---"
    # Strip comment-only lines and include active cron entries
    grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$fragment" || true
  done
} > "$COMBINED"

echo "Cron entries to install:"
cat "$COMBINED"
echo

# In CI/test environments, we don't actually install (no crontab binary or user)
if command -v crontab >/dev/null 2>&1; then
  crontab -u "$CRON_USER" "$COMBINED" 2>/dev/null && echo "✓ Crontab installed for $CRON_USER" || \
    echo "  Note: crontab install skipped (may need root or user $CRON_USER to exist)"
else
  echo "  Note: crontab binary not available — cron not installed (running in CI?)"
fi

rm -f "$COMBINED"

echo
echo "Included fragments:"
for fragment in "${FRAGMENT_FILES[@]}"; do
  echo "  - $(basename "$fragment")"
done
echo
echo "To verify: crontab -u $CRON_USER -l | grep walter"
echo "Logs: /var/log/walter-council/wiki-consolidation.log"
echo
echo "Refs: docs/specs/walter-council-v2.md — T-16"
