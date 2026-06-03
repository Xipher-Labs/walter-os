#!/usr/bin/env bats
# tests/cli/feature-state.bats
#
# Covers: issue #227 / AD-2 — persistent feature-state ledger.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  command -v ruby >/dev/null 2>&1 || skip "ruby required for feature-state YAML tests"

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

ledger_path() {
  printf '%s/.walter/features/%s/state.yaml\n' "$TMP_DIR/repo" "$1"
}

yaml_query() {
  local file="$1" expr="$2"
  ruby -ryaml -e '
    state = YAML.safe_load(File.read(ARGV[0]))
    value = state.dig(*ARGV[1].split("."))
    puts value.is_a?(Array) ? value.length : value
  ' "$file" "$expr"
}

@test "init creates a parseable feature-state ledger with required sections" {
  run bash "$WALTER_OS_BIN" feature-state init AD-2 \
    --repo "$TMP_DIR/repo" \
    --title "Persistent feature-state ledger" \
    --issue 227 \
    --idea "Survive conversation context loss" \
    --spec docs/specs/feature-state-ledger.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-state: initialized"* ]]

  local state_file
  state_file="$(ledger_path AD-2)"
  [[ -f "$state_file" ]]
  [[ "$(yaml_query "$state_file" id)" == "AD-2" ]]
  [[ "$(yaml_query "$state_file" title)" == "Persistent feature-state ledger" ]]
  [[ "$(yaml_query "$state_file" issue)" == "227" ]]
  [[ "$(yaml_query "$state_file" idea)" == "Survive conversation context loss" ]]
  [[ "$(yaml_query "$state_file" spec.path)" == "docs/specs/feature-state-ledger.md" ]]
  [[ "$(yaml_query "$state_file" acceptance_criteria)" == "0" ]]
  [[ "$(yaml_query "$state_file" tasks)" == "0" ]]
  [[ "$(yaml_query "$state_file" decisions)" == "0" ]]
  [[ "$(yaml_query "$state_file" risks)" == "0" ]]
  [[ "$(yaml_query "$state_file" prs)" == "0" ]]
  [[ "$(yaml_query "$state_file" post_merge)" == "0" ]]
}

@test "validate accepts a generated ledger" {
  bash "$WALTER_OS_BIN" feature-state init AD-2 --repo "$TMP_DIR/repo" >/dev/null

  run bash "$WALTER_OS_BIN" feature-state validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-state: valid"* ]]
  [[ "$output" == *".walter/features/AD-2/state.yaml"* ]]
}

@test "init refuses to overwrite an existing ledger unless forced" {
  bash "$WALTER_OS_BIN" feature-state init AD-2 --repo "$TMP_DIR/repo" >/dev/null

  run bash "$WALTER_OS_BIN" feature-state init AD-2 --repo "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "init rejects path traversal feature ids" {
  run bash "$WALTER_OS_BIN" feature-state init ../escape --repo "$TMP_DIR/repo"

  [ "$status" -eq 64 ]
  [[ "$output" == *"invalid feature id"* ]]
  [[ ! -e "$TMP_DIR/repo/.walter/features/../escape/state.yaml" ]]
}

@test "record-post-merge appends a bounded event for AD-13 consumers" {
  bash "$WALTER_OS_BIN" feature-state init AD-13 --repo "$TMP_DIR/repo" >/dev/null

  run bash "$WALTER_OS_BIN" feature-state record-post-merge AD-13 \
    --repo "$TMP_DIR/repo" \
    --decision investigate \
    --next-action open-fix-pr-candidate \
    --commit abc123def456 \
    --source post-merge-check

  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-state: recorded post-merge event"* ]]

  local state_file
  state_file="$(ledger_path AD-13)"
  [[ "$(yaml_query "$state_file" stage)" == "post-merge-investigate" ]]
  ruby -ryaml -e '
    state = YAML.safe_load(File.read(ARGV[0]))
    event = state.fetch("post_merge").last
    abort "missing event" unless event
    abort "decision" unless event["decision"] == "investigate"
    abort "next_action" unless event["next_action"] == "open-fix-pr-candidate"
    abort "merge_sha" unless event["merge_sha"] == "abc123def456"
    abort "source" unless event["source"] == "post-merge-check"
  ' "$state_file"
}

@test "validate rejects policy-like hard-limit override keys" {
  bash "$WALTER_OS_BIN" feature-state init AD-2 --repo "$TMP_DIR/repo" >/dev/null
  printf '\nhard_limit_overrides:\n  approval_gate: relaxed\n' >> "$(ledger_path AD-2)"

  run bash "$WALTER_OS_BIN" feature-state validate "$(ledger_path AD-2)"

  [ "$status" -eq 1 ]
  [[ "$output" == *"state file cannot declare policy key: hard_limit_overrides"* ]]
}

@test "validate rejects nested policy-like hard-limit override keys" {
  bash "$WALTER_OS_BIN" feature-state init AD-2 --repo "$TMP_DIR/repo" >/dev/null
  ruby -ryaml -e '
    path = ARGV[0]
    state = YAML.safe_load(File.read(path))
    state["brief"]["auto_merge"] = true
    File.write(path, state.to_yaml)
  ' "$(ledger_path AD-2)"

  run bash "$WALTER_OS_BIN" feature-state validate "$(ledger_path AD-2)"

  [ "$status" -eq 1 ]
  [[ "$output" == *"state file cannot declare policy key: brief.auto_merge"* ]]
}

@test "validate rejects missing required fields" {
  bash "$WALTER_OS_BIN" feature-state init AD-2 --repo "$TMP_DIR/repo" >/dev/null
  ruby -ryaml -e '
    path = ARGV[0]
    state = YAML.safe_load(File.read(path))
    state.delete("tasks")
    File.write(path, state.to_yaml)
  ' "$(ledger_path AD-2)"

  run bash "$WALTER_OS_BIN" feature-state validate "$(ledger_path AD-2)"

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field(s): tasks"* ]]
}

@test "record-post-merge refuses to mutate invalid ledgers" {
  bash "$WALTER_OS_BIN" feature-state init AD-13 --repo "$TMP_DIR/repo" >/dev/null
  printf '\nhard_limit_overrides:\n  approval_gate: relaxed\n' >> "$(ledger_path AD-13)"

  run bash "$WALTER_OS_BIN" feature-state record-post-merge AD-13 \
    --repo "$TMP_DIR/repo" \
    --decision investigate \
    --next-action open-fix-pr-candidate \
    --commit abc123def456

  [ "$status" -eq 1 ]
  [[ "$output" == *"state file cannot declare policy key: hard_limit_overrides"* ]]
  [[ "$(yaml_query "$(ledger_path AD-13)" post_merge)" == "0" ]]
}

@test "help documents feature-state" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-state"* ]]
}
