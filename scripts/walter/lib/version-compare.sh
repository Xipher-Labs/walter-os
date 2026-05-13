#!/usr/bin/env bash
# scripts/walter/lib/version-compare.sh
#
# Shared version-comparison utility. Sourced by:
#   - bin/walter-os (update-check in cmd_version)
#   - tests/cli/version.bats (unit tests for _version_is_newer)
#
# Usage:
#   source scripts/walter/lib/version-compare.sh
#   _version_is_newer "0.2.5" "0.2.0" && echo "newer"

# _version_is_newer <candidate> <current>
#
# Returns 0 (true) if <candidate> is strictly newer than <current>.
# Returns 1 (false) if equal or older.
#
# Pre-release semantics (intentionally simpler than full SemVer):
#   - Any release (no suffix) > any pre-release (has suffix): 0.2.0 > 0.2.0-alpha
#   - Two pre-releases with the same numeric core compare equal (returns 1).
#     e.g. 0.2.0-beta vs 0.2.0-alpha → returns 1 (no upgrade signalled).
#   - This is sufficient for Walter-OS: stable releases are the normal update
#     path; pre-release vs pre-release ordering is not implemented by design.
#
# Handles:
#   - Standard semver core (MAJOR.MINOR.PATCH) via sort -V
#   - Pre-release suffixes per the rules above
_version_is_newer() {
  local candidate="$1" current="$2"
  [[ "$candidate" == "$current" ]] && return 1
  local cand_core="${candidate%%-*}"
  local curr_core="${current%%-*}"
  if [[ "$cand_core" != "$curr_core" ]]; then
    local newer
    newer="$(printf '%s\n%s\n' "$cand_core" "$curr_core" | sort -V | tail -1)"
    [[ "$newer" == "$cand_core" ]]
  else
    # Same numeric core: release > pre-release (no suffix > has suffix)
    [[ "$candidate" == "$cand_core" && "$current" != "$curr_core" ]]
  fi
}
