#!/usr/bin/env bash
# scripts/walter/subcommands/ai.sh
#
# Configure and inspect operator AI capability profiles.

set -euo pipefail

WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
AI_CAPABILITIES_FILE="${WALTER_AI_CAPABILITIES_FILE:-${WALTER_CONFIG}/ai-capabilities.yaml}"

usage() {
  cat <<'EOF'
walter ai — configure AI tool availability and routing

Usage:
  walter ai status
  walter ai validate [path/to/ai-capabilities.yaml]
  walter ai configure --profile <profile> [--set <capability>=<provider>...]
  walter ai --help

Profiles:
  claude-only   Route general work to Claude.
  codex-only    Route general work to Codex/OpenAI.
  gemini-only   Route general work to Gemini.
  local-only    Route every capability to Ollama/local.
  mixed         Claude + Codex + Copilot + Gemini + Ollama defaults.

Capabilities:
  code_review | infra_security_backend | planning | ux_ui |
  image_generation | research | compliance_local_only

Providers:
  claude | codex | copilot | gemini | ollama | none

The config is private operator metadata written to:
  ~/.config/walter-os/ai-capabilities.yaml

Validate an existing config with:
  walter ai validate
EOF
}

valid_profile() {
  case "${1:-}" in
    claude-only|codex-only|gemini-only|local-only|mixed) return 0 ;;
    *) return 1 ;;
  esac
}

valid_capability() {
  case "${1:-}" in
    code_review|infra_security_backend|planning|ux_ui|image_generation|research|compliance_local_only)
      return 0 ;;
    *) return 1 ;;
  esac
}

valid_provider_route() {
  local value="${1:-}" provider
  [[ -n "$value" ]] || return 1
  IFS=',' read -ra providers <<<"$value"
  for provider in "${providers[@]}"; do
    case "$provider" in
      claude|codex|copilot|gemini|ollama|none) ;;
      *) return 1 ;;
    esac
  done
}

enable_provider_from_route() {
  local value="${1:-}" provider
  IFS=',' read -ra providers <<<"$value"
  for provider in "${providers[@]}"; do
    case "$provider" in
      claude) provider_claude="enabled" ;;
      codex) provider_codex="enabled" ;;
      copilot) provider_copilot="enabled" ;;
      gemini) provider_gemini="enabled" ;;
      ollama) provider_ollama="enabled" ;;
    esac
  done
}

apply_profile_defaults() {
  local profile="$1"

  provider_claude="disabled"
  provider_codex="disabled"
  provider_copilot="disabled"
  provider_gemini="disabled"
  provider_ollama="disabled"

  route_code_review="none"
  route_infra_security_backend="none"
  route_planning="none"
  route_ux_ui="none"
  route_image_generation="none"
  route_research="none"
  route_compliance_local_only="none"

  case "$profile" in
    claude-only)
      provider_claude="enabled"
      route_code_review="claude"
      route_infra_security_backend="claude"
      route_planning="claude"
      route_ux_ui="claude"
      route_image_generation="none"
      route_research="claude"
      ;;
    codex-only)
      provider_codex="enabled"
      route_code_review="codex"
      route_infra_security_backend="codex"
      route_planning="codex"
      route_ux_ui="codex"
      route_research="codex"
      ;;
    gemini-only)
      provider_gemini="enabled"
      route_code_review="gemini"
      route_infra_security_backend="gemini"
      route_planning="gemini"
      route_ux_ui="gemini"
      route_image_generation="gemini"
      route_research="gemini"
      ;;
    local-only)
      provider_ollama="enabled"
      route_code_review="ollama"
      route_infra_security_backend="ollama"
      route_planning="ollama"
      route_ux_ui="ollama"
      route_image_generation="ollama"
      route_research="ollama"
      route_compliance_local_only="ollama"
      ;;
    mixed)
      provider_claude="enabled"
      provider_codex="enabled"
      provider_copilot="enabled"
      provider_gemini="enabled"
      provider_ollama="enabled"
      route_code_review="copilot,codex"
      route_infra_security_backend="codex"
      route_planning="claude"
      route_ux_ui="claude"
      route_image_generation="gemini"
      route_research="gemini"
      route_compliance_local_only="ollama"
      ;;
  esac
}

set_route_override() {
  local pair="$1" capability value
  capability="${pair%%=*}"
  value="${pair#*=}"
  if [[ "$capability" == "$pair" || -z "$capability" || -z "$value" ]]; then
    echo "walter ai configure: --set expects capability=provider" >&2
    exit 2
  fi
  if ! valid_capability "$capability"; then
    echo "walter ai configure: unknown capability: $capability" >&2
    exit 2
  fi
  if ! valid_provider_route "$value"; then
    echo "walter ai configure: invalid provider route: $value" >&2
    exit 2
  fi

  case "$capability" in
    code_review) route_code_review="$value" ;;
    infra_security_backend) route_infra_security_backend="$value" ;;
    planning) route_planning="$value" ;;
    ux_ui) route_ux_ui="$value" ;;
    image_generation) route_image_generation="$value" ;;
    research) route_research="$value" ;;
    compliance_local_only) route_compliance_local_only="$value" ;;
  esac
  enable_provider_from_route "$value"
}

write_capabilities() {
  mkdir -p "$(dirname "$AI_CAPABILITIES_FILE")"
  cat >"$AI_CAPABILITIES_FILE" <<YAML
# ai-capabilities.yaml — Walter-OS operator AI capability profile
# Generated by: walter ai configure
# Contains provider availability metadata only. Do not store secrets here.
profile: ${profile}
provider_claude: ${provider_claude}
provider_codex: ${provider_codex}
provider_copilot: ${provider_copilot}
provider_gemini: ${provider_gemini}
provider_ollama: ${provider_ollama}
route_code_review: ${route_code_review}
route_infra_security_backend: ${route_infra_security_backend}
route_planning: ${route_planning}
route_ux_ui: ${route_ux_ui}
route_image_generation: ${route_image_generation}
route_research: ${route_research}
route_compliance_local_only: ${route_compliance_local_only}
YAML
  chmod 600 "$AI_CAPABILITIES_FILE"
}

yaml_value() {
  local key="$1"
  [[ -f "$AI_CAPABILITIES_FILE" ]] || return 0
  ai_yaml_value "$AI_CAPABILITIES_FILE" "$key"
}

ai_yaml_value() {
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

normalize_provider_route() {
  local route="$1"
  route="${route//[[:space:]]/}"
  printf '%s\n' "$route"
}

detected_provider() {
  local provider="$1"
  case "$provider" in
    claude)
      command -v claude >/dev/null 2>&1 || [[ -n "${ANTHROPIC_API_KEY:-}${ANTHROPIC_ENTERPRISE_KEY:-}" ]] ;;
    codex)
      command -v codex >/dev/null 2>&1 || [[ -n "${OPENAI_API_KEY:-}" ]] ;;
    copilot)
      command -v gh >/dev/null 2>&1 && gh copilot --help >/dev/null 2>&1 ;;
    gemini)
      command -v gemini >/dev/null 2>&1 || [[ -n "${GEMINI_API_KEY:-}" ]] ;;
    ollama)
      command -v ollama >/dev/null 2>&1 || [[ -n "${OLLAMA_BASE_URL:-}" ]] ;;
  esac
}

print_provider_status() {
  local provider="$1" configured detected
  configured="$(yaml_value "provider_${provider}")"
  [[ -n "$configured" ]] || configured="unset"
  if detected_provider "$provider"; then
    detected="detected"
  else
    detected="missing"
  fi
  printf '  %-8s configured=%-8s detected=%s\n' "$provider" "$configured" "$detected"
}

print_route_status() {
  local capability="$1" value
  value="$(yaml_value "route_${capability}")"
  [[ -n "$value" ]] || value="unset"
  printf '  %-24s %s\n' "$capability" "$value"
}

cmd_status() {
  echo "AI capability status"
  if [[ -f "$AI_CAPABILITIES_FILE" ]]; then
    echo "config: $AI_CAPABILITIES_FILE"
  else
    echo "config: not found"
    echo "hint: run walter ai configure --profile mixed"
  fi

  echo
  echo "Providers:"
  print_provider_status claude
  print_provider_status codex
  print_provider_status copilot
  print_provider_status gemini
  print_provider_status ollama

  echo
  echo "Routes:"
  print_route_status code_review
  print_route_status infra_security_backend
  print_route_status planning
  print_route_status ux_ui
  print_route_status image_generation
  print_route_status research
  print_route_status compliance_local_only
}

cmd_configure() {
  profile=""
  local -a overrides=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          echo "walter ai configure: --profile requires a value" >&2
          exit 2
        fi
        profile="${2:-}"
        shift 2
        ;;
      --set)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          echo "walter ai configure: --set requires capability=provider" >&2
          exit 2
        fi
        overrides+=("${2:-}")
        shift 2
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        echo "walter ai configure: unknown option: $1" >&2
        exit 2
        ;;
    esac
  done

  if [[ -z "$profile" ]]; then
    echo "walter ai configure: --profile is required" >&2
    usage >&2
    exit 2
  fi
  if ! valid_profile "$profile"; then
    echo "walter ai configure: unknown profile: $profile" >&2
    exit 2
  fi

  apply_profile_defaults "$profile"
  if ((${#overrides[@]} > 0)); then
    for override in "${overrides[@]}"; do
      set_route_override "$override"
    done
  fi
  write_capabilities

  echo "AI capability profile written: $AI_CAPABILITIES_FILE"
  echo "profile: $profile"
}

validate_capabilities_file() {
  local file="$1" key value invalid=0 line_no=0
  local -a required_keys=(
    profile
    provider_claude
    provider_codex
    provider_copilot
    provider_gemini
    provider_ollama
    route_code_review
    route_infra_security_backend
    route_planning
    route_ux_ui
    route_image_generation
    route_research
    route_compliance_local_only
  )

  if [[ ! -f "$file" ]]; then
    echo "walter ai validate: config not found: $file" >&2
    return 1
  fi
  if [[ ! -r "$file" ]]; then
    echo "walter ai validate: config not readable: $file" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*[a-z_]+[[:space:]]*:[[:space:]]*[^[:space:]].*$ ]]; then
      echo "walter ai validate: invalid YAML at line $line_no" >&2
      invalid=1
    fi
  done <"$file"

  for key in "${required_keys[@]}"; do
    value="$(ai_yaml_value "$file" "$key")"
    if [[ -z "$value" ]]; then
      echo "walter ai validate: missing required key: $key" >&2
      invalid=1
    fi
  done

  value="$(ai_yaml_value "$file" profile)"
  if [[ -n "$value" ]] && ! valid_profile "$value"; then
    echo "walter ai validate: invalid profile; expected claude-only, codex-only, local-only, or mixed" >&2
    invalid=1
  fi

  for key in provider_claude provider_codex provider_copilot provider_gemini provider_ollama; do
    value="$(ai_yaml_value "$file" "$key")"
    case "$value" in
      enabled|disabled|"") ;;
      *)
        echo "walter ai validate: invalid $key; expected enabled or disabled" >&2
        invalid=1
        ;;
    esac
  done

  for key in route_code_review route_infra_security_backend route_planning route_ux_ui route_image_generation route_research route_compliance_local_only; do
    value="$(normalize_provider_route "$(ai_yaml_value "$file" "$key")")"
    if [[ -n "$value" ]] && ! valid_provider_route "$value"; then
      echo "walter ai validate: invalid $key; expected comma-separated providers from claude, codex, copilot, gemini, or ollama" >&2
      invalid=1
    fi
  done

  [[ "$invalid" -eq 0 ]]
}

cmd_validate() {
  local file="${1:-$AI_CAPABILITIES_FILE}"
  if [[ $# -gt 1 ]]; then
    echo "walter ai validate: expected zero or one path argument" >&2
    exit 2
  fi

  if validate_capabilities_file "$file"; then
    echo "AI capability config valid: $file"
  else
    exit 1
  fi
}

cmd="${1:-status}"
shift || true

case "$cmd" in
  status) cmd_status "$@" ;;
  validate) cmd_validate "$@" ;;
  configure) cmd_configure "$@" ;;
  -h|--help|help) usage ;;
  *)
    echo "walter ai: unknown subcommand: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
