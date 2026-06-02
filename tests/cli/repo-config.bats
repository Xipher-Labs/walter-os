#!/usr/bin/env bats
# tests/cli/repo-config.bats
#
# Covers: issue #230 / AD-5 — walter-repo-config.yaml per-repo policy.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  command -v yq >/dev/null 2>&1 || skip "mikefarah/yq required for repo-config validation tests"
  yq --version 2>&1 | grep -qi 'mikefarah' || skip "mikefarah/yq required for repo-config validation tests"
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

write_valid_config() {
  cat > "$TMP_DIR/repo/walter-repo-config.yaml" <<'YAML'
autonomy_mode: guided
profile: balanced
capability_tier_ceiling: 1
auto_merge:
  enabled: false
  allowed_branches:
    - "walter/*"
    - "demo"
  forbidden_branches:
    - main
    - production
  require_green_ci: true
  min_walter_score: 90
  max_risk: low
verification: risk_based
preview_deploy: false
human_approval_required_for:
  - auth
  - payments
  - secrets
  - prod_infra
  - db_migrations
  - destructive_ops
YAML
}

@test "absence of walter-repo-config.yaml applies safest defaults" {
  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"safest defaults apply"* ]]
}

@test "explicit missing target fails instead of applying defaults" {
  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/missing-repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"target not found"* ]]
}

@test "valid walter-repo-config.yaml passes schema validation" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-config: valid"* ]]
}

@test "safe literal branch names are allowed even when they prefix protected names" {
  write_valid_config
  sed -i.bak 's/"demo"/"m"/' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-config: valid"* ]]
}

@test "safe branch globs with literal prefixes are allowed" {
  write_valid_config
  sed -i.bak 's|"demo"|"feature/*"|' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-config: valid"* ]]
}

@test "invalid autonomy_mode fails closed" {
  write_valid_config
  sed -i.bak 's/autonomy_mode: guided/autonomy_mode: sleepy/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid autonomy_mode"* ]]
}

@test "unknown top-level keys warn but do not fail" {
  write_valid_config
  printf '\nexperimental_knob: true\n' >> "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN repo-config: unknown key: experimental_knob"* ]]
  [[ "$output" == *"repo-config: valid"* ]]
}

@test "human approval list cannot remove the hard-limit floor" {
  write_valid_config
  sed -i.bak '/  - auth/d' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing hard-floor approval: auth"* ]]
}

@test "auto_merge.allowed_branches cannot include protected branches" {
  write_valid_config
  sed -i.bak 's/"demo"/main/' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"auto_merge.allowed_branches includes protected branch: main"* ]]
}

@test "auto_merge.allowed_branches cannot include patterns matching protected branches" {
  write_valid_config
  sed -i.bak 's|"demo"|"m*"|' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"auto_merge.allowed_branches pattern matches protected branch: m* -> main"* ]]
}

@test "auto_merge.allowed_branches cannot include release namespace globs" {
  write_valid_config
  sed -i.bak 's|"demo"|release/[!v]*|' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"auto_merge.allowed_branches includes protected branch namespace: release/[!v]*"* ]]
}

@test "auto_merge.allowed_branches globs require safe literal prefixes" {
  write_valid_config
  sed -i.bak 's/"demo"/"*v2*"/' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"auto_merge.allowed_branches glob has no safe literal prefix: *v2*"* ]]
}

@test "repo-config defaults print safe effective defaults" {
  run "$WALTER_OS_BIN" repo-config defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"autonomy_mode: guided"* ]]
  [[ "$output" == *"capability_tier_ceiling: 1"* ]]
  [[ "$output" == *"enabled: false"* ]]
  [[ "$output" == *"verification: risk_based"* ]]
}

@test "repo-config subcommand preserves config-sourced WALTER_OS_HOME" {
  printf 'WALTER_OS_HOME=%q\n' "$REPO_ROOT" > "$WALTER_CONFIG/env"
  unset WALTER_OS_HOME

  run "$WALTER_OS_BIN" repo-config defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"autonomy_mode: guided"* ]]
  export WALTER_OS_HOME="$REPO_ROOT"
}

@test "repository walter-repo-config.yaml validates" {
  run "$WALTER_OS_BIN" repo-config validate "$REPO_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-config: valid"* ]]
}

@test "doctor --repo-config validates git root policy from subdirectories" {
  write_valid_config
  sed -i.bak 's/autonomy_mode: guided/autonomy_mode: sleepy/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"
  git -C "$TMP_DIR/repo" init -q
  mkdir -p "$TMP_DIR/repo/nested/path"

  run bash -c "cd '$TMP_DIR/repo/nested/path' && '$WALTER_OS_BIN' doctor --repo-config"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid autonomy_mode"* ]]
}

@test "doctor --repo-config validates the current repository policy" {
  write_valid_config

  run bash -c "cd '$TMP_DIR/repo' && '$WALTER_OS_BIN' doctor --repo-config"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Walter-OS doctor — repo config"* ]]
  [[ "$output" == *"repo-config: valid"* ]]
}
