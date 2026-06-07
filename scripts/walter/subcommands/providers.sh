#!/usr/bin/env bash
# scripts/walter/subcommands/providers.sh
#
# walter providers configure — interactive provider choice wizard.
#
# Usage:
#   walter providers configure [--category <cat>]
#   walter providers configure --help
#
# Categories: llm | project_management | git | secrets | web_analytics | search | embeddings

# Requires bash >= 4 (associative arrays). macOS ships bash 3.2 as
# /bin/bash; if invoked under that, re-exec under a newer bash (Homebrew
# or /usr/local) so the operator doesn't get a `declare: -A: invalid
# option` error on first invocation. Same pattern as bash-denylist.sh
# bash-3.2 re-exec. One-shot guard prevents infinite loop if the
# candidate path ALSO resolves to bash < 4.
if [[ -n "${BASH_VERSION:-}" && "${BASH_VERSION%%.*}" -lt 4 ]]; then
  if [[ "${WALTER_PROVIDERS_REEXEC:-0}" == "1" ]]; then
    echo "walter providers: re-exec landed on bash < 4 again. Install GNU bash >= 4 (brew install bash)." >&2
    exit 3
  fi
  _self="${BASH_SOURCE[0]}"
  for _candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_candidate" && -f "$_self" ]]; then
      WALTER_PROVIDERS_REEXEC=1 exec "$_candidate" "$_self" "$@"
    fi
  done
  echo "walter providers: requires bash >= 4 (macOS /bin/bash 3.2 doesn't support associative arrays). Install GNU bash: brew install bash" >&2
  exit 3
fi

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
WALTER_LIB="${WALTER_OS_HOME}/scripts/walter"
PROVIDERS_LIB="${WALTER_LIB}/lib/providers"
PROVIDERS_CONFIG_DIR="${HOME}/.config/walter-os"
PROVIDERS_YAML="${PROVIDERS_YAML:-${PROVIDERS_CONFIG_DIR}/providers.yaml}"
MCP_FILE="${WALTER_MCP_FILE:-${WALTER_OS_HOME}/mcp/servers.json}"
# WALTER_ENV_LOCAL allows tests (and advanced operators) to override the
# .env.local path without changing WALTER_OS_HOME.
_ENV_LOCAL_OVERRIDE="${WALTER_ENV_LOCAL:-}"

# Load lib helpers
# shellcheck source=/dev/null
source "${WALTER_LIB}/lib/log.sh"
# shellcheck source=/dev/null
source "${WALTER_LIB}/lib/prompt.sh"
# shellcheck source=/dev/null
source "${PROVIDERS_LIB}/detect.sh"
# shellcheck source=/dev/null
source "${PROVIDERS_LIB}/apply.sh"
# shellcheck source=/dev/null
source "${PROVIDERS_LIB}/patch_env.sh"
# shellcheck source=/dev/null
source "${PROVIDERS_LIB}/patch_mcp.sh"

# ---------------------------------------------------------------------------
# Metadata: display names and ordered options per category
# ---------------------------------------------------------------------------
# bash 3.2 (macOS default) misparses `[key-with-letters]=value` under
# `set -u` as a `${key}` parameter expansion before recognizing the
# array-assignment syntax, which then fires "unbound variable" on the
# bare token. Same bug pattern as approval-gate.sh CATEGORY_MIN_TIER
# (PR #68 P1-05 side-fix). Wrap the assignment in `set +u`/`set -u`
# so the script loads cleanly on every bash we support. bash 4+
# accepts both forms identically.
set +u
declare -A CATEGORY_LABELS=(
  [llm]="LLM Gateway"
  [project_management]="Project Management"
  [git]="Git Provider"
  [secrets]="Secrets Manager"
  [web_analytics]="Web Analytics"
  [search]="Search"
  [embeddings]="Embeddings"
)
set -u

CATEGORY_ORDER=(llm project_management git secrets web_analytics search embeddings)

# Options per category: "slug:Label" pairs.
# Same bash-3.2-under-`set -u` workaround as CATEGORY_LABELS above.
set +u
declare -A CATEGORY_OPTIONS=(
  [llm]="litellm:LiteLLM-proxy-all (self-host)|anthropic:Direct Anthropic|openai:Direct OpenAI|gemini:Direct Gemini|ollama:Ollama local"
  [project_management]="plane:Plane self-host|linear:Linear|plane_cloud:Plane cloud|none:None"
  [git]="forgejo:Forgejo self-host|github:GitHub|gitlab:GitLab"
  [secrets]="infisical:Infisical self-host|doppler:Doppler|onepassword:1Password CLI|bitwarden:Bitwarden CLI|none:None"
  [web_analytics]="plausible:Plausible self-host|plausible_cloud:Plausible cloud|cloudflare:Cloudflare Web Analytics|ga4:GA4|none:None"
  [search]="brave:Brave Search API|algolia:Algolia|none:None"
  [embeddings]="nomic:nomic-embed-text local (Ollama)|openai_ada:OpenAI ada-002|voyage:Voyage AI|none:None"
)
set -u

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat << 'EOF'
walter providers configure — interactive provider choice wizard

Usage:
  walter providers configure [--category <cat>]
  walter providers configure --help

Options:
  --category <cat>   Reconfigure only one category. Choices:
                       llm | project_management | git | secrets |
                       web_analytics | search | embeddings
  --help, -h         Show this help

The wizard auto-detects configured providers via env vars, presents
numbered menus, and writes the result to:
  ~/.config/walter-os/providers.yaml   (provider selections)
  .env.local                            (env var activation)
  mcp/servers.json                      (MCP enable/disable)

Walter can run with any configured LLM provider; Claude and Codex are
supported agent tools, not hard requirements. Use the LLM category to
select LiteLLM, Anthropic/Claude, OpenAI/Codex/GPT, Gemini, or Ollama/local.
EOF
}

# ---------------------------------------------------------------------------
# Load existing providers.yaml (if present) for pre-selection
# ---------------------------------------------------------------------------
load_current_selection() {
  local category="$1"
  [[ -f "$PROVIDERS_YAML" ]] || return 0
  grep "^${category}:" "$PROVIDERS_YAML" | awk '{print $2}' | tr -d '"' || true
}

# ---------------------------------------------------------------------------
# Prompt for a single category
# ---------------------------------------------------------------------------
prompt_category() {
  local category="$1"
  local label="${CATEGORY_LABELS[$category]}"
  local options_str="${CATEGORY_OPTIONS[$category]}"
  local detected
  detected="$(detect_provider "$category")"
  local current
  current="$(load_current_selection "$category")"

  # All display output goes to stderr so stdout carries only the slug result.
  log_step "$label" >&2

  # Build arrays from pipe-delimited "slug:Label" string
  local slugs=()
  local labels=()
  IFS='|' read -ra pairs <<< "$options_str"
  for pair in "${pairs[@]}"; do
    local slug="${pair%%:*}"
    local lbl="${pair#*:}"
    slugs+=("$slug")
    local suffix=""
    if [[ "$slug" == "$detected" ]]; then
      suffix=" (detected)"
    fi
    if [[ "$slug" == "$current" && -z "$detected" ]]; then
      suffix=" (current)"
    fi
    labels+=("${lbl}${suffix}")
  done

  # Non-interactive (piped) mode: read from stdin directly
  local choice_idx=0

  if [[ ! -t 0 ]]; then
    # Non-interactive: read a single line (1-based index or slug)
    read -r user_input
    # If it's a number, treat as index
    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
      choice_idx=$(( user_input - 1 ))
    else
      # Treat as slug — keep default 0 if not found
      for i in "${!slugs[@]}"; do
        if [[ "${slugs[$i]}" == "$user_input" ]]; then
          choice_idx=$i; break
        fi
      done
    fi
    # Safe fallback: clamp to valid range (unknown slug or OOB index → first)
    echo "${slugs[$choice_idx]:-${slugs[0]}}"
    return
  fi

  # Interactive mode: numbered menu — display on stderr
  for i in "${!labels[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${labels[$i]}" >&2
  done

  # Default: detected > current > first option
  local default_idx=0
  if [[ -n "$detected" ]]; then
    for i in "${!slugs[@]}"; do
      [[ "${slugs[$i]}" == "$detected" ]] && default_idx=$i && break
    done
  elif [[ -n "$current" ]]; then
    for i in "${!slugs[@]}"; do
      [[ "${slugs[$i]}" == "$current" ]] && default_idx=$i && break
    done
  fi

  local prompt_str="Select [1-${#slugs[@]}] (default: $((default_idx+1))): "
  read -r -p "$prompt_str" raw_choice </dev/tty || raw_choice=""
  if [[ -z "$raw_choice" ]]; then
    choice_idx=$default_idx
  elif [[ "$raw_choice" =~ ^[0-9]+$ ]]; then
    choice_idx=$(( raw_choice - 1 ))
  else
    choice_idx=$default_idx
  fi

  # Safe fallback: if choice_idx is OOB (-1, > N-1), default to first slug
  # rather than crashing under set -u or returning the last array element
  # (bash 4.2+ silently maps negative indices to the end).
  echo "${slugs[$choice_idx]:-${slugs[0]}}"
}

# ---------------------------------------------------------------------------
# Main wizard logic
# ---------------------------------------------------------------------------
providers_configure() {
  local only_category=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category) only_category="${2:-}"; shift 2 ;;
      --help|-h)  usage; exit 0 ;;
      configure)  shift ;;  # consumed by bin/walter dispatch
      *)          log_err "Unknown option: $1"; usage; exit 2 ;;
    esac
  done

  mkdir -p "$PROVIDERS_CONFIG_DIR"

  # Load existing selections as defaults
  declare -A selections=()
  for cat in "${CATEGORY_ORDER[@]}"; do
    selections[$cat]="$(load_current_selection "$cat")"
  done

  # Determine which categories to configure
  local to_configure=()
  if [[ -n "$only_category" ]]; then
    # Validate the category
    local valid=0
    for cat in "${CATEGORY_ORDER[@]}"; do
      [[ "$cat" == "$only_category" ]] && valid=1 && break
    done
    if [[ $valid -eq 0 ]]; then
      log_err "Unknown category: '$only_category'"
      log_err "Valid categories: ${CATEGORY_ORDER[*]}"
      exit 2
    fi
    to_configure=("$only_category")
  else
    to_configure=("${CATEGORY_ORDER[@]}")
  fi

  log_step "Walter-OS Provider Configuration"
  log_info "Walk through each category and select your preferred provider."
  log_info "Providers detected from your current env are marked (detected)."
  echo

  # Run wizard for each category
  for cat in "${to_configure[@]}"; do
    selected="$(prompt_category "$cat")"
    selections[$cat]="$selected"
  done

  # For categories not being reconfigured, keep existing or default to template value
  if [[ -n "$only_category" ]]; then
    # Fill in any category not in selections from existing providers.yaml
    for cat in "${CATEGORY_ORDER[@]}"; do
      if [[ -z "${selections[$cat]:-}" ]]; then
        local existing
        existing="$(load_current_selection "$cat")"
        if [[ -n "$existing" ]]; then
          selections[$cat]="$existing"
        else
          # Fall back to template defaults
          case "$cat" in
            llm)                selections[$cat]="litellm" ;;
            project_management) selections[$cat]="plane" ;;
            git)                selections[$cat]="forgejo" ;;
            secrets)            selections[$cat]="infisical" ;;
            web_analytics)      selections[$cat]="plausible" ;;
            search)             selections[$cat]="brave" ;;
            embeddings)         selections[$cat]="nomic" ;;
          esac
        fi
      fi
    done
  fi

  # Show planned changes diff
  echo
  log_step "Planned changes"
  echo "providers.yaml will be written to: $PROVIDERS_YAML"
  for cat in "${CATEGORY_ORDER[@]}"; do
    local current
    current="$(load_current_selection "$cat")"
    local new="${selections[$cat]}"
    if [[ "$current" != "$new" ]]; then
      log_info "  ${CATEGORY_LABELS[$cat]}: ${current:-<unset>} → ${new}"
    else
      log_dim "  ${CATEGORY_LABELS[$cat]}: ${new} (unchanged)"
    fi
  done

  echo
  # In non-interactive mode, auto-apply
  if [[ -t 0 ]]; then
    read -r -p "Press Enter to apply or Ctrl-C to abort..." </dev/tty
  fi

  # Write providers.yaml
  write_providers_yaml \
    "${selections[llm]}" \
    "${selections[project_management]}" \
    "${selections[git]}" \
    "${selections[secrets]}" \
    "${selections[web_analytics]}" \
    "${selections[search]}" \
    "${selections[embeddings]}" \
    "$PROVIDERS_YAML"
  log_ok "providers.yaml written."

  # Patch .env.local if it exists
  local env_local="${_ENV_LOCAL_OVERRIDE:-${WALTER_OS_HOME}/.env.local}"
  if [[ -f "$env_local" ]]; then
    # Export LLM provider so the embeddings patcher can avoid clobbering
    # cross-category vars (e.g. OPENAI_API_KEY owned by llm=openai).
    export WALTER_LLM_PROVIDER="${selections[llm]:-}"
    for cat in "${to_configure[@]}"; do
      patch_env_for_category "$cat" "${selections[$cat]}" "$env_local"
    done
    unset WALTER_LLM_PROVIDER
    log_ok ".env.local updated."
  else
    log_warn ".env.local not found — skipping env var patching."
    log_dim "  Copy .env.example to .env.local and re-run to activate."
  fi

  # Patch mcp/servers.json
  if [[ -f "$MCP_FILE" ]]; then
    for cat in "${to_configure[@]}"; do
      patch_mcp_for_category "$cat" "${selections[$cat]}" "$MCP_FILE"
    done
    log_ok "mcp/servers.json updated."
  else
    log_warn "mcp/servers.json not found at $MCP_FILE — skipping MCP patching."
  fi

  # Ollama post-config note [AC-6]
  if [[ "${selections[embeddings]}" == "nomic" ]]; then
    echo
    print_ollama_note
  fi

  echo
  log_ok "Provider configuration complete."
  log_info "Next: run 'walter ai configure --profile mixed' or 'walter ai status' to declare which AI tools are actually available."
}

# ---------------------------------------------------------------------------
# Entrypoint: handle subcommand dispatch from bin/walter
# ---------------------------------------------------------------------------
sub="${1:-}"
case "$sub" in
  configure|"")
    shift || true
    providers_configure "$@"
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    log_err "walter providers: unknown subcommand '$sub'"
    log_err "Usage: walter providers configure [--category <cat>]"
    exit 2
    ;;
esac
