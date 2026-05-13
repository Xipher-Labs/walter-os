#!/usr/bin/env bash
# scripts/walter/lib/providers/patch_mcp.sh
#
# Updates mcp/servers.json to enable/disable MCP entries based on
# provider selection. Uses jq for JSON editing.
# Sourced by providers.sh.

# MCP server name mappings per category.
# Format: "provider=mcp_server_key" (the key in servers.json .servers object).
# A category may have multiple MCPs (only the selected one gets disabled=false).

_mcp_servers_for_category() {
  local category="$1"
  case "$category" in
    project_management)
      echo "plane=plane linear=linear"
      ;;
    git)
      # github MCP is remote HTTP; forgejo uses tea CLI (no MCP entry in servers.json).
      # gitlab: not in current servers.json — skip.
      echo "github=github"
      ;;
    secrets)
      # bitwarden has an MCP entry; infisical/doppler/1password do not.
      echo "bitwarden=bitwarden"
      ;;
    web_analytics)
      # No analytics MCPs currently in servers.json — no-op.
      echo ""
      ;;
    search)
      # brave_search is the MCP key
      echo "brave=brave_search"
      ;;
    llm)
      # No MCP entries for LLM providers in servers.json — no-op.
      echo ""
      ;;
    embeddings)
      # No MCP entries for embedding providers — no-op.
      echo ""
      ;;
  esac
}

# patch_mcp_for_category <category> <selected_provider> <mcp_file>
#
# Sets disabled=true for non-selected provider MCPs and disabled=false
# for the selected provider MCP. Uses jq. Edits in-place via temp file.
patch_mcp_for_category() {
  local category="$1"
  local selected="$2"
  local mcp_file="$3"

  [[ -f "$mcp_file" ]] || return 0
  command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; return 1; }

  local mappings
  mappings="$(_mcp_servers_for_category "$category")"
  [[ -z "$mappings" ]] && return 0

  local tmp
  tmp="$(mktemp)"
  # Use RETURN (not EXIT) so cleanup is function-scoped and does not stomp
  # any pre-existing EXIT trap in the caller when this file is sourced.
  # Requires bash 4+ (already required by Walter-OS).
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}' '${tmp}.new'" RETURN

  # Apply each mapping as a separate jq pass so we can use --arg for the key,
  # preventing jq filter injection if mcp_key contains special characters.
  cp "$mcp_file" "$tmp"
  for mapping in $mappings; do
    local provider="${mapping%%=*}"
    local mcp_key="${mapping##*=}"

    # Only patch if the key exists in servers.json
    local exists
    exists="$(jq --arg k "$mcp_key" 'if .servers | has($k) then "yes" else "no" end' "$tmp")"
    [[ "$exists" != '"yes"' ]] && continue

    local flag
    if [[ "$provider" == "$selected" ]]; then
      flag="false"
    else
      flag="true"
    fi
    jq --arg key "$mcp_key" --argjson flag "$flag" \
      '.servers[$key].disabled = $flag' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
  done

  mv "$tmp" "$mcp_file"
}
