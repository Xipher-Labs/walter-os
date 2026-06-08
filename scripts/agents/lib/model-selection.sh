#!/usr/bin/env bash
# scripts/agents/lib/model-selection.sh — safe Council model selection.
#
# The Walter model router returns LiteLLM-style aliases. Agent runners may also
# run against the direct Anthropic endpoint, where aliases such as codex/claude
# are not valid model IDs. This helper keeps that boundary explicit.

# shellcheck disable=SC2034
WALTER_AGENT_MODEL_SELECTION_LIB_VERSION=1

walter_agent_litellm_configured() {
  [[ -n "${LITELLM_BASE_URL:-}" && -n "${LITELLM_API_KEY:-}" ]]
}

walter_agent_anthropic_model_compatible() {
  case "${1:-}" in
    cheap|haiku|sonnet|opus|claude-*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_walter_agent_model_env_hint() {
  case "${1:-default}" in
    backend|backend-review|backend_review|security|review)
      echo "WALTER_MODEL_BACKEND_REVIEW" ;;
    frontend|front-end|ui|ux|design)
      echo "WALTER_MODEL_FRONTEND" ;;
    longform|long-form|writing|content)
      echo "WALTER_MODEL_LONGFORM" ;;
    quick|quick-refactor|quick_refactor|refactor)
      echo "WALTER_MODEL_QUICK_REFACTOR" ;;
    phi|medical|health|local)
      echo "WALTER_MODEL_PHI" ;;
    brainstorm|brainstorming|plan|planning|research)
      echo "WALTER_MODEL_BRAINSTORM" ;;
    *)
      echo "WALTER_MODEL_DEFAULT" ;;
  esac
}

walter_agent_select_model() {
  local domain="${1:-default}" var_name="${2:-WALTER_AGENT_SELECTED_MODEL}" fallback="${3:-}"
  local router_sh="${WALTER_MODEL_ROUTER_SH:-}"
  local model env_hint

  if [[ -z "$router_sh" && -n "${WALTER_OS_HOME:-}" ]]; then
    router_sh="$WALTER_OS_HOME/scripts/walter/lib/model-router.sh"
  fi

  if [[ -z "$router_sh" || ! -f "$router_sh" ]]; then
    echo "agents/model-selection.sh: model router not found at ${router_sh:-<unset>}." >&2
    return 3
  fi

  # shellcheck disable=SC1090,SC1091
  source "$router_sh"
  walter_model_select_primary "$domain" model || {
    echo "agents/model-selection.sh: failed to select model for domain '${domain}'." >&2
    return 3
  }

  if ! walter_agent_litellm_configured && ! walter_agent_anthropic_model_compatible "$model"; then
    if [[ -n "$fallback" && "$fallback" != "$model" ]] && walter_agent_anthropic_model_compatible "$fallback"; then
      echo "agents/model-selection.sh: WARN model '${model}' for domain '${domain}' requires LiteLLM; using '${fallback}'." >&2
      model="$fallback"
    else
      env_hint="$(_walter_agent_model_env_hint "$domain")"
      echo "agents/model-selection.sh: model '${model}' for domain '${domain}' requires LiteLLM." >&2
      echo "agents/model-selection.sh: set LITELLM_BASE_URL and LITELLM_API_KEY, or set ${env_hint}=sonnet for direct Anthropic." >&2
      return 3
    fi
  fi

  if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "agents/model-selection.sh: invalid output variable name '${var_name}'." >&2
    return 3
  fi
  printf -v "$var_name" '%s' "$model"
}
