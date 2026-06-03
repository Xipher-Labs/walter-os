#!/usr/bin/env bats
# tests/cli/post-merge-check.bats
#
# Covers: docs/specs/post-merge-feedback-loop.md

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
  local path="$1" runs="$2" alerts="${3:-[]}" fix_attempts="${4:-0}" max_fix_attempts="${5:-2}"
  jq -nc \
    --arg pr "301" \
    --arg merge_sha "abc123def456" \
    --argjson runs "$runs" \
    --argjson alerts "$alerts" \
    --argjson fix_attempts "$fix_attempts" \
    --argjson max_fix_attempts "$max_fix_attempts" \
    '{
      pr: {number: $pr, merge_sha: $merge_sha},
      feature: {id: "AD-13", fix_attempts: $fix_attempts, max_fix_attempts: $max_fix_attempts},
      runs: $runs,
      alerts: $alerts
    }' > "$path"
}

@test "AC1: all post-merge runs passing returns healthy" {
  local fixture="$TMP_DIR/healthy.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"success"},{"workflowName":"readme-lint","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Decision: healthy"* ]]
  [[ "$output" == *"Next action: no-action"* ]]
}

@test "AC2: failed non-deploy run returns investigate" {
  local fixture="$TMP_DIR/investigate.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"failure"},{"workflowName":"readme-lint","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Decision: investigate"* ]]
  [[ "$output" == *"failed runs: ci"* ]]
}

@test "AC3: deploy failure recommends rollback" {
  local fixture="$TMP_DIR/deploy-failed.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"production-deploy","status":"completed","conclusion":"failure"},{"workflowName":"ci","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture"

  [ "$status" -eq 2 ]
  [[ "$output" == *"Decision: rollback-recommended"* ]]
  [[ "$output" == *"high-impact failed runs: production-deploy"* ]]
}

@test "AC3: critical telemetry alert recommends rollback" {
  local fixture="$TMP_DIR/critical-alert.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"success"}]' \
    '[{"source":"grafana","severity":"critical","summary":"error budget burn"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture" --json

  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.decision == "rollback-recommended"'
  echo "$output" | jq -e '.findings | index("critical/high alerts: error budget burn")'
}

@test "AC4: max fix attempts reached escalates to human" {
  local fixture="$TMP_DIR/max-attempts.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"failure"}]' \
    '[]' \
    2 \
    2

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture" --json

  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.decision == "human-escalation"'
  echo "$output" | jq -e '.next_action == "escalate-human"'
}

@test "AC5: pending runs are investigate, not rollback" {
  local fixture="$TMP_DIR/pending.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"in_progress","conclusion":null},{"workflowName":"readme-lint","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.decision == "investigate"'
  echo "$output" | jq -e '.next_action == "wait-or-investigate"'
}

@test "AC6: help documents post-merge-check" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"post-merge-check"* ]]
}
