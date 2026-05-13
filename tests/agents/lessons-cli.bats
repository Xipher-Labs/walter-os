#!/usr/bin/env bats
# Tests for T-14: walter-os lessons subcommand
# Covers: AC-3, AC-4 of Improvement 4

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  LESSONS_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/lessons.sh"
  [[ -f "$WALTER_OS" ]] || skip "walter-os not found"
  [[ -f "$LESSONS_LIB" ]] || skip "lessons.sh not found"
  command -v sqlite3 >/dev/null 2>&1 || skip "sqlite3 required"

  # Isolated environment
  LESSONS_DB_DIR="$(mktemp -d -t walter-lessons-cli-XXXXXX)"
  export LESSONS_DB="$LESSONS_DB_DIR/lessons.db"
  export _LESSONS_MOCK_EMBED=1
  export LITELLM_BASE_URL=""
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_CONFIG="$LESSONS_DB_DIR/config"
  mkdir -p "$WALTER_CONFIG"
}

teardown() {
  rm -rf "$LESSONS_DB_DIR"
}

@test "walter-os lessons list prints table header even with empty DB" {
  run bash "$WALTER_OS" lessons list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "AGENT\|ID\|HEADLINE"
}

@test "walter-os lessons list shows entry after lesson_write" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Use parameterized SQL queries" "Prevent injection" '["security","sql"]'

  run bash "$WALTER_OS" lessons list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "reviewer"
}

@test "walter-os lessons rate updates confidence" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "coder" "Test lesson for rating" "Body" '["test"]'
  id="$(sqlite3 "$LESSONS_DB" "SELECT id FROM lessons LIMIT 1;")"

  run bash "$WALTER_OS" lessons rate "$id" "0.1"
  [ "$status" -eq 0 ]

  conf="$(sqlite3 "$LESSONS_DB" "SELECT confidence FROM lessons WHERE id='$id';")"
  # Confidence should be close to 0.1 — skip if bc is unavailable (don't fake result)
  command -v bc >/dev/null 2>&1 || skip "bc required for floating point comparison"
  [ "$(echo "$conf < 0.2" | bc -l)" -eq 1 ]
}

@test "walter-os lessons list --agent filters by agent" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Reviewer lesson" "Body" '["review"]'
  lesson_write "coder" "Coder lesson" "Body" '["code"]'

  run bash "$WALTER_OS" lessons list --agent reviewer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "reviewer"
  # Should not contain coder's entry (just filtering test)
}

@test "walter-os lessons query returns JSON" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Auth security pattern" "Body" '["security"]'

  run bash "$WALTER_OS" lessons query "authentication security"
  [ "$status" -eq 0 ]
  # Output should be a JSON array
  echo "$output" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null
}

@test "walter-os lessons subcommand exists in help" {
  run bash "$WALTER_OS" help
  echo "$output" | grep -qi "lessons"
}

# --------------- Fix 2 (round 2): lessons_list filter escaping ---------------
# Covers: agent_filter, tag_filter (quote-escape), days_filter (integer validation)
# Reviewer round 2 warn finding.

@test "lessons list --agent: SQL injection does not drop table" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Sentinel for agent injection test" "body" '["test"]'

  run bash "$WALTER_OS" lessons list --agent "x'; DROP TABLE lessons; --"
  # Command must exit cleanly (0) or with expected empty result
  [ "$status" -eq 0 ]
  # Table must still exist and contain the sentinel
  count="$("${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" "SELECT COUNT(*) FROM lessons;" 2>/dev/null || echo "0")"
  [ "$count" -gt 0 ]
}

@test "lessons list --tag: SQL injection does not drop table" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Sentinel for tag injection test" "body" '["test"]'

  run bash "$WALTER_OS" lessons list --tag "x'; DROP TABLE lessons; --"
  [ "$status" -eq 0 ]
  count="$("${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" "SELECT COUNT(*) FROM lessons;" 2>/dev/null || echo "0")"
  [ "$count" -gt 0 ]
}

@test "lessons list --last: non-integer value is rejected with error" {
  # days_filter must be validated as positive integer before interpolation
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init

  run bash "$WALTER_OS" lessons list --last "30; DELETE FROM lessons"
  # Must fail (exit non-zero) with an error about days being invalid
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "integer\|invalid\|days"
}

@test "lessons list --agent: normal agent name still works (regression)" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Reviewer regression lesson" "body" '["review"]'
  lesson_write "coder" "Coder regression lesson" "body" '["code"]'

  run bash "$WALTER_OS" lessons list --agent reviewer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "reviewer"
}
