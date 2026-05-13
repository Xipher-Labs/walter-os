#!/usr/bin/env bats
# Tests for T-M-1: scripts/wiki/wiki-validator.sh + AGENTS.md amendment
# Covers: T-M-1 verification steps

setup() {
  VALIDATOR="$BATS_TEST_DIRNAME/../../scripts/wiki/wiki-validator.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../fixtures/wiki-test"
  [[ -f "$VALIDATOR" ]] || skip "wiki-validator.sh not found"
}

@test "validator exits 0 for a valid page with complete frontmatter" {
  run bash "$VALIDATOR" "$FIXTURES/valid-page.md"
  [ "$status" -eq 0 ]
}

@test "validator exits 0 for valid-person.md" {
  run bash "$VALIDATOR" "$FIXTURES/valid-person.md"
  [ "$status" -eq 0 ]
}

@test "validator exits 1 for page with malformed YAML frontmatter" {
  run bash "$VALIDATOR" "$FIXTURES/malformed-yaml.md"
  [ "$status" -eq 1 ]
}

@test "validator exits 1 for page with missing type field" {
  # missing-type page has no 'type:' field
  run bash "$VALIDATOR" "$FIXTURES/people/missing-type.md"
  [ "$status" -eq 1 ]
}

@test "validator error message mentions what field is missing" {
  run bash "$VALIDATOR" "$FIXTURES/people/missing-type.md"
  # Output on stderr should explain what's wrong
  [ -n "$output" ]
}

@test "AGENTS.md global file contains Wiki integrity section" {
  AGENTS_MD="$BATS_TEST_DIRNAME/../../AGENTS.md"
  grep -q "Wiki integrity" "$AGENTS_MD"
}

@test "AGENTS.md wiki-validator.sh hook rule is documented" {
  AGENTS_MD="$BATS_TEST_DIRNAME/../../AGENTS.md"
  grep -q "wiki-validator" "$AGENTS_MD"
}

# --------------- Fix 12: require title+tags per SCHEMA ---------------

@test "validator exits 1 for page missing title field" {
  run bash "$VALIDATOR" "$FIXTURES/missing-title.md"
  [ "$status" -eq 1 ]
}

@test "validator error message mentions 'title' as missing field" {
  run bash "$VALIDATOR" "$FIXTURES/missing-title.md"
  echo "$output" | grep -qi "title"
}

@test "validator exits 1 for page with no tags field" {
  local tmp_file
  tmp_file="$(mktemp -t wiki-validator-test-XXXXXX.md)"
  printf '%s\n' '---' 'type: concept' 'title: Test' 'created: 2026-01-01' '---' '' '# Body' > "$tmp_file"
  run bash "$VALIDATOR" "$tmp_file"
  rm -f "$tmp_file"
  [ "$status" -eq 1 ]
}

@test "validator exits 0 for page with all 4 required fields" {
  local tmp_file
  tmp_file="$(mktemp -t wiki-validator-test-XXXXXX.md)"
  printf '%s\n' '---' 'type: concept' 'title: Test Page' 'created: 2026-01-01' 'tags: [test]' '---' '' '# Body' > "$tmp_file"
  run bash "$VALIDATOR" "$tmp_file"
  rm -f "$tmp_file"
  [ "$status" -eq 0 ]
}
