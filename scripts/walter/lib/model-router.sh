#!/usr/bin/env bash
# scripts/walter/lib/model-router.sh
#
# Domain-based model routing for Walter-OS skills and agents.
# Source this file, then call:
#   walter_model_for <backend_review|frontend|longform|quick_refactor|phi|brainstorm|default>
#
# Values are LiteLLM-style aliases. A comma-separated value means the caller may
# fan out to multiple models and merge the outputs.

# shellcheck disable=SC2034 # used by sourced callers
WALTER_MODEL_ROUTER_VERSION=1

_walter_model_domain_key() {
  case "${1:-default}" in
    backend|backend-review|backend_review|security|review)
      echo "BACKEND_REVIEW" ;;
    frontend|front-end|ui|ux|design)
      echo "FRONTEND" ;;
    longform|long-form|writing|content)
      echo "LONGFORM" ;;
    quick|quick-refactor|quick_refactor|refactor)
      echo "QUICK_REFACTOR" ;;
    phi|medical|health|local)
      echo "PHI" ;;
    brainstorm|brainstorming|plan|planning|research)
      echo "BRAINSTORM" ;;
    default|"")
      echo "DEFAULT" ;;
    *)
      echo "DEFAULT" ;;
  esac
}

_walter_model_domain_slug() {
  tr '[:upper:]' '[:lower:]' <<<"$(_walter_model_domain_key "$1")"
}

walter_model_default_for() {
  case "$(_walter_model_domain_key "${1:-default}")" in
    BACKEND_REVIEW)  echo "codex" ;;
    FRONTEND)        echo "claude" ;;
    LONGFORM)        echo "claude" ;;
    QUICK_REFACTOR)  echo "codex" ;;
    PHI)             echo "local-ollama" ;;
    BRAINSTORM)      echo "claude,codex" ;;
    DEFAULT|*)       echo "claude" ;;
  esac
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

  case "$route" in
    claude|haiku|sonnet|opus|claude-*|anthropic/*|openrouter/claude*)
      echo "claude" ;;
    codex|codex-*|gpt|gpt-*|openai/*)
      echo "codex" ;;
    gemini|gemini-*|cheap|nanobanana|google/*)
      echo "gemini" ;;
    local|local-*|local/*|ollama|ollama/*|ollama:*|localhost:[0-9]*|127.0.0.1:[0-9]*|'[::1]:'[0-9]*)
      echo "ollama" ;;
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

  key="$(_walter_model_domain_key "$requested")"
  slug="$(_walter_model_domain_slug "$requested")"

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

  env_key="WALTER_MODEL_${key}"
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

walter_models_print_effective() {
  local domain
  for domain in backend_review frontend longform quick_refactor phi brainstorm default; do
    printf '  %s: %s\n' "$domain" "$(walter_model_for "$domain")"
  done
}
