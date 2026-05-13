#!/usr/bin/env bats
# Tests that Makefile `audit-shell` target shellchecks the SAME list of
# files as the CI shellcheck job in .github/workflows/ci.yml.
#
# Codex R2 MEDIUM M5: the Makefile target claimed to "match ci.yml" but
# only covered 5 of 28 files. Running `make audit-shell` locally was thus
# materially weaker than CI and silently masked failures that would only
# surface in PR pipelines.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CI_FILE="$REPO_ROOT/.github/workflows/ci.yml"
  MAKEFILE="$REPO_ROOT/Makefile"
  [[ -f "$CI_FILE" ]] || skip "ci.yml not found"
  [[ -f "$MAKEFILE" ]] || skip "Makefile not found"
}

# Extract the file list from ci.yml's shellcheck command. The block is the
# multi-line continuation starting at `shellcheck -e ... \` and ending at
# the first non-continuation line.
_ci_files() {
  awk '
    /shellcheck -e SC/ { in_block=1; next }
    in_block {
      # Trim leading whitespace
      sub(/^[[:space:]]+/, "")
      # Strip trailing backslash + spaces
      sub(/[[:space:]]*\\$/, "")
      if ($0 == "") { exit }
      # If line does not look like a path token, end block
      if ($0 !~ /^[A-Za-z0-9_\/.-]+$/) { exit }
      print $0
    }
  ' "$CI_FILE" | sort -u
}

# Extract the file list from Makefile's audit-shell recipe.
_makefile_files() {
  awk '
    /^audit-shell:/ { in_recipe=1; next }
    in_recipe && /^[^[:space:]]/ { exit }
    in_recipe {
      # Strip leading tab+whitespace and trailing backslash
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]*\\$/, "")
      # Skip lines that are not file paths
      if ($0 == "") next
      if ($0 ~ /^shellcheck/) next
      if ($0 !~ /^[A-Za-z0-9_\/.-]+$/) next
      print $0
    }
  ' "$MAKEFILE" | sort -u
}

@test "M5: Makefile audit-shell file list equals ci.yml shellcheck file list" {
  ci_list="$(_ci_files)"
  mk_list="$(_makefile_files)"
  # Useful debug output if it fails
  if [[ "$ci_list" != "$mk_list" ]]; then
    echo "--- ci.yml ---" >&2
    echo "$ci_list" >&2
    echo "--- Makefile ---" >&2
    echo "$mk_list" >&2
    echo "--- only in ci.yml ---" >&2
    comm -23 <(echo "$ci_list") <(echo "$mk_list") >&2
    echo "--- only in Makefile ---" >&2
    comm -13 <(echo "$ci_list") <(echo "$mk_list") >&2
  fi
  [ "$ci_list" = "$mk_list" ]
}

@test "M5: Makefile audit-shell uses same shellcheck exclusion list as ci.yml" {
  # Both should pass the same explicit exclusion list. We grep each file
  # for the literal exclusion string.
  ci_excl='SC2155,SC1091,SC1083,SC2317,SC2329'
  grep -q "$ci_excl" "$CI_FILE"
  grep -q "$ci_excl" "$MAKEFILE"
}
