#!/usr/bin/env bats
# tests/oss/pr-title-format.bats
# W-15: validate PR/issue title convention regex against valid/invalid fixtures.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  VALIDATOR="$REPO_ROOT/hooks/pr-title-validator.sh"
}

@test "validator script exists and is executable" {
  [[ -x "$VALIDATOR" ]]
}

# ── Valid titles ─────────────────────────────────────────────────────────

@test "accepts FEAT BUSINESS" {
  run "$VALIDATOR" "[FEAT] -BUSINESS- pricing experiment skill"
  [ "$status" -eq 0 ]
}

@test "accepts FIX SECURITY" {
  run "$VALIDATOR" "[FIX] -SECURITY- enforce CCR_APIKEY on sub-router routes"
  [ "$status" -eq 0 ]
}

@test "accepts DOCS COMPLIANCE" {
  run "$VALIDATOR" "[DOCS] -COMPLIANCE- expand GDPR self-assessment template"
  [ "$status" -eq 0 ]
}

@test "accepts CHORE OPERATIONS" {
  run "$VALIDATOR" "[CHORE] -OPERATIONS- bump hcloud-cli to v1.45"
  [ "$status" -eq 0 ]
}

@test "accepts TEST TECHNICAL" {
  run "$VALIDATOR" "[TEST] -TECHNICAL- add bats coverage for new-project subcommand"
  [ "$status" -eq 0 ]
}

@test "accepts each of 8 categories" {
  for cat in SECURITY BUSINESS COMPLIANCE OPERATIONS TECHNICAL CUSTOMER CONTENT LEARNING; do
    run "$VALIDATOR" "[FEAT] -$cat- generic title for category"
    [ "$status" -eq 0 ]
  done
}

# ── Invalid titles ───────────────────────────────────────────────────────

@test "rejects lowercase type" {
  run "$VALIDATOR" "[feat] -BUSINESS- thing"
  [ "$status" -eq 1 ]
}

@test "rejects lowercase category" {
  run "$VALIDATOR" "[FEAT] -business- thing"
  [ "$status" -eq 1 ]
}

@test "rejects conventional-commit format" {
  run "$VALIDATOR" "feat: add new thing"
  [ "$status" -eq 1 ]
}

@test "rejects missing category" {
  run "$VALIDATOR" "[FEAT] add new thing"
  [ "$status" -eq 1 ]
}

@test "rejects missing type" {
  run "$VALIDATOR" "-BUSINESS- add new thing"
  [ "$status" -eq 1 ]
}

@test "rejects unknown type" {
  run "$VALIDATOR" "[REFACTOR] -TECHNICAL- restructure"
  [ "$status" -eq 1 ]
}

@test "rejects unknown category" {
  run "$VALIDATOR" "[FEAT] -DEVOPS- ship something"
  [ "$status" -eq 1 ]
}

@test "rejects empty title body" {
  run "$VALIDATOR" "[FEAT] -BUSINESS- "
  [ "$status" -eq 1 ]
}

@test "rejects missing argument" {
  run "$VALIDATOR"
  [ "$status" -eq 2 ]
}
@test "rejects title body >60 chars" {
  # 61 chars body should fail
  run "$VALIDATOR" "[FEAT] -BUSINESS- this is a very long title body that exceeds the sixty character limit"
  [ "$status" -eq 1 ]
}

@test "rejects title ending with period" {
  run "$VALIDATOR" "[FEAT] -BUSINESS- title body ends with a period."
  [ "$status" -eq 1 ]
}

@test "accepts title body exactly 60 chars" {
  # 60-char body (no period)
  run "$VALIDATOR" "[FEAT] -BUSINESS- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  [ "$status" -eq 0 ]
}
