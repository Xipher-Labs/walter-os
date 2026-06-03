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
  mkdir -p "$HOME" "$WALTER_CONFIG" "$TMP_DIR/repo"
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

@test "AC5: --json emits structured signal arrays" {
  local fixture="$TMP_DIR/structured-signals.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci, docs","status":"completed","conclusion":"failure"},{"workflowName":"production-deploy","status":"completed","conclusion":"failure"},{"workflowName":"readme-lint","status":"in_progress","conclusion":null}]' \
    '[{"source":"grafana","severity":"high","summary":"api, elevated errors"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture" --json

  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.signals.pending_runs == ["readme-lint"]'
  echo "$output" | jq -e '.signals.failed_runs == ["ci, docs", "production-deploy"]'
  echo "$output" | jq -e '.signals.high_impact_failed_runs == ["production-deploy"]'
  echo "$output" | jq -e '.signals.critical_alerts == ["api, elevated errors"]'
}

@test "AD-13: opt-in feature-state recording appends post-merge event" {
  command -v ruby >/dev/null 2>&1 || skip "ruby required for feature-state YAML tests"
  local fixture="$TMP_DIR/record-ledger.json"
  local state_file="$TMP_DIR/repo/.walter/features/AD-13/state.yaml"
  bash "$WALTER_OS_BIN" feature-state init AD-13 \
    --repo "$TMP_DIR/repo" \
    --title "Post-merge feedback loop" \
    --issue 238 \
    --idea "Record post-merge health decisions" >/dev/null
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"failure"}]'

  run bash "$WALTER_OS_BIN" post-merge-check \
    --fixture "$fixture" \
    --json \
    --record-feature-state AD-13 \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.decision == "investigate"'
  ruby -ryaml -e '
    state = YAML.safe_load(File.read(ARGV[0]))
    event = state.fetch("post_merge").last
    abort "stage" unless state["stage"] == "post-merge-investigate"
    abort "decision" unless event["decision"] == "investigate"
    abort "next_action" unless event["next_action"] == "open-fix-pr-candidate"
    abort "merge_sha" unless event["merge_sha"] == "abc123def456"
    abort "source" unless event["source"] == "post-merge-check"
  ' "$state_file"
}

@test "AD-13: feature-state recording failures use runtime exit code" {
  command -v ruby >/dev/null 2>&1 || skip "ruby required for feature-state YAML tests"
  local fixture="$TMP_DIR/missing-ledger.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check \
    --fixture "$fixture" \
    --record-feature-state AD-13 \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 4 ]
  [[ "$output" == *"unable to record feature state"* ]]
  [[ "$output" == *"feature-state exit 1"* ]]
  [[ "$output" == *".walter/features/AD-13/state.yaml"* ]]
}

@test "AD-13: invalid feature id remains a usage error" {
  local fixture="$TMP_DIR/invalid-feature-id.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check \
    --fixture "$fixture" \
    --record-feature-state ../escape \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 64 ]
  [[ "$output" == *"invalid feature id"* ]]
}

@test "AD-13: --repo without feature-state recording is a usage error" {
  local fixture="$TMP_DIR/repo-without-recording.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci","status":"completed","conclusion":"success"}]'

  run bash "$WALTER_OS_BIN" post-merge-check \
    --fixture "$fixture" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--repo requires --record-feature-state"* ]]
}

@test "regression: comma-bearing run and alert names do not inflate counts" {
  local fixture="$TMP_DIR/comma-names.json"
  write_fixture \
    "$fixture" \
    '[{"workflowName":"ci, docs","status":"completed","conclusion":"failure"},{"workflowName":"release, production","status":"completed","conclusion":"failure"}]' \
    '[{"source":"grafana","severity":"critical","summary":"api, elevated errors"}]'

  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$fixture" --json

  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.counts.failed_runs == 2'
  echo "$output" | jq -e '.counts.high_impact_failed_runs == 1'
  echo "$output" | jq -e '.counts.critical_alerts == 1'
  echo "$output" | jq -e '.findings | index("failed runs: ci, docs, release, production")'
}

@test "regression: gh runtime failures use a non-decision exit code" {
  local fake_bin="$TMP_DIR/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "simulated gh outage" >&2
exit 42
EOF
  chmod +x "$fake_bin/gh"

  cd "$REPO_ROOT"
  run env PATH="$fake_bin:$PATH" bash "$WALTER_OS_BIN" post-merge-check --commit abc123

  [ "$status" -eq 4 ]
  [[ "$output" == *"unable to inspect GitHub Actions runs"* ]]
}

@test "regression: unreadable fixture is a usage error" {
  run bash "$WALTER_OS_BIN" post-merge-check --fixture "$TMP_DIR/missing.json"

  [ "$status" -eq 64 ]
  [[ "$output" == *"fixture is not readable"* ]]
}

@test "AC6: help documents post-merge-check" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"post-merge-check"* ]]
  [[ "$output" == *"record-feature-state"* ]]
}
