#!/usr/bin/env bash
# Interactive prompts via gum (if available) or read fallback

prompt_input() {
  # Usage: VAR=$(prompt_input "Question" "default")
  local q="$1" def="${2:-}"
  if command -v gum >/dev/null 2>&1; then
    gum input --prompt "$q ▸ " --placeholder "$def"
  else
    if [[ -n "$def" ]]; then
      read -r -p "$q [$def]: " v
      echo "${v:-$def}"
    else
      read -r -p "$q: " v
      echo "$v"
    fi
  fi
}

prompt_choose() {
  # Usage: VAR=$(prompt_choose "Pick" "opt1" "opt2" "opt3")
  local q="$1"; shift
  if command -v gum >/dev/null 2>&1; then
    gum choose --header="$q" "$@"
  else
    echo "$q"
    select v in "$@"; do
      [[ -n "$v" ]] && { echo "$v"; return; }
    done
  fi
}

prompt_confirm() {
  # Usage: prompt_confirm "Are you sure?" && do_thing
  local q="$1"
  if command -v gum >/dev/null 2>&1; then
    gum confirm "$q"
  else
    read -r -p "$q [y/N]: " v
    [[ "$v" =~ ^[yY]$ ]]
  fi
}

prompt_editor() {
  # Open $EDITOR (or nano) on a tempfile pre-filled with content; return edited content
  local prefill="$1" suffix="${2:-md}"
  local tmpfile
  tmpfile=$(mktemp -t walter-prompt-XXX."$suffix")
  printf '%s' "$prefill" > "$tmpfile"
  "${EDITOR:-nano}" "$tmpfile" < /dev/tty > /dev/tty
  cat "$tmpfile"
  rm -f "$tmpfile"
}
