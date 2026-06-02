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

@test "AC2: unknown title category blocks the PR" {
  local fixture="$TMP_DIR/title-category.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -PRODUCT- add PR readiness score" \
    '[{"name":"bats","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Decision: block"* ]]
  [[ "$output" == *"title does not match"* ]]
}

@test "AC2: completed check without conclusion is pending" {
  local fixture="$TMP_DIR/check-no-conclusion.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"bats","status":"COMPLETED","conclusion":null}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "human-review"'
  echo "$output" | jq -e '.findings | index("pending checks: 1")'
  echo "$output" | jq -e '.findings | index("failing checks: 1") | not'
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

@test "AC3: outdated unresolved review threads are ignored" {
  local fixture="$TMP_DIR/outdated-thread.json"
  local updated="$TMP_DIR/outdated-thread-updated.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"bats","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'
  jq '.reviewThreads = [{isResolved: false, isOutdated: true}] | .reviewThreadsTotalCount = 1' \
    "$fixture" > "$updated"
  mv "$updated" "$fixture"

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "policy-auto-merge"'
  echo "$output" | jq -e '.findings | index("unresolved review threads: 1") | not'
}

@test "AC3: incomplete review thread page forces human review" {
  local fixture="$TMP_DIR/thread-page.json"
  local updated="$TMP_DIR/thread-page-updated.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"bats","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'
  jq '.reviewThreads = [{isResolved: true, isOutdated: false}] | .reviewThreadsTotalCount = 101' \
    "$fixture" > "$updated"
  mv "$updated" "$fixture"

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "human-review"'
  echo "$output" | jq -e '.findings | index("review thread page incomplete: fetched 1 of 101")'
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

@test "AC4: issue references may use a colon after keyword" {
  local fixture="$TMP_DIR/colon-ref.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"shellcheck","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]' \
    $'## Verification\n- bats tests/cli/pr-score.bats\n\nCloses: #236'

  run bash "$WALTER_OS_BIN" pr-score --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.components.issue_links.points == 10'
  echo "$output" | jq -e '.findings | index("missing issue reference in PR body") | not'
}

@test "AC4: --fixture cannot be combined with a PR reference" {
  local fixture="$TMP_DIR/clean.json"
  write_fixture \
    "$fixture" \
    "[FEAT] -TECHNICAL- add PR readiness score" \
    '[{"name":"shellcheck","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    '[{"path":"scripts/walter/subcommands/pr-score.sh"}]'

  run bash "$WALTER_OS_BIN" pr-score 289 --fixture "$fixture"

  [ "$status" -eq 2 ]
  [[ "$output" == *"PR reference cannot be combined with --fixture"* ]]
}

@test "AC5: help documents pr-score" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-score"* ]]
}
