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
#
# A subcommand reference is a line where `walter-os <word>` appears in
# a way that looks like a command invocation, not prose. We require
# either a leading `$ ` prompt indicator OR the line to be indented
# (typical for code blocks inside the prompt's fenced block).
#
# Words known to appear in PROSE (not commands) are excluded:
#   clone | repo | symlinked | config | directory | settings | path
# These are nouns/adjectives that happen to follow "walter-os" in
# contextual text like "from the walter-os clone:" or "walter-os repo
# purpose".
# -----------------------------------------------------------------------
@test "AC10: every walter-os <subcmd> in prompts exists in bin/walter-os" {
  # Capture lines that contain `walter-os <word>` in a code-block-like
  # context. Approach: take every line, extract candidate subcommands,
  # then filter out the prose-only words.
  prose_words="clone repo symlinked config directory settings path"

  prompt_subs=$(grep -hoE 'walter-os[[:space:]]+[a-z][a-z0-9-]*' "$PROMPT_DIR"/tier-*.md 2>/dev/null \
    | sed -E 's/walter-os[[:space:]]+//' \
    | sort -u)

  if [ -z "$prompt_subs" ]; then
    skip "no walter-os subcommands found in prompts (vacuous)"
  fi

  missing=""
  while IFS= read -r sub; do
    # Skip flag-like and known-prose words
    [[ "$sub" =~ ^- ]] && continue
    case " $prose_words " in
      *" $sub "*) continue ;;
    esac
    # Find the dispatch case in bin/walter-os. Lines look like:
    #   doctor)             cmd_doctor "$@" ;;
    if ! grep -qE "^\s*${sub}\s*\)" "$WALTER_OS_BIN"; then
      missing="${missing}\n  ✗ ${sub}"
    fi
  done <<< "$prompt_subs"

  if [ -n "$missing" ]; then
    printf "walter-os subcommands missing from dispatch:%b\nsubcommands found in prompts (after prose filter):\n%s\n" \
      "$missing" "$prompt_subs" >&2
    return 1
  fi
}
