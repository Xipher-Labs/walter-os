#!/usr/bin/env bats
# tests/install/tier-prompts-flag-coverage.bats
#
# Covers AC9, AC10 of docs/specs/agent-install-tier-completion.md:
#   AC9: every install.sh flag mentioned in setup/agent-install/tier-*.md
#        actually exists in install.sh's argparse.
#   AC10: every walter-os subcommand mentioned in the prompts actually
#        exists in bin/walter-os's case statement.
#
# This is the test that proves the drift Copilot flagged on closed
# PR #103 has been closed.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PROMPT_DIR="${REPO_ROOT}/setup/agent-install"
INSTALL_SH="${REPO_ROOT}/install.sh"
WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"

setup() {
  # Sanity: required files exist
  [ -d "$PROMPT_DIR" ] || skip "setup/agent-install directory missing"
  [ -f "$INSTALL_SH" ]
  [ -f "$WALTER_OS_BIN" ]
}

# -----------------------------------------------------------------------
# AC9: install.sh flags referenced in prompts exist in install.sh
# -----------------------------------------------------------------------
@test "AC9: every install.sh --<flag> in prompts exists in install.sh argparse" {
  # Extract flags. Pattern: install.sh --foo-bar
  prompt_flags=$(grep -hoE 'install\.sh\s+--[a-z][a-z0-9-]*' "$PROMPT_DIR"/tier-*.md 2>/dev/null \
    | sed -E 's/install\.sh[[:space:]]+--/--/' \
    | sort -u)

  if [ -z "$prompt_flags" ]; then
    skip "no install.sh flags found in prompts (vacuous)"
  fi

  missing=""
  while IFS= read -r flag; do
    # Look for the flag in install.sh case statement
    if ! grep -qE "^\s*${flag}\s*\)" "$INSTALL_SH"; then
      missing="${missing}\n  ✗ ${flag}"
    fi
  done <<< "$prompt_flags"

  if [ -n "$missing" ]; then
    printf "install.sh flags missing from argparse:%b\nflags found in prompts:\n%s\n" \
      "$missing" "$prompt_flags" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# AC10: walter-os subcommands referenced in prompts exist in bin/walter-os
# -----------------------------------------------------------------------
@test "AC10: every walter-os <subcmd> in prompts exists in bin/walter-os" {
  # Extract subcommands. Pattern: walter-os <subcmd-name> (excluding
  # walter-os --version, walter-os doctor --tier 3 second word, etc.).
  # We grep for the first word after `walter-os ` that isn't a flag.
  prompt_subs=$(grep -hoE 'walter-os\s+[a-z][a-z0-9-]*' "$PROMPT_DIR"/tier-*.md 2>/dev/null \
    | sed -E 's/walter-os[[:space:]]+//' \
    | sort -u)

  if [ -z "$prompt_subs" ]; then
    skip "no walter-os subcommands found in prompts (vacuous)"
  fi

  missing=""
  while IFS= read -r sub; do
    # Skip anything that looks like a flag (defensive)
    [[ "$sub" =~ ^- ]] && continue
    # Find the dispatch case in bin/walter-os. Lines look like:
    #   doctor)             cmd_doctor "$@" ;;
    if ! grep -qE "^\s*${sub}\s*\)" "$WALTER_OS_BIN"; then
      missing="${missing}\n  ✗ ${sub}"
    fi
  done <<< "$prompt_subs"

  if [ -n "$missing" ]; then
    printf "walter-os subcommands missing from dispatch:%b\nsubcommands found in prompts:\n%s\n" \
      "$missing" "$prompt_subs" >&2
    return 1
  fi
}
