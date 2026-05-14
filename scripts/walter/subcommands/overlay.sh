#!/usr/bin/env bash
# scripts/walter/subcommands/overlay.sh
# Open the Walter-OS personal overlay in the operator's editor.

set -euo pipefail

overlay_usage() {
  cat <<'EOF'
Usage: walter-os overlay [--print]
       walter overlay [--print]

Open ~/.config/walter-os/overlay in an editor, preferring:
  1. WALTER_OVERLAY_OPEN_CMD
  2. VISUAL
  3. EDITOR
  4. code
  5. Visual Studio Code via macOS open
  6. xdg-open

Options:
  --print      Print the overlay path without opening it.
  -h, --help   Show this help.
EOF
}

overlay_dir="${WALTER_OVERLAY_DIR:-${HOME}/.config/walter-os/overlay}"

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

if [[ -n "${WALTER_OVERLAY_OPEN_CMD:-}" ]]; then
  exec "$WALTER_OVERLAY_OPEN_CMD" "$overlay_dir"
fi

if [[ -n "${VISUAL:-}" ]]; then
  exec "$VISUAL" "$overlay_dir"
fi

if [[ -n "${EDITOR:-}" ]]; then
  exec "$EDITOR" "$overlay_dir"
fi

if command -v code >/dev/null 2>&1; then
  exec code "$overlay_dir"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  exec open -a "Visual Studio Code" "$overlay_dir"
fi

if command -v xdg-open >/dev/null 2>&1; then
  exec xdg-open "$overlay_dir"
fi

echo "walter-os overlay: no editor opener found. Overlay path:" >&2
echo "  $overlay_dir" >&2
exit 3
