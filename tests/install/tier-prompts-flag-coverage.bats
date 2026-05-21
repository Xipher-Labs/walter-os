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
  prompt_flags=$(grep -hoE 'install\.sh[[:space:]]+--[a-z][a-z0-9-]*' "$PROMPT_DIR"/tier-*.md 2>/dev/null \
    | sed -E 's/install\.sh[[:space:]]+--/--/' \
    | sort -u)

  if [ -z "$prompt_flags" ]; then
    skip "no install.sh flags found in prompts (vacuous)"
  fi

  missing=""
  while IFS= read -r flag; do
    # Look for the flag in install.sh case statement
    if ! grep -qE "^[[:space:]]*${flag}[[:space:]]*\)" "$INSTALL_SH"; then
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
# Implementation: grep ALL occurrences of `walter-os <word>` across the
# prompt files (no context filter — every match is a candidate), then
# subtract a curated allowlist of words that are common in English prose
# right after the literal "walter-os":
#   clone | repo | symlinked | config | directory | settings | path
# These are nouns/adjectives that happen to follow "walter-os" in
# contextual text like "from the walter-os clone:" or "walter-os repo
# purpose" — not subcommand invocations.
#
# This approach trades false-negative risk (a real misspelled subcommand
# that happens to match an allowlist word would slip through) for false-
# positive simplicity. The allowlist is small and reviewed in this file.
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
    if ! grep -qE "^[[:space:]]*${sub}[[:space:]]*\)" "$WALTER_OS_BIN"; then
      missing="${missing}\n  ✗ ${sub}"
    fi
  done <<< "$prompt_subs"

  if [ -n "$missing" ]; then
    printf "walter-os subcommands missing from dispatch:%b\nsubcommands found in prompts (after prose filter):\n%s\n" \
      "$missing" "$prompt_subs" >&2
    return 1
  fi
}


# -----------------------------------------------------------------------
# AC10b: nested walter-os <parent> <sub> commands also exist
#
# AC10 above only checks first-token dispatch. The prompts also use
# nested forms like `walter-os agents list` or `walter-os profile
# high-risk`, whose parents delegate to a sub-script. Drift in the
# nested layer slipped past AC10 historically (closed Copilot finding
# R1 #4 — `walter-os agents bootstrap-plane-labels` was undocumented).
#
# We validate the nested subcommands for the parents the prompts
# actually use. The map below is maintained in this test file; adding
# a new parent dispatcher to the prompts means extending this map.
# -----------------------------------------------------------------------
@test "AC10b: nested walter-os <parent> <sub> usages are valid" {
  # Parent → space-separated list of valid sub-commands.
  # Sourced from each dispatcher script's case statement.
  # Uses a flat function with case dispatch (not `declare -A`) for
  # portability across bash 3.2 (macOS default) and bash 4+ (Linux).
  valid_subs_for() {
    case "$1" in
      # Sourced from scripts/agents/main.sh — top-level cases at
      # lines 27 (list), 42 (run-once), 74 (pause), 81 (resume),
      # 91 (unlock), 117 (trust), 259 (status).
      agents)            echo "list run-once pause resume status trust unlock" ;;
      profile)           echo "default high-risk" ;;
      profile-bootstrap) echo "init status sync-shared" ;;
      *)                 echo "" ;;
    esac
  }

  parents="agents profile profile-bootstrap"
  missing=""
  for parent in $parents; do
    valid=$(valid_subs_for "$parent")
    [ -z "$valid" ] && continue
    while IFS= read -r used_sub; do
      [ -z "$used_sub" ] && continue
      case " $valid " in
        *" $used_sub "*) ;;
        *) missing="${missing}"$'\n'"  ✗ walter-os ${parent} ${used_sub}" ;;
      esac
    done < <(grep -hoE "walter-os ${parent} [a-z][a-z0-9-]*" "$PROMPT_DIR"/tier-*.md 2>/dev/null \
              | awk '{print $3}' | sort -u)
  done

  if [ -n "$missing" ]; then
    printf "Nested walter-os subcommands in prompts that don't exist:%s\n" "$missing" >&2
    return 1
  fi
}
