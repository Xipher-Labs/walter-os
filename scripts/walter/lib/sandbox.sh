#!/usr/bin/env bash
# scripts/walter/lib/sandbox.sh
#
# Uniform process-sandbox shim for Walter-OS hook and skill execution.

walter_sandbox_provider() {
  local os
  os="$(uname -s 2>/dev/null || true)"
  case "$os" in
    Darwin)
      printf '%s\n' "sandbox-exec"
      ;;
    Linux)
      if [[ -n "${WALTER_SANDBOX_PROVIDER:-}" ]]; then
        case "$WALTER_SANDBOX_PROVIDER" in
          nsjail|firejail) printf '%s\n' "$WALTER_SANDBOX_PROVIDER" ;;
          *)
            echo "walter-sandbox: unsupported Linux provider override: $WALTER_SANDBOX_PROVIDER" >&2
            return 1
            ;;
        esac
        return 0
      fi
      printf '%s\n' "nsjail"
      ;;
    *)
      echo "walter-sandbox: no supported sandbox provider on ${os:-unknown}; sandbox required by A-3" >&2
      return 1
      ;;
  esac
}

walter_sandbox_profile_suffix() {
  local provider="$1"
  case "$provider" in
    nsjail) printf '%s\n' "nsjail.conf" ;;
    firejail) printf '%s\n' "firejail.profile" ;;
    sandbox-exec) printf '%s\n' "sb" ;;
    *)
      echo "walter-sandbox: unsupported provider: $provider" >&2
      return 1
      ;;
  esac
}

walter_sandbox_repo_root() {
  if [[ -n "${WALTER_OS_HOME:-}" ]]; then
    printf '%s\n' "$WALTER_OS_HOME"
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

walter_sandbox_runtime_dir() {
  local base dir uid
  uid="$(id -u 2>/dev/null || printf '%s' "unknown")"
  base="${WALTER_RUNTIME_DIR:-${TMPDIR:-/tmp}/walter-os-${uid}}"
  dir="${base}/sandbox"
  mkdir -p "$dir" || return 1
  if [[ -z "${WALTER_RUNTIME_DIR:-}" ]]; then
    chmod 700 "$base" 2>/dev/null || true
  fi
  chmod 700 "$dir" 2>/dev/null || true
  printf '%s\n' "$dir"
}

_walter_sandbox_sed_escape() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

walter_sandbox_profile_path() {
  [[ "$#" -ge 1 ]] || {
    echo "walter-sandbox: usage: walter_sandbox_profile_path <profile> [provider]" >&2
    return 2
  }
  local profile="$1" provider="${2:-}" suffix overlay default_dir overlay_dir repo_root
  if [[ -z "$provider" ]]; then
    provider="$(walter_sandbox_provider)" || return 1
  fi
  case "$profile" in
    *[!A-Za-z0-9._-]*|'')
      echo "walter-sandbox: unsafe profile name: $profile" >&2
      return 1
      ;;
  esac
  suffix="$(walter_sandbox_profile_suffix "$provider")" || return 1

  overlay_dir="${WALTER_CONFIG:-${HOME}/.config/walter-os}/overlay/sandbox-profiles"
  repo_root="$(walter_sandbox_repo_root)" || return 1
  default_dir="${repo_root}/setup/sandbox-profiles"
  overlay="${overlay_dir}/${profile}.${suffix}"
  if [[ -f "$overlay" ]]; then
    printf '%s\n' "$overlay"
    return 0
  fi
  printf '%s\n' "${default_dir}/${profile}.${suffix}"
}

walter_sandbox_materialize_profile() {
  [[ "$#" -eq 2 ]] || {
    echo "walter-sandbox: usage: walter_sandbox_materialize_profile <profile> <provider>" >&2
    return 2
  }
  local profile="$1" provider="$2" src runtime_dir dest tmp_dest
  local repo_root config_dir home_value
  src="$(walter_sandbox_profile_path "$profile" "$provider")" || return 1
  if [[ ! -f "$src" ]]; then
    echo "walter-sandbox: profile missing: $src" >&2
    return 1
  fi
  if ! grep -q '@WALTER_OS_HOME@\|@WALTER_CONFIG@\|@HOME@' "$src"; then
    printf '%s\n' "$src"
    return 0
  fi

  runtime_dir="$(walter_sandbox_runtime_dir)" || return 1
  dest="$(mktemp "${runtime_dir}/${profile}.${provider}.XXXXXX")" || return 1
  tmp_dest="${dest}.tmp"
  repo_root="$(_walter_sandbox_sed_escape "$(walter_sandbox_repo_root)")" || return 1
  config_dir="$(_walter_sandbox_sed_escape "${WALTER_CONFIG:-${HOME}/.config/walter-os}")"
  home_value="$(_walter_sandbox_sed_escape "${HOME}")"
  sed \
    -e "s/@WALTER_OS_HOME@/${repo_root}/g" \
    -e "s/@WALTER_CONFIG@/${config_dir}/g" \
    -e "s/@HOME@/${home_value}/g" \
    "$src" > "$tmp_dest" || {
      rm -f "$dest" "$tmp_dest"
      return 1
    }
  chmod 600 "$tmp_dest" 2>/dev/null || true
  mv "$tmp_dest" "$dest" || {
    rm -f "$dest" "$tmp_dest"
    return 1
  }
  printf '%s\n' "$dest"
}

walter_sandbox_check() {
  local profile="${1:-walter-hook-default}" provider profile_path
  provider="$(walter_sandbox_provider)" || return 1
  if ! command -v "$provider" >/dev/null 2>&1; then
    echo "walter-sandbox: provider missing: $provider" >&2
    return 1
  fi
  profile_path="$(walter_sandbox_profile_path "$profile" "$provider")" || return 1
  if [[ ! -f "$profile_path" ]]; then
    echo "walter-sandbox: profile missing: $profile_path" >&2
    return 1
  fi
}

walter_sandbox_run() {
  [[ "$#" -ge 2 ]] || {
    echo "walter-sandbox: usage: walter_sandbox_run <profile> <cmd...>" >&2
    return 2
  }
  local profile="$1" provider profile_path
  shift

  provider="$(walter_sandbox_provider)" || return 1
  walter_sandbox_check "$profile" || return 1
  profile_path="$(walter_sandbox_materialize_profile "$profile" "$provider")" || return 1

  case "$provider" in
    sandbox-exec)
      "$provider" -f "$profile_path" -- "$@"
      ;;
    nsjail)
      "$provider" --config "$profile_path" -- "$@"
      ;;
    firejail)
      "$provider" --profile="$profile_path" -- "$@"
      ;;
    *)
      echo "walter-sandbox: unsupported provider: $provider" >&2
      return 1
      ;;
  esac
}
