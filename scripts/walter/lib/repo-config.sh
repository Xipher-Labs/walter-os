#!/usr/bin/env bash
# scripts/walter/lib/repo-config.sh
#
# Loader + validator for walter-repo-config.yaml (AD-5 / ADR-0026).
# This file is intentionally policy-only: it validates the committed per-repo
# policy surface, but it does not relax approval-gate hard limits.

walter_repo_config_defaults() {
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
}

walter_repo_config_path() {
  local target="${1:-$(pwd)}"
  if [[ -d "$target" ]]; then
    printf '%s\n' "${target%/}/walter-repo-config.yaml"
  else
    printf '%s\n' "$target"
  fi
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
  _walter_repo_config_has "$path" "human_approval_required_for" || return 0
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

  local branch protected
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    case "$branch" in
      '*'|'**'|main|master|staging|production|release|release/*)
        _walter_repo_config_fail "auto_merge.allowed_branches includes protected branch: ${branch}"
        ;;
    esac
    case "$branch" in
      *release/*)
        _walter_repo_config_fail "auto_merge.allowed_branches includes protected branch namespace: ${branch}"
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

  printf 'repo-config: valid: %s\n' "$path"
  return 0
}
