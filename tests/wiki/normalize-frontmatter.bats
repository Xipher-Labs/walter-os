#!/usr/bin/env bats
# Tests for T-M-0: scripts/wiki/normalize-frontmatter.sh
# Covers: T-M-0 AC (normalization, report, idempotency)

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/wiki/normalize-frontmatter.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../fixtures/wiki-test"
  [[ -f "$SCRIPT" ]] || skip "normalize-frontmatter.sh not found"

  # Work on a temporary copy so we don't modify the fixtures
  WORK_DIR="$(mktemp -d -t wiki-normalize-XXXXXX)"
  cp -r "$FIXTURES"/. "$WORK_DIR"/

  REPORT_FILE="$(mktemp -t wiki-normalize-report-XXXXXX.txt)"
  export WIKI_NORMALIZE_REPORT="$REPORT_FILE"
}

teardown() {
  rm -rf "$WORK_DIR" "$REPORT_FILE"
}

@test "valid pages are not modified" {
  original_valid="$(cat "$WORK_DIR/valid-page.md")"
  original_person="$(cat "$WORK_DIR/valid-person.md")"

  run bash "$SCRIPT" "$WORK_DIR"

  [ "$(cat "$WORK_DIR/valid-page.md")" = "$original_valid" ]
  [ "$(cat "$WORK_DIR/valid-person.md")" = "$original_person" ]
}

@test "missing type in people/ is auto-fixed to person" {
  run bash "$SCRIPT" "$WORK_DIR"

  # The file under people/ should have type: person added
  grep -q "type: person" "$WORK_DIR/people/missing-type.md"
}

@test "missing title page appears in report" {
  run bash "$SCRIPT" "$WORK_DIR"

  [ -f "$REPORT_FILE" ]
  grep -q "missing-title" "$REPORT_FILE"
}

@test "malformed YAML page appears in report as needs manual fix" {
  run bash "$SCRIPT" "$WORK_DIR"

  [ -f "$REPORT_FILE" ]
  grep -q "malformed-yaml" "$REPORT_FILE"
}

@test "script is idempotent — running twice produces no changes on second run" {
  bash "$SCRIPT" "$WORK_DIR"
  # Capture state after first run
  snapshot_after_first="$(find "$WORK_DIR" -name '*.md' -exec sha256sum {} \; | sort)"

  bash "$SCRIPT" "$WORK_DIR"
  snapshot_after_second="$(find "$WORK_DIR" -name '*.md' -exec sha256sum {} \; | sort)"

  [ "$snapshot_after_first" = "$snapshot_after_second" ]
}

@test "script exits 0 even when report has findings" {
  run bash "$SCRIPT" "$WORK_DIR"
  [ "$status" -eq 0 ]
}

@test "M11: file missing tags field is reported or auto-fixed" {
  # wiki-validator.sh requires tags but normalize-frontmatter.sh did not
  # handle it. After this fix, a file without tags must either get
  # tags: [] added auto or appear in the report as MISSING_TAGS.
  local no_tags_file="$WORK_DIR/missing-tags.md"
  cat > "$no_tags_file" <<'EOF'
---
type: concept
title: No Tags Page
created: 2026-05-01
---

# No Tags Page

A page that has all required fields except tags.
EOF

  run bash "$SCRIPT" "$WORK_DIR"
  [ "$status" -eq 0 ]

  # Either tags was added to the file OR it appears in the report
  local has_tags_in_file=0
  local has_tags_in_report=0
  grep -q "^tags" "$no_tags_file" 2>/dev/null && has_tags_in_file=1
  grep -q "missing-tags\|MISSING_TAGS" "$REPORT_FILE" 2>/dev/null && has_tags_in_report=1

  if [[ "$has_tags_in_file" -eq 0 && "$has_tags_in_report" -eq 0 ]]; then
    echo "FAIL: file without tags was neither auto-fixed nor reported" >&3
    false
  fi
}
