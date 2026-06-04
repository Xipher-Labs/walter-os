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
  [[ "$output" == *"effective autonomy_mode: guided"* ]]
  [[ "$output" == *"policy axis, not install tier"* ]]
  [[ "$output" == *"hard-limit floor: non-overridable"* ]]
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

@test "mode contract helper normalizes unknown modes to guided" {
  run bash -c "source '$REPO_ROOT/scripts/walter/lib/repo-config.sh'; walter_repo_config_print_mode_contract sleepy"

  [ "$status" -eq 0 ]
  [[ "$output" == *"effective autonomy_mode: guided"* ]]
  [[ "$output" == *"unknown mode requested; safest guided semantics apply"* ]]
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

@test "full autonomy still cannot remove the hard-limit floor" {
  write_valid_config
  sed -i.bak 's/autonomy_mode: guided/autonomy_mode: full/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"
  sed -i.bak '/  - secrets/d' "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing hard-floor approval: secrets"* ]]
}

@test "full autonomy cannot omit the hard-limit approval list" {
  write_valid_config
  sed -i.bak 's/autonomy_mode: guided/autonomy_mode: full/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"
  sed -i.bak '/^human_approval_required_for:/,$d' \
    "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing hard-floor approval list: human_approval_required_for"* ]]
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

@test "repo-config defaults hackathon prints bounded full-autonomy profile" {
  run "$WALTER_OS_BIN" repo-config defaults hackathon

  [ "$status" -eq 0 ]
  [[ "$output" == *"autonomy_mode: full"* ]]
  [[ "$output" == *"profile: hackathon"* ]]
  [[ "$output" == *"verification: prototype"* ]]
  [[ "$output" == *"preview_deploy: true"* ]]
  [[ "$output" == *"enabled: true"* ]]
  [[ "$output" == *"\"hackathon/*\""* ]]
  [[ "$output" == *"min_walter_score: 70"* ]]
  [[ "$output" == *"max_risk: medium"* ]]
  [[ "$output" == *"  - auth"* ]]
  [[ "$output" == *"  - destructive_ops"* ]]
}

@test "repo-config defaults hackathon emits a valid policy file" {
  "$WALTER_OS_BIN" repo-config defaults hackathon > "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config validate "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-config: valid"* ]]
  [[ "$output" == *"effective autonomy_mode: full"* ]]
  [[ "$output" == *"hard-limit floor: non-overridable"* ]]
}

@test "repo-config defaults rejects unknown profile presets" {
  run "$WALTER_OS_BIN" repo-config defaults sleepy

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown defaults profile: sleepy"* ]]
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

@test "repo-config library loads protected paths from sibling when WALTER_OS_HOME is wrong" {
  run bash -c '
    export WALTER_OS_HOME="$1/missing"
    # shellcheck source=/dev/null
    source "$2"
    _walter_repo_config_path_is_hard_floor "bin/walter-os"
  ' bash "$TMP_DIR" "$REPO_ROOT/scripts/walter/lib/repo-config.sh"

  [ "$status" -eq 0 ]
}

@test "repo-config library falls back to minimal protected paths when policy file is missing" {
  cp "$REPO_ROOT/scripts/walter/lib/repo-config.sh" "$TMP_DIR/repo-config.sh"

  run bash -c '
    export WALTER_OS_HOME="$1/missing"
    # shellcheck source=/dev/null
    source "$2"
    _walter_repo_config_path_is_hard_floor "install.sh"
  ' bash "$TMP_DIR" "$TMP_DIR/repo-config.sh"

  [ "$status" -eq 0 ]
}

@test "repo-config fallback policy preserves high-sensitivity hard-floor paths" {
  cp "$REPO_ROOT/scripts/walter/lib/repo-config.sh" "$TMP_DIR/repo-config.sh"

  run bash -c '
    export WALTER_OS_HOME="$1/missing"
    # shellcheck source=/dev/null
    source "$2"
    _walter_repo_config_path_is_hard_floor ".ssh/id_ed25519" &&
      _walter_repo_config_path_is_hard_floor "nested/.ssh/id_ed25519" &&
      _walter_repo_config_path_is_hard_floor ".claude/settings.json"
  ' bash "$TMP_DIR" "$TMP_DIR/repo-config.sh"

  [ "$status" -eq 0 ]
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

@test "verification-plan uses prototype checks for low-risk risk_based changes" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path docs/operational/repo-config.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"verification: risk_based"* ]]
  [[ "$output" == *"effective_risk: low"* ]]
  [[ "$output" == *"plan: prototype"* ]]
  [[ "$output" == *"  - lint"* ]]
  [[ "$output" == *"  - smoke_test"* ]]
}

@test "verification-plan applies risk_based defaults when config is absent" {
  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path docs/README.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"verification: risk_based"* ]]
  [[ "$output" == *"plan: prototype"* ]]
}

@test "verification-plan raises script changes to medium risk checks" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path scripts/walter/lib/repo-config.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"path_risk: medium"* ]]
  [[ "$output" == *"effective_risk: medium"* ]]
  [[ "$output" == *"plan: risk_based"* ]]
  [[ "$output" == *"  - targeted_tests"* ]]
}

@test "verification-plan normalizes dot-slash script paths for medium risk" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path ./scripts/walter/lib/repo-config.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"path_risk: medium"* ]]
  [[ "$output" == *"effective_risk: medium"* ]]
}

@test "verification-plan escalates hard-floor paths even in prototype profile" {
  "$WALTER_OS_BIN" repo-config defaults hackathon > "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path install.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"verification: prototype"* ]]
  [[ "$output" == *"hard_floor: yes"* ]]
  [[ "$output" == *"effective_risk: high"* ]]
  [[ "$output" == *"plan: production"* ]]
  [[ "$output" == *"human_gate: required"* ]]
  [[ "$output" == *"  - security_review"* ]]
}

@test "verification-plan uses shared protected-path policy for hard-floor paths" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path bin/walter-os

  [ "$status" -eq 0 ]
  [[ "$output" == *"hard_floor: yes"* ]]
  [[ "$output" == *"plan: production"* ]]
}

@test "verification-plan does not hard-floor non-migration paths containing migration" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path docs/operational/data-migration-safety.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"path_risk: low"* ]]
  [[ "$output" == *"hard_floor: no"* ]]
  [[ "$output" == *"plan: prototype"* ]]
}

@test "verification-plan prints validation diagnostics for invalid policy" {
  write_valid_config
  sed -i.bak 's/verification: risk_based/verification: vibes/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" --risk low

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid verification: vibes"* ]]
}

@test "verification-plan production mode requires full verification for low risk" {
  write_valid_config
  sed -i.bak 's/verification: risk_based/verification: production/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path docs/operational/repo-config.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"verification: production"* ]]
  [[ "$output" == *"plan: production"* ]]
  [[ "$output" == *"  - lint"* ]]
  [[ "$output" == *"  - typecheck"* ]]
  [[ "$output" == *"  - rollback_plan"* ]]
}

@test "verification-plan adds screenshot validation for UI paths" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path apps/control-tower/app/page.tsx

  [ "$status" -eq 0 ]
  [[ "$output" == *"plan: prototype"* ]]
  [[ "$output" == *"  - screenshot_validation"* ]]
}

@test "verification-plan normalizes dot-slash Control Tower UI paths" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" \
    --risk low \
    --path ./apps/control-tower/app/page.ts

  [ "$status" -eq 0 ]
  [[ "$output" == *"  - screenshot_validation"* ]]
}

@test "verification-plan rejects invalid risk values" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" --risk spicy

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid risk: spicy"* ]]
}

@test "verification-plan rejects missing risk values without shell noise" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" --risk

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --risk"* ]]
  [[ "$output" != *"shift count out of range"* ]]
}

@test "verification-plan rejects missing path values without shell noise" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" --risk low --path

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --path"* ]]
  [[ "$output" != *"shift count out of range"* ]]
}

@test "verification-plan rejects option-looking missing path values" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" --path --risk low

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --path"* ]]
}

@test "verification-plan rejects unknown options unless forced positional" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" --unknown

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --unknown"* ]]

  run "$WALTER_OS_BIN" repo-config verification-plan "$TMP_DIR/repo" -- --unknown

  [ "$status" -eq 0 ]
  [[ "$output" == *"path_risk: low"* ]]
}

@test "capability-plan defaults to read-only without evidence" {
  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo_ceiling: 1 assisted"* ]]
  [[ "$output" == *"evidence_tier: 0 read_only"* ]]
  [[ "$output" == *"effective_tier: 0 read_only"* ]]
  [[ "$output" == *"human_gate: required"* ]]
}

@test "capability-plan computes assisted with CI and tests evidence" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" \
    --evidence ci \
    --evidence tests

  [ "$status" -eq 0 ]
  [[ "$output" == *"evidence_tier: 1 assisted"* ]]
  [[ "$output" == *"effective_tier: 1 assisted"* ]]
  [[ "$output" == *"allowed_actions:"* ]]
  [[ "$output" == *"  - open_pr"* ]]
}

@test "capability-plan caps rich evidence by repo ceiling" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" \
    --risk low \
    --evidence ci \
    --evidence tests \
    --evidence sandbox \
    --evidence egress \
    --evidence rollback \
    --evidence branch_protection \
    --evidence history

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo_ceiling: 1 assisted"* ]]
  [[ "$output" == *"evidence_tier: 3 bounded_autonomy"* ]]
  [[ "$output" == *"effective_tier: 1 assisted"* ]]
}

@test "capability-plan allows bounded autonomy only with ceiling and evidence" {
  write_valid_config
  sed -i.bak 's/capability_tier_ceiling: 1/capability_tier_ceiling: 3/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" \
    --risk low \
    --evidence ci \
    --evidence tests \
    --evidence sandbox \
    --evidence egress \
    --evidence rollback \
    --evidence branch_protection \
    --evidence history

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo_ceiling: 3 bounded_autonomy"* ]]
  [[ "$output" == *"evidence_tier: 3 bounded_autonomy"* ]]
  [[ "$output" == *"effective_tier: 3 bounded_autonomy"* ]]
  [[ "$output" == *"  - policy_auto_merge_non_protected"* ]]
}

@test "capability-plan caps hard-floor paths at assisted and requires human gate" {
  write_valid_config
  sed -i.bak 's/capability_tier_ceiling: 1/capability_tier_ceiling: 3/' \
    "$TMP_DIR/repo/walter-repo-config.yaml"

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" \
    --risk low \
    --path install.sh \
    --evidence ci \
    --evidence tests \
    --evidence sandbox \
    --evidence egress \
    --evidence rollback \
    --evidence branch_protection \
    --evidence history

  [ "$status" -eq 0 ]
  [[ "$output" == *"hard_floor: yes"* ]]
  [[ "$output" == *"effective_tier: 1 assisted"* ]]
  [[ "$output" == *"human_gate: required"* ]]
}

@test "capability-plan rejects unknown evidence names" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" --evidence vibes

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid evidence: vibes"* ]]
}

@test "capability-plan rejects missing risk values without shell noise" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" --risk

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --risk"* ]]
  [[ "$output" != *"shift count out of range"* ]]
}

@test "capability-plan rejects missing path values without shell noise" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" --risk low --path

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --path"* ]]
  [[ "$output" != *"shift count out of range"* ]]
}

@test "capability-plan rejects option-looking missing path values" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" --path --risk low

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --path"* ]]
}

@test "capability-plan rejects missing evidence values without shell noise" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" --evidence

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --evidence"* ]]
  [[ "$output" != *"shift count out of range"* ]]
}

@test "capability-plan rejects unknown options unless forced positional" {
  write_valid_config

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" --unknown

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --unknown"* ]]

  run "$WALTER_OS_BIN" repo-config capability-plan "$TMP_DIR/repo" -- --unknown

  [ "$status" -eq 0 ]
  [[ "$output" == *"path_risk: low"* ]]
}
