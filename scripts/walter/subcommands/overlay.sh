#!/usr/bin/env bash
# scripts/walter/subcommands/overlay.sh
# Open the Walter-OS personal overlay with the configured overlay opener.

set -euo pipefail

overlay_usage() {
  cat <<'EOF'
Usage: walter-os overlay [--print]
       walter overlay [--print]

Open ~/.config/walter-os/overlay with the configured overlay opener,
in this preference order:
  1. WALTER_OVERLAY_OPEN_CMD
  2. WALTER_OVERLAY_EDITOR
  3. System opener (platform-native)
  4. VISUAL
  5. EDITOR

WALTER_OVERLAY_EDITOR may be: system, cursor, code, zed, vim, nvim,
or an executable path. WALTER_OVERLAY_OPEN_CMD is an advanced override
and may include simple whitespace-separated arguments.

The system opener is platform-native: macOS open, Linux xdg-open, and
WSL explorer.exe when available.

Options:
  --print      Print the overlay path without opening it.
  -h, --help   Show this help.
EOF
}

resolve_overlay_dir() {
  if [[ -n "${WALTER_OVERLAY_DIR:-}" ]]; then
    printf '%s\n' "$WALTER_OVERLAY_DIR"
    return 0
  fi

  if [[ -z "${HOME:-}" ]]; then
    echo "walter-os overlay: HOME is required unless WALTER_OVERLAY_DIR is set" >&2
    exit 2
  fi

  printf '%s/.config/walter-os/overlay\n' "$HOME"
}

command_string_available() {
  local command_string="$1"
  local executable

  read -r executable _ <<<"$command_string"
  if [[ -z "$executable" ]]; then
    return 1
  fi

  if [[ "$executable" == */* ]]; then
    [[ -x "$executable" ]]
  else
    command -v "$executable" >/dev/null 2>&1
  fi
}

exec_command_string() {
  local command_string="$1"
  local target_dir="$2"
  local -a command_parts
  local glob_state

  glob_state="$(set +o | grep '^set +o noglob$' || true)"
  set -f
  # shellcheck disable=SC2206
  command_parts=($command_string)
  if [[ -n "$glob_state" ]]; then
    set +f
  fi
  exec "${command_parts[@]}" "$target_dir"
}

is_wsl() {
  if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]; then
    return 0
  fi

  [[ -r /proc/version ]] && grep -qi microsoft /proc/version
}

try_system_opener() {
  local target_dir="$1"

  case "$(uname -s)" in
    Darwin)
      open "$target_dir" && exit 0
      ;;
    Linux)
      if is_wsl && command -v wslpath >/dev/null 2>&1 && command -v explorer.exe >/dev/null 2>&1; then
        explorer.exe "$(wslpath -w "$target_dir")" && exit 0
      fi
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$target_dir" && exit 0
      fi
      ;;
  esac

  return 1
}

try_editor_preference() {
  local preference="$1"
  local target_dir="$2"

  case "$preference" in
    ""|system)
      try_system_opener "$target_dir" || true
      return 1
      ;;
    cursor|code|zed|vim|nvim)
      if command -v "$preference" >/dev/null 2>&1; then
        exec "$preference" "$target_dir"
      fi
      ;;
    *)
      if command_string_available "$preference"; then
        exec_command_string "$preference" "$target_dir"
      fi
      ;;
  esac

  return 1
}

overlay_dir="$(resolve_overlay_dir)"

case "${1:-}" in
  --print)
    printf '%s\n' "$overlay_dir"
    exit 0
    ;;
  -h|--help|help)
    overlay_usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "walter-os overlay: unknown option '$1'" >&2
    overlay_usage >&2
    exit 2
    ;;
esac

if [[ ! -d "$overlay_dir" ]]; then
  echo "walter-os overlay: overlay directory not found: $overlay_dir" >&2
  echo "  Run: ./setup/personal-overlay-init.sh" >&2
  exit 1
fi

if [[ -n "${WALTER_OVERLAY_OPEN_CMD:-}" ]] && command_string_available "$WALTER_OVERLAY_OPEN_CMD"; then
  exec_command_string "$WALTER_OVERLAY_OPEN_CMD" "$overlay_dir"
fi

if [[ -n "${WALTER_OVERLAY_EDITOR:-}" ]]; then
  try_editor_preference "$WALTER_OVERLAY_EDITOR" "$overlay_dir" || true
fi

try_system_opener "$overlay_dir" || true

if [[ -n "${VISUAL:-}" ]] && command_string_available "$VISUAL"; then
  exec_command_string "$VISUAL" "$overlay_dir"
fi

if [[ -n "${EDITOR:-}" ]] && command_string_available "$EDITOR"; then
  exec_command_string "$EDITOR" "$overlay_dir"
fi

echo "walter-os overlay: no configured overlay opener found. Overlay path:" >&2
echo "  $overlay_dir" >&2
exit 3
