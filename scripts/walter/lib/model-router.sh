#!/usr/bin/env bash
# scripts/walter/lib/model-router.sh
#
# Domain-based model routing for Walter-OS skills and agents.
# Source this file, then call:
#   walter_model_for <backend_review|frontend|longform|quick_refactor|phi|brainstorm|default>
#   walter_model_resolve <domain> <out-var>
#
# Values are LiteLLM-style aliases. A comma-separated value means the caller may
# fan out to multiple models and merge the outputs.

# shellcheck disable=SC2034 # used by sourced callers
WALTER_MODEL_ROUTER_VERSION=1

_walter_model_warn_once() {
  local key="${1:-}" message="${2:-}"
  [[ -n "$key" && -n "$message" ]] || return 0

  if [[ $'\n'"${__WALTER_MODEL_WARNED_KEYS:-}"$'\n' == *$'\n'"$key"$'\n'* ]]; then
    return 0
  fi

  __WALTER_MODEL_WARNED_KEYS="${__WALTER_MODEL_WARNED_KEYS:-}"$'\n'"$key"
  printf '%s\n' "$message" >&2
}

_walter_model_domains_file() {
  local script_dir
  if [[ -n "${WALTER_MODEL_DOMAINS_FILE:-}" ]]; then
    printf '%s\n' "$WALTER_MODEL_DOMAINS_FILE"
    return 0
  fi
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s\n' "$script_dir/model-domains.tsv"
}

_walter_model_load_domain_rows() {
  local file line domain env default description valid_count=0
  file="$(_walter_model_domains_file)"
  if [[ "${__WALTER_MODEL_DOMAIN_ROWS_FILE:-}" == "$file" ]]; then
    return "${__WALTER_MODEL_DOMAIN_ROWS_STATUS:-1}"
  fi

  __WALTER_MODEL_DOMAIN_ROWS_FILE="$file"
  __WALTER_MODEL_DOMAIN_ROWS=""
  __WALTER_MODEL_DOMAIN_ROWS_STATUS=1

  if [[ ! -r "$file" ]]; then
    _walter_model_warn_once "domains-unreadable" \
      "walter-model-router: WARN model domain table is missing or unreadable: $file"
    __WALTER_MODEL_DOMAIN_ROWS_FILE=""
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "${line//[[:space:]]/}" && "${line#\#}" == "$line" ]] || continue
    IFS=$'\t' read -r domain env default description <<<"$line"
    if [[ -z "$domain" || -z "$env" || -z "$default" ||
      ! "$domain" =~ ^[a-z][a-z0-9_]*$ ||
      ! "$env" =~ ^WALTER_MODEL_[A-Z0-9_]+$ ]] ||
      ! walter_model_value_valid "$default"; then
      _walter_model_warn_once "domains-malformed" \
        "walter-model-router: WARN ignoring malformed model domain row in $file"
      continue
    fi
    valid_count=$((valid_count + 1))
    __WALTER_MODEL_DOMAIN_ROWS="${__WALTER_MODEL_DOMAIN_ROWS}${line}"$'\n'
  done < "$file"

  if (( valid_count == 0 )); then
    _walter_model_warn_once "domains-empty" \
      "walter-model-router: WARN model domain table has no valid rows: $file"
    __WALTER_MODEL_DOMAIN_ROWS_FILE=""
    return 1
  fi

  __WALTER_MODEL_DOMAIN_ROWS="${__WALTER_MODEL_DOMAIN_ROWS%$'\n'}"
  __WALTER_MODEL_DOMAIN_ROWS_STATUS=0
}

_walter_model_domain_rows() {
  _walter_model_load_domain_rows || return 1
  printf '%s\n' "$__WALTER_MODEL_DOMAIN_ROWS"
}

walter_model_domains() {
  _walter_model_load_domain_rows || return 1
  printf '%s\n' "$__WALTER_MODEL_DOMAIN_ROWS" | cut -f1
}

_walter_model_domain_exists() {
  local requested="${1:-}" domain _env _default _description
  [[ -n "$requested" ]] || return 1

  while IFS=$'\t' read -r domain _env _default _description; do
    [[ "$domain" == "$requested" ]] && return 0
  done < <(_walter_model_domain_rows)

  return 1
}

_walter_model_domain_field() {
  local requested="${1:-}" field="${2:-}" domain env default description
  [[ -n "$requested" && -n "$field" ]] || return 1

  while IFS=$'\t' read -r domain env default description; do
    if [[ "$domain" == "$requested" ]]; then
      case "$field" in
        env) printf '%s\n' "$env" ;;
        default) printf '%s\n' "$default" ;;
        description) printf '%s\n' "$description" ;;
        *) return 1 ;;
      esac
      return 0
    fi
  done < <(_walter_model_domain_rows)

  return 1
}

_walter_model_normalize_domain() {
  local requested normalized
  requested="${1:-default}"
  case "$requested" in
    phi|medical|health|local)
      normalized="phi" ;;
    backend|backend-review|security|review)
      normalized="backend_review" ;;
    frontend|front-end|ui|ux|design)
      normalized="frontend" ;;
    longform|long-form|writing|content)
      normalized="longform" ;;
    quick|quick-refactor|refactor)
      normalized="quick_refactor" ;;
    brainstorm|brainstorming|plan|planning|research)
      normalized="brainstorm" ;;
    default|"")
      normalized="default" ;;
    *)
      normalized="$(tr '[:upper:]-' '[:lower:]_' <<<"$requested")" ;;
  esac

  printf '%s\n' "$normalized"
}

_walter_model_legacy_domain_exists() {
  case "${1:-}" in
    backend_review|frontend|longform|quick_refactor|phi|brainstorm|default)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

_walter_model_legacy_default_for() {
  case "${1:-default}" in
    backend_review|quick_refactor)
      printf '%s\n' "codex" ;;
    phi)
      printf '%s\n' "local-ollama" ;;
    brainstorm)
      printf '%s\n' "claude,codex" ;;
    frontend|longform|default|*)
      printf '%s\n' "claude" ;;
  esac
}

_walter_model_legacy_env_for() {
  case "${1:-default}" in
    backend_review)
      printf '%s\n' "WALTER_MODEL_BACKEND_REVIEW" ;;
    frontend)
      printf '%s\n' "WALTER_MODEL_FRONTEND" ;;
    longform)
      printf '%s\n' "WALTER_MODEL_LONGFORM" ;;
    quick_refactor)
      printf '%s\n' "WALTER_MODEL_QUICK_REFACTOR" ;;
    phi)
      printf '%s\n' "WALTER_MODEL_PHI" ;;
    brainstorm)
      printf '%s\n' "WALTER_MODEL_BRAINSTORM" ;;
    default|*)
      printf '%s\n' "WALTER_MODEL_DEFAULT" ;;
  esac
}

_walter_model_domain_key() {
  local normalized
  normalized="$(_walter_model_normalize_domain "${1:-default}")"

  if _walter_model_domain_exists "$normalized" || _walter_model_legacy_domain_exists "$normalized"; then
    tr '[:lower:]' '[:upper:]' <<<"$normalized"
  else
    echo "DEFAULT"
  fi
}

_walter_model_domain_slug() {
  tr '[:upper:]' '[:lower:]' <<<"$(_walter_model_domain_key "$1")"
}

walter_model_default_for() {
  local slug
  _walter_model_load_domain_rows || true
  slug="$(_walter_model_domain_slug "${1:-default}")"
  _walter_model_domain_field "$slug" default \
    || _walter_model_legacy_default_for "$slug"
}

walter_model_env_for() {
  local slug
  _walter_model_load_domain_rows || true
  slug="$(_walter_model_domain_slug "${1:-default}")"
  _walter_model_domain_field "$slug" env \
    || _walter_model_legacy_env_for "$slug"
}

walter_model_value_valid() {
  local value="${1:-}"
  local route
  local stripped
  local -a routes
  [[ -n "$value" ]] || return 1

  # Strip every allowed character. Anything left over is a shell/control
  # character we do not want in a model alias or endpoint-like value.
  stripped="${value//[A-Za-z0-9._\/@:+,\[\]-]/}"
  [[ -z "$stripped" ]] || return 1
  [[ "$value" != *, && "$value" != ,* && "$value" != *,,* ]] || return 1

  IFS=',' read -ra routes <<<"$value"
  for route in "${routes[@]}"; do
    [[ -n "$route" ]] || return 1
  done
}

_walter_model_local_alias_safe() {
  local alias="${1:-}"
  [[ -n "$alias" ]] || return 1
  [[ "$alias" =~ ^[A-Za-z0-9._+-]+$ ]]
}

_walter_model_is_local() {
  local value="${1:-}"
  local suffix

  case "$value" in
    local|ollama)
      return 0
      ;;
    local-*)
      suffix="${value#local-}"
      _walter_model_local_alias_safe "$suffix"
      return $?
      ;;
    local/*)
      suffix="${value#local/}"
      _walter_model_local_alias_safe "$suffix"
      return $?
      ;;
    ollama/*)
      suffix="${value#ollama/}"
      _walter_model_local_alias_safe "$suffix"
      return $?
      ;;
    ollama:*)
      suffix="${value#ollama:}"
      _walter_model_local_alias_safe "$suffix"
      return $?
      ;;
    localhost:[0-9]*|127.0.0.1:[0-9]*|'[::1]:'[0-9]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_walter_model_all_routes_local() {
  local value="${1:-}"
  local route
  local -a routes

  IFS=',' read -ra routes <<<"$value"
  for route in "${routes[@]}"; do
    _walter_model_is_local "$route" || return 1
  done
  return 0
}

_walter_model_capabilities_file() {
  echo "${WALTER_AI_CAPABILITIES_FILE:-${WALTER_CONFIG:-$HOME/.config/walter-os}/ai-capabilities.yaml}"
}

_walter_model_yaml_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      if (line ~ "^" key "[[:space:]]*:") {
        sub(/^[^:]*:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  ' "$file"
}

_walter_model_provider_for_route() {
  local route="${1:-}"

  if _walter_model_is_local "$route"; then
    echo "ollama"
    return 0
  fi

  case "$route" in
    claude|haiku|sonnet|opus|claude-*|anthropic/*|openrouter/claude*)
      echo "claude" ;;
    codex|codex-*|gpt|gpt-*|openai/*)
      echo "codex" ;;
    gemini|gemini-*|cheap|nanobanana|google/*)
      echo "gemini" ;;
    copilot)
      echo "copilot" ;;
    none|"")
      echo "none" ;;
    *)
      echo "" ;;
  esac
}

_walter_model_warn_disabled_providers() {
  local value="${1:-}"
  local file provider state route
  local -a routes

  file="$(_walter_model_capabilities_file)"
  [[ -f "$file" ]] || return 0
  [[ -r "$file" ]] || return 0

  IFS=',' read -ra routes <<<"$value"
  for route in "${routes[@]}"; do
    provider="$(_walter_model_provider_for_route "$route")"
    [[ -n "$provider" && "$provider" != "none" ]] || continue

    state="$(_walter_model_yaml_value "$file" "provider_${provider}")"
    if [[ "$state" == "disabled" ]]; then
      echo "walter-model-router: WARN provider_${provider} is disabled in $file but route uses ${route}" >&2
    fi
  done
}

walter_model_phi_lock() {
  local configured="${WALTER_MODEL_PHI:-local-ollama}"
  if walter_model_value_valid "$configured" && _walter_model_all_routes_local "$configured"; then
    _walter_model_warn_disabled_providers "$configured"
    echo "$configured"
    return 0
  fi

  echo "walter-model-router: WARN WALTER_MODEL_PHI must point to a local model; using local-ollama" >&2
  _walter_model_warn_disabled_providers "local-ollama"
  echo "local-ollama"
}

walter_model_for() {
  local requested="${1:-default}"
  local key slug env_key configured fallback

  _walter_model_load_domain_rows || true
  key="$(_walter_model_domain_key "$requested")"
  slug="$(tr '[:upper:]' '[:lower:]' <<<"$key")"

  if [[ "$key" == "PHI" || "${WALTER_PHI_MODE:-0}" == "1" ]]; then
    export WALTER_MODEL_DOMAIN="phi"
    walter_model_phi_lock
    return 0
  fi

  export WALTER_MODEL_DOMAIN="$slug"

  if [[ -n "${WALTER_MODEL_OVERRIDE:-}" ]]; then
    if walter_model_value_valid "$WALTER_MODEL_OVERRIDE"; then
      _walter_model_warn_disabled_providers "$WALTER_MODEL_OVERRIDE"
      echo "$WALTER_MODEL_OVERRIDE"
      return 0
    fi
    echo "walter-model-router: WARN invalid WALTER_MODEL_OVERRIDE ignored" >&2
  fi

  env_key="$(walter_model_env_for "$requested")"
  configured="${!env_key:-}"
  fallback="$(walter_model_default_for "$requested")"

  if [[ -z "$configured" ]]; then
    _walter_model_warn_disabled_providers "$fallback"
    echo "$fallback"
    return 0
  fi

  if walter_model_value_valid "$configured"; then
    _walter_model_warn_disabled_providers "$configured"
    echo "$configured"
    return 0
  fi

  echo "walter-model-router: WARN invalid ${env_key} ignored; using ${fallback}" >&2
  _walter_model_warn_disabled_providers "$fallback"
  echo "$fallback"
}

walter_model_select_primary() {
  local requested="${1:-default}" var_name="${2:-WALTER_SELECTED_MODEL}"
  local tmp value primary

  [[ "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

  tmp="$(mktemp "${TMPDIR:-/tmp}/walter-model.XXXXXX")" || return 1
  walter_model_for "$requested" > "$tmp"
  value="$(cat "$tmp")"
  rm -f "$tmp"

  IFS=',' read -r primary _ <<<"$value"
  printf -v "$var_name" '%s' "$primary"
}

walter_model_resolve() {
  walter_model_select_primary "$@"
}

walter_models_print_effective() {
  local domain domains
  domains="$(walter_model_domains)" || return 1
  while IFS= read -r domain; do
    [[ -n "$domain" ]] || continue
    printf '  %s: %s\n' "$domain" "$(walter_model_for "$domain")"
  done <<<"$domains"
}
