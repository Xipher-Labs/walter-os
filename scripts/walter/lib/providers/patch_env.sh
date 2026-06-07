#!/usr/bin/env bash
# scripts/walter/lib/providers/patch_env.sh
#
# Patches .env.local based on provider selection.
# For the selected provider: ensures its env vars are present (uncommented).
# For non-selected providers in the same category: comments out their vars.
#
# Uses sed in-place (with .bak backup).
# Sourced by providers.sh.

# Save/restore the caller's `set -u` (nounset) shell option around our
# `declare -A` blocks. Bash 3.2 misparses `[key]=value` array assignments
# under set -u, so we have to disable it locally — but this file is
# SOURCED by providers.sh, so unconditionally turning set -u BACK on
# after the array would mutate the caller's shell options (a real
# regression flagged by Copilot R1 of #98). The save/restore pattern
# preserves whatever the caller had configured.
_walter_providers_nounset_save() {
  case $- in
    *u*) _WALTER_PROVIDERS_NOUNSET_WAS_ON=1 ;;
    *)   _WALTER_PROVIDERS_NOUNSET_WAS_ON=0 ;;
  esac
  set +u
}
_walter_providers_nounset_restore() {
  if [[ "${_WALTER_PROVIDERS_NOUNSET_WAS_ON:-0}" == "1" ]]; then
    set -u
  fi
  unset _WALTER_PROVIDERS_NOUNSET_WAS_ON
}

# _comment_out_var <varname> <file>
# Comments out a variable assignment line if it is currently uncommented.
_comment_out_var() {
  local varname="$1" file="$2"
  # Match lines like: VARNAME=... or VARNAME =... (no leading #)
  sed -i.bak "s|^\(${varname}=\)|#\1|g" "$file"
}

# _set_env_var <varname> <value> <file>
# Sets VAR=value in the env file. If the var already exists (commented or
# uncommented), updates it in-place. If it does not exist, appends it.
_set_env_var() {
  local varname="$1" value="$2" file="$3"
  if grep -q "^${varname}=" "$file"; then
    sed -i.bak "s|^${varname}=.*|${varname}=${value}|" "$file"
  elif grep -q "^#${varname}=" "$file"; then
    sed -i.bak "s|^#${varname}=.*|${varname}=${value}|" "$file"
  else
    echo "${varname}=${value}" >> "$file"
  fi
}

# _patch_vars <selected> <env_file> <providers_list> <varmap_name>
# Generic helper: uncomments vars for the selected provider; comments out
# vars for all other providers — but SKIPS commenting a var that is shared
# with the selected provider (preventing same-var double-patch).
#
# <varmap_name> is the name of an associative array declared by the caller
# (passed by name, accessed via nameref). Providers in <providers_list> that
# have no entry in the varmap are silently skipped (safe for "none" option).
_patch_vars() {
  local selected="$1" env_file="$2" providers_list="$3"
  local -n _varmap="$4"

  # Build the set of vars owned by the selected provider
  local -A _selected_vars=()
  local _sv
  for _sv in ${_varmap[$selected]:-}; do
    _selected_vars[$_sv]=1
  done

  local provider
  for provider in $providers_list; do
    local var
    if [[ "$provider" == "$selected" ]]; then
      for var in ${_varmap[$provider]:-}; do
        _uncomment_var "$var" "$env_file"
      done
    else
      for var in ${_varmap[$provider]:-}; do
        # Skip if this var is also owned by the selected provider
        [[ -n "${_selected_vars[$var]:-}" ]] && continue
        _comment_out_var "$var" "$env_file"
      done
    fi
  done
}

# _var_owned_by_llm_category <varname>
# Returns 0 (true) if the var is actively needed by the currently-selected
# LLM provider. Reads WALTER_LLM_PROVIDER env var (set by providers.sh before
# calling patch_env_for_category) or falls back to PROVIDERS_YAML.
# Used by the embeddings patcher to avoid commenting out cross-category vars
# (e.g. OPENAI_API_KEY used by llm=openai must not be commented when
# embeddings=nomic is selected).
_var_owned_by_llm_category() {
  local var="$1"
  local llm_choice="${WALTER_LLM_PROVIDER:-}"
  # Fall back to providers.yaml if env var not set
  if [[ -z "$llm_choice" && -n "${PROVIDERS_YAML:-}" && -f "${PROVIDERS_YAML}" ]]; then
    llm_choice="$(grep "^llm:" "${PROVIDERS_YAML}" | awk '{print $2}' | tr -d '"' || true)"
  fi
  # Check if this var belongs to the selected LLM provider
  case "${llm_choice}:${var}" in
    openai:OPENAI_API_KEY)   return 0 ;;
    gemini:GEMINI_API_KEY)   return 0 ;;
    ollama:OLLAMA_BASE_URL)  return 0 ;;
  esac
  return 1
}

# _uncomment_var <varname> <file>
# Removes a leading # from a commented-out variable assignment line.
_uncomment_var() {
  local varname="$1" file="$2"
  sed -i.bak "s|^#\(${varname}=\)|\1|g" "$file"
}

# patch_env_for_category <category> <selected_provider> <env_file>
#
# Comments out env vars for all non-selected providers in the category.
# Does NOT add new vars — only manages existing ones.
patch_env_for_category() {
  local category="$1"
  local selected="$2"
  local env_file="$3"

  [[ -f "$env_file" ]] || return 0

  # bash 3.2 (macOS default) misparses `[key]=value` array assignments
  # under `set -u` as a parameter expansion before recognizing the
  # array-assignment syntax. Wrap each `declare -A` block in
  # `set +u` / `set -u` so the script loads cleanly on every supported
  # bash. Same pattern as approval-gate.sh CATEGORY_MIN_TIER
  # (PR #68 P1-05 side fix) and providers.sh CATEGORY_LABELS.
  case "$category" in
    llm)
      _walter_providers_nounset_save
      declare -A llm_vars=(
        [litellm]="LITELLM_BASE_URL LITELLM_API_KEY"
        [anthropic]="ANTHROPIC_API_KEY ANTHROPIC_ENTERPRISE_KEY"
        [openai]="OPENAI_API_KEY"
        [gemini]="GEMINI_API_KEY"
        [ollama]="OLLAMA_BASE_URL"
      )
      _walter_providers_nounset_restore
      _patch_vars "$selected" "$env_file" "litellm anthropic openai gemini ollama" llm_vars
      ;;

    project_management)
      _walter_providers_nounset_save
      declare -A pm_vars=(
        [plane]="PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT"
        [plane_cloud]="PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT"
        [linear]="LINEAR_API_KEY"
      )
      _walter_providers_nounset_restore
      # plane and plane_cloud share vars; _patch_vars handles shared-var protection
      _patch_vars "$selected" "$env_file" "plane plane_cloud linear" pm_vars
      ;;

    git)
      _walter_providers_nounset_save
      declare -A git_vars=(
        [github]="GITHUB_TOKEN"
        [forgejo]="FORGEJO_URL FORGEJO_TOKEN"
        [gitlab]="GITLAB_TOKEN GITLAB_URL"
      )
      _walter_providers_nounset_restore
      _patch_vars "$selected" "$env_file" "github forgejo gitlab" git_vars
      # Write canonical GIT_PROVIDER identifier so scripts don't have to
      # infer the provider from which credential vars are set.
      if [[ "$selected" != "none" ]]; then
        _set_env_var "GIT_PROVIDER" "$selected" "$env_file"
      fi
      ;;

    secrets)
      _walter_providers_nounset_save
      declare -A secrets_vars=(
        [infisical]="INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET INFISICAL_API_URL"
        [doppler]="DOPPLER_TOKEN"
        [onepassword]="OP_ACCOUNT"
        [bitwarden]="BW_SESSION BW_SERVER"
      )
      _walter_providers_nounset_restore
      _patch_vars "$selected" "$env_file" "infisical doppler onepassword bitwarden" secrets_vars
      ;;

    web_analytics)
      _walter_providers_nounset_save
      declare -A analytics_vars=(
        [plausible]="PLAUSIBLE_API_KEY PLAUSIBLE_SITE_ID"
        [plausible_cloud]="PLAUSIBLE_API_KEY PLAUSIBLE_SITE_ID"
        [cloudflare]="CF_ANALYTICS_TOKEN"
        [ga4]="GA4_MEASUREMENT_ID GA4_API_SECRET"
      )
      _walter_providers_nounset_restore
      # plausible and plausible_cloud share vars; _patch_vars handles shared-var protection
      _patch_vars "$selected" "$env_file" "plausible plausible_cloud cloudflare ga4" analytics_vars
      ;;

    search)
      _walter_providers_nounset_save
      declare -A search_vars=(
        [brave]="BRAVE_API_KEY"
        [algolia]="ALGOLIA_API_KEY ALGOLIA_APP_ID"
      )
      _walter_providers_nounset_restore
      _patch_vars "$selected" "$env_file" "brave algolia" search_vars
      ;;

    embeddings)
      _walter_providers_nounset_save
      declare -A embed_vars=(
        [nomic]="OLLAMA_BASE_URL"
        [openai_ada]="OPENAI_API_KEY"
        [voyage]="VOYAGE_API_KEY"
      )
      _walter_providers_nounset_restore
      # OLLAMA_BASE_URL and OPENAI_API_KEY are shared with the llm category.
      # _var_owned_by_llm_category() reads WALTER_LLM_PROVIDER (set by
      # providers.sh before calling this function) to check whether the
      # currently-selected LLM provider owns the var. If it does, we skip
      # commenting it out, preventing cross-category clobbering.
      for provider in nomic openai_ada voyage; do
        if [[ "$provider" == "$selected" ]]; then
          for var in ${embed_vars[$provider]}; do
            _uncomment_var "$var" "$env_file"
          done
        else
          for var in ${embed_vars[$provider]}; do
            if ! _var_owned_by_llm_category "$var"; then
              _comment_out_var "$var" "$env_file"
            fi
          done
        fi
      done
      ;;
  esac

  # Remove backup files created by sed
  rm -f "${env_file}.bak"
}
