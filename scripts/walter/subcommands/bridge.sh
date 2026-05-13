#!/usr/bin/env bash
# scripts/walter/subcommands/bridge.sh
# Handler for: walter bridge {install|status|--help}
#
# Usage:
#   walter bridge install {claude-code-router|gemini-cli|codex-cli|all}
#   walter bridge status
#   walter bridge --help
#
# Refs: W-8-cli-clients

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-${HOME}/walter-os}"
CLIENTS_DIR="${WALTER_OS_HOME}/setup/walter-bridge/clients"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

bridge_help() {
  cat <<EOF
Usage: walter bridge <subcommand> [args]

Subcommands:
  install {claude-code-router|gemini-cli|codex-cli|all}
                  Render and install a CLI config via Walter-Bridge.
                  Requires: WALTER_DOMAIN and LITELLM_MASTER_KEY in env.
  status          Check which CLIs are wired to Walter-Bridge.
  --help          Show this help.

Examples:
  walter bridge install codex-cli
  walter bridge install all
  walter bridge status

Refs: W-8-cli-clients
      setup/walter-bridge/clients/README.md
EOF
}

# Validate that both required env vars are present.
# Fail loud with a pointer to personal.env if either is missing.
_require_env() {
  local missing=0
  if [[ -z "${WALTER_DOMAIN:-}" ]]; then
    echo "walter bridge: WALTER_DOMAIN is not set." >&2
    echo "  Set it in ~/.config/walter-os/overlay/personal.env and re-run." >&2
    missing=1
  fi
  if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
    echo "walter bridge: LITELLM_MASTER_KEY is not set." >&2
    echo "  Set it in ~/.config/walter-os/overlay/personal.env and re-run." >&2
    missing=1
  fi
  if [[ "$missing" -eq 1 ]]; then
    exit 2
  fi
}

# Render one template into its target path.
# Usage: _render_template <cli-name> <template-file> <target-file>
_render_one() {
  local cli="$1"
  local template="$2"
  local target="$3"

  if [[ ! -f "$template" ]]; then
    echo "walter bridge install: template not found: $template" >&2
    exit 3
  fi

  # Backup existing file if present.
  if [[ -f "$target" ]]; then
    local ts
    ts="$(date +%s)"
    local backup="${target}.bak.${ts}"
    cp "$target" "$backup"
    echo "  Backed up existing config to $backup"
  fi

  # Ensure target directory exists.
  mkdir -p "$(dirname "$target")"

  # Render via envsubst.
  envsubst < "$template" > "$target"
  echo "  Installed $cli config at $target"
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------

bridge_install() {
  _require_env

  local cli="${1:-}"
  if [[ -z "$cli" ]]; then
    echo "walter bridge install: CLI name required." >&2
    echo "  Usage: walter bridge install {claude-code-router|gemini-cli|codex-cli|all}" >&2
    exit 2
  fi

  case "$cli" in
    claude-code-router)
      _render_one "claude-code-router" \
        "${CLIENTS_DIR}/claude-code-router/config.template.json" \
        "${HOME}/.claude-code-router/config.json"
      ;;
    gemini-cli)
      _render_one "gemini-cli" \
        "${CLIENTS_DIR}/gemini-cli/settings.template.json" \
        "${HOME}/.gemini/settings.json"
      ;;
    codex-cli)
      _render_one "codex-cli" \
        "${CLIENTS_DIR}/codex-cli/config.template.toml" \
        "${HOME}/.codex/config.toml"
      ;;
    all)
      _render_one "claude-code-router" \
        "${CLIENTS_DIR}/claude-code-router/config.template.json" \
        "${HOME}/.claude-code-router/config.json"
      _render_one "gemini-cli" \
        "${CLIENTS_DIR}/gemini-cli/settings.template.json" \
        "${HOME}/.gemini/settings.json"
      _render_one "codex-cli" \
        "${CLIENTS_DIR}/codex-cli/config.template.toml" \
        "${HOME}/.codex/config.toml"
      ;;
    *)
      echo "walter bridge install: unknown CLI '$cli'." >&2
      echo "  Valid: claude-code-router | gemini-cli | codex-cli | all" >&2
      exit 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

bridge_status() {
  # Marker string that should appear in a correctly-rendered config.
  # After envsubst, ${WALTER_DOMAIN} is replaced with the actual domain.
  # We check for "llm." as an anchor that exists in all three rendered templates
  # regardless of what WALTER_DOMAIN was set to.
  local marker="llm."

  _check_cli() {
    local label="$1"
    local cfg="$2"
    if [[ ! -f "$cfg" ]]; then
      printf "  %-22s %s\n" "$label:" "not installed"
    elif grep -q "$marker" "$cfg" 2>/dev/null; then
      printf "  %-22s %s\n" "$label:" "wired"
    else
      printf "  %-22s %s\n" "$label:" "installed but not pointing at Walter-Bridge"
    fi
  }

  echo "Walter-Bridge routing status:"
  _check_cli "claude-code-router" "${HOME}/.claude-code-router/config.json"
  _check_cli "gemini-cli"         "${HOME}/.gemini/settings.json"
  _check_cli "codex-cli"          "${HOME}/.codex/config.toml"
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  install) shift; bridge_install "$@" ;;
  status)  shift; bridge_status "$@" ;;
  --help|-h|help) bridge_help ;;
  "") bridge_help; exit 0 ;;
  *)
    echo "walter bridge: unknown subcommand '${1}'." >&2
    echo "  Usage: walter bridge {install|status} [args]" >&2
    exit 2
    ;;
esac
