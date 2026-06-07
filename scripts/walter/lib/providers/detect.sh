#!/usr/bin/env bash
# scripts/walter/lib/providers/detect.sh
#
# Auto-detect configured providers by checking environment variables.
# Sourced by wizard.sh and providers.sh.
#
# Usage:
#   source detect.sh
#   detected="$(detect_provider git)"  # returns slug or empty string

# detect_provider <category>
# Returns the detected provider slug for the given category, or empty string.
detect_provider() {
  local category="$1"
  case "$category" in
    llm)
      # LiteLLM takes priority (it proxies others).
      # Both LITELLM_BASE_URL and LITELLM_API_KEY are required — scripts/agents/lib/llm.sh
      # needs the base URL to route requests; a key alone is insufficient.
      if [[ -n "${LITELLM_BASE_URL:-}" && -n "${LITELLM_API_KEY:-}" ]]; then
        echo "litellm"; return
      fi
      if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${ANTHROPIC_ENTERPRISE_KEY:-}" ]]; then
        echo "anthropic"; return
      fi
      if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo "openai"; return
      fi
      if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        echo "gemini"; return
      fi
      if [[ -n "${OLLAMA_BASE_URL:-}" ]]; then
        echo "ollama"; return
      fi
      ;;
    project_management)
      if [[ -n "${PLANE_API_TOKEN:-}" ]]; then
        echo "plane"; return
      fi
      if [[ -n "${LINEAR_API_KEY:-}" ]]; then
        echo "linear"; return
      fi
      ;;
    git)
      # GitHub wins if GITHUB_TOKEN is set (most common cloud case)
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "github"; return
      fi
      if [[ -n "${FORGEJO_TOKEN:-}" || -n "${FORGEJO_URL:-}" ]]; then
        echo "forgejo"; return
      fi
      if [[ -n "${GITLAB_TOKEN:-}" || -n "${GITLAB_URL:-}" ]]; then
        echo "gitlab"; return
      fi
      ;;
    secrets)
      if [[ -n "${INFISICAL_CLIENT_ID:-}" ]]; then
        echo "infisical"; return
      fi
      if [[ -n "${DOPPLER_TOKEN:-}" ]]; then
        echo "doppler"; return
      fi
      if [[ -n "${OP_ACCOUNT:-}" ]]; then
        echo "onepassword"; return
      fi
      if [[ -n "${BW_SESSION:-}" ]]; then
        echo "bitwarden"; return
      fi
      ;;
    web_analytics)
      if [[ -n "${PLAUSIBLE_API_KEY:-}" && -n "${PLAUSIBLE_SITE_ID:-}" ]]; then
        # Distinguish cloud vs self-host via PLAUSIBLE_API_URL
        if [[ "${PLAUSIBLE_API_URL:-}" == *"plausible.io"* ]]; then
          echo "plausible_cloud"; return
        fi
        echo "plausible"; return
      fi
      if [[ -n "${CF_ANALYTICS_TOKEN:-}" ]]; then
        echo "cloudflare"; return
      fi
      if [[ -n "${GA4_MEASUREMENT_ID:-}" ]]; then
        echo "ga4"; return
      fi
      ;;
    search)
      if [[ -n "${BRAVE_API_KEY:-}" ]]; then
        echo "brave"; return
      fi
      if [[ -n "${ALGOLIA_API_KEY:-}" ]]; then
        echo "algolia"; return
      fi
      ;;
    embeddings)
      if [[ -n "${OLLAMA_BASE_URL:-}" ]]; then
        echo "nomic"; return
      fi
      if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo "openai_ada"; return
      fi
      if [[ -n "${VOYAGE_API_KEY:-}" ]]; then
        echo "voyage"; return
      fi
      ;;
  esac
  echo ""
}

# detect_all_providers
# Returns a newline-separated key=value list for all 7 categories.
detect_all_providers() {
  for cat in llm project_management git secrets web_analytics search embeddings; do
    local detected
    detected="$(detect_provider "$cat")"
    echo "${cat}=${detected}"
  done
}
