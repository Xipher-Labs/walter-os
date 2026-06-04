#!/usr/bin/env bash
# scripts/walter/lib/repo-config.sh
#
# Loader + validator for walter-repo-config.yaml (AD-5 / ADR-0026).
# This file is intentionally policy-only: it validates the committed per-repo
# policy surface, but it does not relax approval-gate hard limits.

_WALTER_REPO_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WALTER_REPO_CONFIG_PROTECTED_PATHS_LIB="${_WALTER_REPO_CONFIG_LIB_DIR}/protected-paths.sh"
if [[ ! -f "$_WALTER_REPO_CONFIG_PROTECTED_PATHS_LIB" && -n "${WALTER_OS_HOME:-}" ]]; then
  _WALTER_REPO_CONFIG_PROTECTED_PATHS_LIB="${WALTER_OS_HOME}/scripts/walter/lib/protected-paths.sh"
fi
if [[ -f "$_WALTER_REPO_CONFIG_PROTECTED_PATHS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_WALTER_REPO_CONFIG_PROTECTED_PATHS_LIB"
elif ! declare -p WALTER_PROTECTED_PATH_PATTERNS >/dev/null 2>&1; then
  declare -a WALTER_PROTECTED_PATH_PATTERNS=(
    'hooks/*.sh'
    '.claude/settings.json'
    '.github/workflows/*'
    'install.sh'
    'bin/walter-os'
    'AGENTS.md'
    'CLAUDE.md'
    'mcp/servers.json'
    'scripts/walter/lib/capability-token.sh'
    'scripts/walter/lib/skill-cap-loader.sh'
    'scripts/walter/lib/session-state.sh'
    'scripts/walter/lib/protected-paths.sh'
    'scripts/walter/subcommands/cap.sh'
    'agents/*.md'
    'skills/*/SKILL.md'
    'auth/*'
    'crypto/*'
    'personal/health/*'
    '*.key'
    '*.pem'
    '*.crt'
    '.ssh/*'
    '*/.ssh/*'
    '*.env'
    '*.env.*'
  )
fi
unset _WALTER_REPO_CONFIG_LIB_DIR _WALTER_REPO_CONFIG_PROTECTED_PATHS_LIB

walter_repo_config_defaults() {
  local profile="${1:-balanced}"

  case "$profile" in
    balanced)
      cat <<'YAML'
autonomy_mode: guided
profile: balanced
capability_tier_ceiling: 1
auto_merge:
  enabled: false
  allowed_branches: []
  forbidden_branches:
    - main
    - master
    - staging
    - production
    - "release/*"
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
      ;;
    hackathon)
      cat <<'YAML'
autonomy_mode: full
profile: hackathon
capability_tier_ceiling: 1
auto_merge:
  enabled: true
  allowed_branches:
    - "hackathon/*"
  forbidden_branches:
    - main
    - master
    - staging
    - production
    - "release/*"
  require_green_ci: true
  min_walter_score: 70
  max_risk: medium
verification: prototype
preview_deploy: true
human_approval_required_for:
  - auth
  - payments
  - secrets
  - prod_infra
  - db_migrations
  - destructive_ops
YAML
      ;;
    *)
      printf 'repo-config: unknown defaults profile: %s\n' "$profile" >&2
      return 2
      ;;
  esac
}

walter_repo_config_path() {
  local target="${1:-$(pwd)}"
  if [[ -d "$target" ]]; then
    printf '%s\n' "${target%/}/walter-repo-config.yaml"
  else
    printf '%s\n' "$target"
  fi
}

walter_repo_config_print_mode_contract() {
  local mode="${1:-guided}"
  local summary

  case "$mode" in
    lite)
      summary="lite = plan, report, and request approval; no autonomous code/PR/deploy progression"
      ;;
    guided)
      summary="guided = default human-in-the-loop delivery; agents may prepare work, humans approve intent/architecture/merge"
      ;;
    full)
      summary="full = policy-bounded autonomy for eligible non-protected paths; protected actions still require humans"
      ;;
    *)
      mode="guided"
      summary="unknown mode requested; safest guided semantics apply until validation succeeds"
      ;;
  esac

  printf 'repo-config: effective autonomy_mode: %s\n' "$mode"
  printf 'repo-config: autonomy scope: policy axis, not install tier\n'
  printf 'repo-config: mode semantics: %s\n' "$summary"
  printf 'repo-config: hard-limit floor: non-overridable in every mode\n'
}

_walter_repo_config_risk_rank() {
  case "${1:-low}" in
    low) printf '1\n' ;;
    medium) printf '2\n' ;;
    high) printf '3\n' ;;
    *) printf '0\n' ;;
  esac
}

_walter_repo_config_max_risk() {
  local left="${1:-low}"
  local right="${2:-low}"
  if (( $(_walter_repo_config_risk_rank "$right") > $(_walter_repo_config_risk_rank "$left") )); then
    printf '%s\n' "$right"
  else
    printf '%s\n' "$left"
  fi
}

_walter_repo_config_path_is_hard_floor() {
  local path="$1"
  local normalized="${path#./}"
  local pattern
  if declare -p WALTER_PROTECTED_PATH_PATTERNS >/dev/null 2>&1; then
    for pattern in "${WALTER_PROTECTED_PATH_PATTERNS[@]}"; do
      # shellcheck disable=SC2053 # Shared protected path policy uses globs.
      if [[ "$normalized" == $pattern || "$normalized" == */$pattern || \
            "$normalized" == $pattern/* || "$normalized" == */$pattern/* ]]; then
        return 0
      fi
    done
  fi

  case "$normalized" in
    migrations/*|*/migrations/*)
      return 0
      ;;
  esac
  return 1
}

_walter_repo_config_path_is_medium_risk() {
  local path="$1"
  local normalized="${path#./}"
  case "$normalized" in
    bin/*|*/bin/*|scripts/*|*/scripts/*|setup/*|*/setup/*|compose.yml|*/compose.yml|\
    docker-compose.yml|*/docker-compose.yml|apps/*/api/*|*/apps/*/api/*)
      return 0
      ;;
  esac
  return 1
}

_walter_repo_config_path_is_ui() {
  local path="$1"
  local normalized="${path#./}"
  case "$normalized" in
    apps/control-tower/*|*/apps/control-tower/*|*.tsx|*.jsx|*.css|*.scss)
      return 0
      ;;
  esac
  return 1
}

_walter_repo_config_print_checks() {
  local plan="$1"
  local ui_change="$2"

  printf 'required_checks:\n'
  case "$plan" in
    prototype)
      printf '  - lint\n'
      printf '  - typecheck\n'
      printf '  - smoke_test\n'
      printf '  - critical_path_test\n'
      ;;
    risk_based)
      printf '  - lint\n'
      printf '  - typecheck\n'
      printf '  - targeted_tests\n'
      printf '  - integration_tests\n'
      printf '  - acceptance_criteria_check\n'
      ;;
    production)
      printf '  - lint\n'
      printf '  - typecheck\n'
      printf '  - spec_up_to_date\n'
      printf '  - red_green_refactor_tests\n'
      printf '  - unit_tests\n'
      printf '  - integration_tests\n'
      printf '  - e2e_or_smoke\n'
      printf '  - acceptance_criteria_coverage\n'
      printf '  - security_review\n'
      printf '  - rollback_plan\n'
      ;;
  esac
  if [[ "$ui_change" == "yes" ]]; then
    printf '  - screenshot_validation\n'
  fi
}

_walter_repo_config_tier_name() {
  case "${1:-0}" in
    0) printf 'read_only\n' ;;
    1) printf 'assisted\n' ;;
    2) printf 'supervised_autonomy\n' ;;
    3) printf 'bounded_autonomy\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

_walter_repo_config_bool_has() {
  local haystack="$1"
  local needle="$2"
  grep -Fxq "$needle" <<<"$haystack"
}

_walter_repo_config_cap_min() {
  local left="$1"
  local right="$2"
  if (( left < right )); then
    printf '%s\n' "$left"
  else
    printf '%s\n' "$right"
  fi
}

_walter_repo_config_print_capability_actions() {
  local tier="$1"

  printf 'allowed_actions:\n'
  case "$tier" in
    0)
      printf '  - read\n'
      printf '  - search\n'
      printf '  - comment\n'
      ;;
    1)
      printf '  - read\n'
      printf '  - search\n'
      printf '  - create_branch\n'
      printf '  - implement\n'
      printf '  - run_tests\n'
      printf '  - open_pr\n'
      ;;
    2)
      printf '  - read\n'
      printf '  - search\n'
      printf '  - create_branch\n'
      printf '  - implement\n'
      printf '  - run_tests\n'
      printf '  - open_pr\n'
      printf '  - deploy_preview\n'
      ;;
    3)
      printf '  - read\n'
      printf '  - search\n'
      printf '  - create_branch\n'
      printf '  - implement\n'
      printf '  - run_tests\n'
      printf '  - open_pr\n'
      printf '  - deploy_preview\n'
      printf '  - policy_auto_merge_non_protected\n'
      ;;
  esac
}

walter_repo_config_capability_plan() {
  local target="${1:-$(pwd)}"
  shift || true
  local input_risk="low"
  local paths=()
  local evidence_items=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --risk)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          printf 'repo-config: missing value for --risk\n' >&2
          return 2
        fi
        input_risk="${2:-}"
        shift 2
        ;;
      --risk=*)
        input_risk="${1#--risk=}"
        shift
        ;;
      --path)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          printf 'repo-config: missing value for --path\n' >&2
          return 2
        fi
        paths+=("${2:-}")
        shift 2
        ;;
      --path=*)
        paths+=("${1#--path=}")
        shift
        ;;
      --evidence)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          printf 'repo-config: missing value for --evidence\n' >&2
          return 2
        fi
        evidence_items+=("${2:-}")
        shift 2
        ;;
      --evidence=*)
        evidence_items+=("${1#--evidence=}")
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          paths+=("$1")
          shift
        done
        ;;
      --*)
        printf 'repo-config: unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  case "$input_risk" in
    low|medium|high) ;;
    *)
      printf 'repo-config: invalid risk: %s\n' "$input_risk" >&2
      return 2
      ;;
  esac

  local evidence_set="" evidence normalized
  for evidence in "${evidence_items[@]}"; do
    normalized="${evidence//-/_}"
    case "$normalized" in
      ci|tests|coverage|sandbox|egress|rollback|branch_protection|history)
        evidence_set="${evidence_set}${evidence_set:+$'\n'}${normalized}"
        ;;
      *)
        printf 'repo-config: invalid evidence: %s\n' "$evidence" >&2
        return 2
        ;;
    esac
  done

  local validation_output
  if ! validation_output="$(walter_repo_config_validate "$target" 2>&1)"; then
    printf '%s\n' "$validation_output"
    return 1
  fi

  local config_path repo_ceiling=1 path hard_floor="no" path_risk="low" effective_risk
  config_path="$(walter_repo_config_path "$target")"
  if [[ -f "$config_path" ]]; then
    repo_ceiling="$(yq e '.capability_tier_ceiling // 1' "$config_path" 2>/dev/null || printf '1')"
  fi

  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && continue
    if _walter_repo_config_path_is_hard_floor "$path"; then
      hard_floor="yes"
      path_risk="$(_walter_repo_config_max_risk "$path_risk" high)"
    elif _walter_repo_config_path_is_medium_risk "$path"; then
      path_risk="$(_walter_repo_config_max_risk "$path_risk" medium)"
    fi
  done
  effective_risk="$(_walter_repo_config_max_risk "$input_risk" "$path_risk")"

  local evidence_tier=0
  if _walter_repo_config_bool_has "$evidence_set" ci \
      && _walter_repo_config_bool_has "$evidence_set" tests; then
    evidence_tier=1
  fi
  if (( evidence_tier >= 1 )) \
      && _walter_repo_config_bool_has "$evidence_set" sandbox \
      && _walter_repo_config_bool_has "$evidence_set" egress \
      && _walter_repo_config_bool_has "$evidence_set" rollback; then
    evidence_tier=2
  fi
  if (( evidence_tier >= 2 )) \
      && _walter_repo_config_bool_has "$evidence_set" branch_protection \
      && _walter_repo_config_bool_has "$evidence_set" history \
      && [[ "$effective_risk" == "low" && "$hard_floor" == "no" ]]; then
    evidence_tier=3
  fi

  local risk_cap=3
  case "$effective_risk" in
    high) risk_cap=1 ;;
    medium) risk_cap=2 ;;
  esac
  if [[ "$hard_floor" == "yes" ]]; then
    risk_cap=1
  fi

  local effective_tier
  effective_tier="$(_walter_repo_config_cap_min "$repo_ceiling" "$evidence_tier")"
  effective_tier="$(_walter_repo_config_cap_min "$effective_tier" "$risk_cap")"

  printf 'repo-config: capability plan\n'
  printf 'policy: %s\n' "$config_path"
  printf 'repo_ceiling: %s %s\n' "$repo_ceiling" "$(_walter_repo_config_tier_name "$repo_ceiling")"
  printf 'evidence_tier: %s %s\n' "$evidence_tier" "$(_walter_repo_config_tier_name "$evidence_tier")"
  printf 'risk_cap: %s %s\n' "$risk_cap" "$(_walter_repo_config_tier_name "$risk_cap")"
  printf 'effective_tier: %s %s\n' "$effective_tier" "$(_walter_repo_config_tier_name "$effective_tier")"
  printf 'input_risk: %s\n' "$input_risk"
  printf 'path_risk: %s\n' "$path_risk"
  printf 'effective_risk: %s\n' "$effective_risk"
  printf 'hard_floor: %s\n' "$hard_floor"
  if (( effective_tier < 3 )) || [[ "$hard_floor" == "yes" || "$effective_risk" == "high" ]]; then
    printf 'human_gate: required\n'
  else
    printf 'human_gate: policy\n'
  fi
  _walter_repo_config_print_capability_actions "$effective_tier"
}

walter_repo_config_verification_plan() {
  local target="${1:-$(pwd)}"
  shift || true
  local input_risk="low"
  local paths=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --risk)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          printf 'repo-config: missing value for --risk\n' >&2
          return 2
        fi
        input_risk="${2:-}"
        shift 2
        ;;
      --risk=*)
        input_risk="${1#--risk=}"
        shift
        ;;
      --path)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          printf 'repo-config: missing value for --path\n' >&2
          return 2
        fi
        paths+=("${2:-}")
        shift 2
        ;;
      --path=*)
        paths+=("${1#--path=}")
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          paths+=("$1")
          shift
        done
        ;;
      --*)
        printf 'repo-config: unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  case "$input_risk" in
    low|medium|high) ;;
    *)
      printf 'repo-config: invalid risk: %s\n' "$input_risk" >&2
      return 2
      ;;
  esac

  local validation_output
  if ! validation_output="$(walter_repo_config_validate "$target" 2>&1)"; then
    printf '%s\n' "$validation_output"
    return 1
  fi

  local config_path verification policy_status path path_risk="low" effective_risk hard_floor="no" ui_change="no"
  config_path="$(walter_repo_config_path "$target")"
  verification="risk_based"
  policy_status="defaulted_missing"
  if [[ -f "$config_path" ]]; then
    verification="$(yq e '.verification // "risk_based"' "$config_path" 2>/dev/null || printf 'risk_based')"
    policy_status="configured"
  fi

  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && continue
    if _walter_repo_config_path_is_hard_floor "$path"; then
      hard_floor="yes"
      path_risk="$(_walter_repo_config_max_risk "$path_risk" high)"
    elif _walter_repo_config_path_is_medium_risk "$path"; then
      path_risk="$(_walter_repo_config_max_risk "$path_risk" medium)"
    fi
    if _walter_repo_config_path_is_ui "$path"; then
      ui_change="yes"
    fi
  done

  effective_risk="$(_walter_repo_config_max_risk "$input_risk" "$path_risk")"

  local plan
  if [[ "$hard_floor" == "yes" || "$verification" == "production" || "$effective_risk" == "high" ]]; then
    plan="production"
  elif [[ "$verification" == "prototype" || "$effective_risk" == "low" ]]; then
    plan="prototype"
  else
    plan="risk_based"
  fi

  printf 'repo-config: verification plan\n'
  printf 'policy: %s\n' "$config_path"
  printf 'policy_status: %s\n' "$policy_status"
  printf 'verification: %s\n' "$verification"
  printf 'input_risk: %s\n' "$input_risk"
  printf 'path_risk: %s\n' "$path_risk"
  printf 'effective_risk: %s\n' "$effective_risk"
  printf 'hard_floor: %s\n' "$hard_floor"
  printf 'ui_change: %s\n' "$ui_change"
  if [[ "$hard_floor" == "yes" || "$plan" == "production" ]]; then
    printf 'human_gate: required\n'
  else
    printf 'human_gate: policy\n'
  fi
  printf 'plan: %s\n' "$plan"
  _walter_repo_config_print_checks "$plan" "$ui_change"
}

_walter_repo_config_require_yq() {
  if ! command -v yq >/dev/null 2>&1; then
    printf 'repo-config: invalid: yq missing; install mikefarah/yq to validate walter-repo-config.yaml\n'
    return 1
  fi
  if ! (yq --version 2>&1 | grep -qi 'mikefarah'); then
    printf 'repo-config: invalid: yq is not mikefarah/yq: %s\n' "$(yq --version 2>&1 | head -1)"
    return 1
  fi
}

_walter_repo_config_yq_true() {
  local path="$1"
  local expr="$2"
  local result
  result="$(yq e "$expr" "$path" 2>/dev/null)" || return 1
  [[ "$result" == "true" ]]
}

_walter_repo_config_has() {
  local path="$1"
  local expr="$2"
  _walter_repo_config_yq_true "$path" "has(\"$expr\")"
}

_walter_repo_config_auto_merge_has() {
  local path="$1"
  local expr="$2"
  _walter_repo_config_yq_true "$path" ".auto_merge | has(\"$expr\")"
}

_walter_repo_config_fail() {
  printf 'repo-config: invalid: %s\n' "$*"
  WALTER_REPO_CONFIG_ERRORS=$((WALTER_REPO_CONFIG_ERRORS + 1))
}

_walter_repo_config_warn() {
  printf 'WARN repo-config: %s\n' "$*"
  WALTER_REPO_CONFIG_WARNINGS=$((WALTER_REPO_CONFIG_WARNINGS + 1))
}

_walter_repo_config_validate_enum() {
  local path="$1"
  local key="$2"
  local label="$3"
  shift 3
  _walter_repo_config_has "$path" "$key" || return 0

  local type value allowed
  type="$(yq e ".${key} | tag" "$path" 2>/dev/null || true)"
  value="$(yq e ".${key}" "$path" 2>/dev/null || true)"
  if [[ "$type" != "!!str" ]]; then
    _walter_repo_config_fail "invalid ${label}: expected string"
    return 0
  fi

  for allowed in "$@"; do
    [[ "$value" == "$allowed" ]] && return 0
  done
  _walter_repo_config_fail "invalid ${label}: ${value}"
}

_walter_repo_config_validate_bool() {
  local path="$1"
  local expr="$2"
  local label="$3"
  local type
  type="$(yq e "${expr} | tag" "$path" 2>/dev/null || true)"
  [[ "$type" == "!!bool" ]] || _walter_repo_config_fail "invalid ${label}: expected boolean"
}

_walter_repo_config_validate_int_range() {
  local path="$1"
  local expr="$2"
  local label="$3"
  local min="$4"
  local max="$5"
  local type value
  type="$(yq e "${expr} | tag" "$path" 2>/dev/null || true)"
  value="$(yq e "$expr" "$path" 2>/dev/null || true)"
  if [[ "$type" != "!!int" ]] || ! [[ "$value" =~ ^-?[0-9]+$ ]] \
      || (( value < min || value > max )); then
    _walter_repo_config_fail "invalid ${label}: expected integer ${min}..${max}"
  fi
}

_walter_repo_config_validate_string_array() {
  local path="$1"
  local expr="$2"
  local label="$3"
  local type item_type
  type="$(yq e "${expr} | tag" "$path" 2>/dev/null || true)"
  if [[ "$type" != "!!seq" ]]; then
    _walter_repo_config_fail "invalid ${label}: expected string array"
    return 0
  fi

  while IFS= read -r item_type; do
    [[ -z "$item_type" ]] && continue
    if [[ "$item_type" != "!!str" ]]; then
      _walter_repo_config_fail "invalid ${label}: all entries must be strings"
      return 0
    fi
  done < <(yq e "${expr}[] | tag" "$path" 2>/dev/null || true)
}

_walter_repo_config_validate_top_keys() {
  local path="$1"
  local key
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    case "$key" in
      autonomy_mode|profile|capability_tier_ceiling|auto_merge|verification|preview_deploy|human_approval_required_for)
        ;;
      *)
        _walter_repo_config_warn "unknown key: ${key}"
        ;;
    esac
  done < <(yq e 'keys | .[]' "$path" 2>/dev/null || true)
}

_walter_repo_config_validate_auto_merge_keys() {
  local path="$1"
  local key
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    case "$key" in
      enabled|allowed_branches|forbidden_branches|require_green_ci|min_walter_score|max_risk)
        ;;
      *)
        _walter_repo_config_warn "unknown auto_merge key: ${key}"
        ;;
    esac
  done < <(yq e '.auto_merge | keys | .[]' "$path" 2>/dev/null || true)
}

_walter_repo_config_validate_human_approvals() {
  local path="$1"
  if ! _walter_repo_config_has "$path" "human_approval_required_for"; then
    _walter_repo_config_fail "missing hard-floor approval list: human_approval_required_for"
    return 0
  fi
  _walter_repo_config_validate_string_array "$path" ".human_approval_required_for" "human_approval_required_for"

  local approvals required item
  approvals="$(yq e '.human_approval_required_for[]' "$path" 2>/dev/null || true)"
  for required in auth payments secrets prod_infra db_migrations destructive_ops; do
    if ! printf '%s\n' "$approvals" | grep -Fxq "$required"; then
      _walter_repo_config_fail "missing hard-floor approval: ${required}"
    fi
  done

  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if ! [[ "$item" =~ ^[a-z][a-z0-9_-]*$ ]]; then
      _walter_repo_config_fail "invalid human_approval_required_for entry: ${item}"
    fi
  done < <(yq e '.human_approval_required_for[]' "$path" 2>/dev/null || true)
}

_walter_repo_config_validate_allowed_branches() {
  local path="$1"
  _walter_repo_config_validate_string_array "$path" ".auto_merge.allowed_branches" "auto_merge.allowed_branches"

  local branch prefix protected protected_prefix
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    case "$branch" in
      \*|\*\*|main|master|staging|production|release)
        _walter_repo_config_fail "auto_merge.allowed_branches includes protected branch: ${branch}"
        ;;
    esac
    case "$branch" in
      release/*)
        _walter_repo_config_fail "auto_merge.allowed_branches includes protected branch namespace: ${branch}"
        ;;
    esac
    case "$branch" in
      *\**|*\?*|*\[*)
        prefix="$branch"
        prefix="${prefix%%\**}"
        prefix="${prefix%%\?*}"
        prefix="${prefix%%\[*}"
        if [[ -z "$prefix" ]]; then
          _walter_repo_config_fail "auto_merge.allowed_branches glob has no safe literal prefix: ${branch}"
        else
          for protected_prefix in main master staging production release/; do
            if [[ "$protected_prefix" == "$prefix"* ]] || [[ "$prefix" == release/* ]]; then
              _walter_repo_config_fail "auto_merge.allowed_branches glob prefix intersects protected branches: ${branch} -> ${protected_prefix}"
              break
            fi
          done
        fi
        ;;
    esac

    # Treat allowed_branches entries as shell-style patterns because the
    # schema intentionally allows entries like "walter/*". Reject any pattern
    # that can match a protected branch name before later auto-merge consumers
    # read it as authorization.
    for protected in \
      main master staging production \
      release/0 release/1 release/9 \
      release/a release/b release/c release/d release/e release/f release/g \
      release/h release/i release/j release/k release/l release/m release/n \
      release/o release/p release/q release/r release/s release/t release/u \
      release/v release/w release/x release/y release/z release/v1 release/prod; do
      # shellcheck disable=SC2053 # RHS is intentionally a policy glob.
      if [[ "$protected" == $branch ]]; then
        _walter_repo_config_fail "auto_merge.allowed_branches pattern matches protected branch: ${branch} -> ${protected}"
      fi
    done
  done < <(yq e '.auto_merge.allowed_branches[]' "$path" 2>/dev/null || true)
}

_walter_repo_config_validate_auto_merge() {
  local path="$1"
  _walter_repo_config_has "$path" "auto_merge" || return 0

  local type
  type="$(yq e '.auto_merge | tag' "$path" 2>/dev/null || true)"
  if [[ "$type" != "!!map" ]]; then
    _walter_repo_config_fail "invalid auto_merge: expected map"
    return 0
  fi

  _walter_repo_config_validate_auto_merge_keys "$path"
  _walter_repo_config_auto_merge_has "$path" "enabled" \
    && _walter_repo_config_validate_bool "$path" ".auto_merge.enabled" "auto_merge.enabled"
  _walter_repo_config_auto_merge_has "$path" "allowed_branches" \
    && _walter_repo_config_validate_allowed_branches "$path"
  _walter_repo_config_auto_merge_has "$path" "forbidden_branches" \
    && _walter_repo_config_validate_string_array "$path" ".auto_merge.forbidden_branches" "auto_merge.forbidden_branches"
  _walter_repo_config_auto_merge_has "$path" "require_green_ci" \
    && _walter_repo_config_validate_bool "$path" ".auto_merge.require_green_ci" "auto_merge.require_green_ci"
  _walter_repo_config_auto_merge_has "$path" "min_walter_score" \
    && _walter_repo_config_validate_int_range "$path" ".auto_merge.min_walter_score" "auto_merge.min_walter_score" 0 100

  if _walter_repo_config_auto_merge_has "$path" "max_risk"; then
    local risk_type risk
    risk_type="$(yq e '.auto_merge.max_risk | tag' "$path" 2>/dev/null || true)"
    risk="$(yq e '.auto_merge.max_risk' "$path" 2>/dev/null || true)"
    if [[ "$risk_type" != "!!str" ]] || [[ ! "$risk" =~ ^(low|medium|high)$ ]]; then
      _walter_repo_config_fail "invalid auto_merge.max_risk: ${risk}"
    fi
  fi
}

walter_repo_config_validate() {
  local target="${1:-$(pwd)}"
  local path
  path="$(walter_repo_config_path "$target")"
  WALTER_REPO_CONFIG_ERRORS=0
  WALTER_REPO_CONFIG_WARNINGS=0

  if [[ ! -e "$target" ]]; then
    _walter_repo_config_fail "target not found: ${target}"
    return 1
  fi

  if [[ ! -f "$path" ]]; then
    printf 'repo-config: absent at %s; safest defaults apply\n' "$path"
    walter_repo_config_print_mode_contract guided
    return 0
  fi

  _walter_repo_config_require_yq || return 1

  if ! yq e '.' "$path" >/dev/null 2>&1; then
    _walter_repo_config_fail "YAML parse failed: ${path}"
    return 1
  fi

  if ! _walter_repo_config_yq_true "$path" 'tag == "!!map"'; then
    _walter_repo_config_fail "root must be a YAML map"
  else
    _walter_repo_config_validate_top_keys "$path"
    _walter_repo_config_validate_enum "$path" "autonomy_mode" "autonomy_mode" lite guided full
    _walter_repo_config_validate_enum "$path" "profile" "profile" balanced hackathon production

    if _walter_repo_config_has "$path" "capability_tier_ceiling"; then
      _walter_repo_config_validate_int_range "$path" ".capability_tier_ceiling" "capability_tier_ceiling" 0 3
    fi

    _walter_repo_config_validate_auto_merge "$path"
    _walter_repo_config_validate_enum "$path" "verification" "verification" prototype risk_based production

    if _walter_repo_config_has "$path" "preview_deploy"; then
      _walter_repo_config_validate_bool "$path" ".preview_deploy" "preview_deploy"
    fi

    _walter_repo_config_validate_human_approvals "$path"
  fi

  if [[ "$WALTER_REPO_CONFIG_ERRORS" -gt 0 ]]; then
    return 1
  fi

  local autonomy_mode
  autonomy_mode="$(yq e '.autonomy_mode // "guided"' "$path" 2>/dev/null || printf 'guided')"
  printf 'repo-config: valid: %s\n' "$path"
  walter_repo_config_print_mode_contract "$autonomy_mode"
  return 0
}
