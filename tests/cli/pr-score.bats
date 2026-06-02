#!/usr/bin/env bats
# tests/cli/pr-score.bats
#
# Covers: docs/specs/pr-score.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_DIR="$(mktemp -d)"
  export HOME="$TMP_DIR/home"
  export WALTER_CONFIG="$TMP_DIR/config"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$HOME" "$WALTER_CONFIG"
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || exit
  case "$TMP_DIR" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_DIR" ;;
  esac
  true
}

write_fixture() {
  local path="$1" title="$2" checks="$3" files="$4" body="${5:-}"
  if [[ -z "$body" ]]; then
    body=$'## Verification\n- bats tests/cli/pr-score.bats\n\nCloses #236'
  fi
  jq -nc \
    --arg title "$title" \
    --arg body "$body" \
    --argjson checks "$checks" \
    --argjson files "$files" \
    '{
      number: 236,
      title: $title,
      body: $body,
      mergeable: "MERGEABLE",
      reviewRequests: [],
      comments: [],
      latestReviews: [
        {
          author: {login: "copilot-pull-request-reviewer"},
          body: "Copilot reviewed 3 out of 3 changed files and generated no new comments."
        }
      ],
      reviewThreads: [{isResolved: true}],
      statusCheckRollup: $checks,
      files: $files
    }' > "$path"
}

@test "AC1: clean low-risk PR is policy-auto-merge eligible" {
  local fixture="$TMP_DIR/clean.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"shellcheck","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"bats","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"},{"path":"tests/cli/pr-score.bats"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Walter Score:"* ]]
  [[ "$output" == *"Decision: policy-auto-merge"* ]]
}

@test "AC2: failing checks block the PR" {
  local fixture="$TMP_DIR/failing.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"bats","status":"COMPLETED","conclusion":"FAILURE"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Decision: block"* ]]
  [[ "$output" == *"failing checks"* ]]
}

@test "AC2: invalid title blocks the PR" {
  local fixture="$TMP_DIR/title.json"
  write_fixture \
    "$fixture" \
    "add PR readiness score" \
    '[{"name":"bats","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Decision: block"* ]]
  [[ "$output" == *"title does not match"* ]]
}

@test "AC3: workflow changes force human review" {
  local fixture="$TMP_DIR/workflow.json"
  write_fixture \
    "$fixture" \
    "[CHORE] -OPERATIONS- migrate workflow action pins" \
    '[{"name":"bats","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":".github/workflows/ci.yml"},{"path":"tests/install/workflow-pins.bats"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Decision: human-review"* ]]
  [[ "$output" == *"sensitive path"* ]]
}

@test "AC4: --json emits machine-readable score and decision" {
  local fixture="$TMP_DIR/clean.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"shellcheck","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score >= 90 and .decision == "policy-auto-merge"'
  echo "$output" | jq -e '.components.checks.points == 30'
  echo "$output" | jq -e '.findings | type == "array"'
}

@test "AC5: help documents pr-score" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-score"* ]]
}
