#!/usr/bin/env bash
# scripts/walter/lib/sandbox.sh
#
# Uniform process-sandbox shim for Walter-OS hook and skill execution.

walter_sandbox_provider() {
  local os proc_version
  os="$(uname -s 2>/dev/null || true)"
  case "$os" in
    Darwin)
      printf '%s\n' "sandbox-exec"
      ;;
    Linux)
      proc_version="${WALTER_SANDBOX_PROC_VERSION:-/proc/version}"
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
      if [[ -f "$proc_version" ]] && grep -qiE 'microsoft|wsl' "$proc_version" 2>/dev/null; then
        printf '%s\n' "nsjail"
      else
        printf '%s\n' "nsjail"
      fi
      ;;
    *)
      echo "walter-sandbox: no supported sandbox provider on ${os:-unknown}; sandbox required by A-3" >&2
      return 1
      ;;
  esac
}

walter_sandbox_profile_path() {
  [[ "$#" -ge 1 ]] || {
    echo "walter-sandbox: usage: walter_sandbox_profile_path <profile> [provider]" >&2
    return 2
  }
  local profile="$1" provider="${2:-}" suffix overlay default_dir overlay_dir
  if [[ -z "$provider" ]]; then
    provider="$(walter_sandbox_provider)" || return 1
  fi
  case "$profile" in
    *[!A-Za-z0-9._-]*|'')
      echo "walter-sandbox: unsafe profile name: $profile" >&2
      return 1
      ;;
  esac
  case "$provider" in
    nsjail) suffix="nsjail.conf" ;;
    firejail) suffix="firejail.profile" ;;
    sandbox-exec) suffix="sb" ;;
    *)
      echo "walter-sandbox: unsupported provider: $provider" >&2
      return 1
      ;;
  esac

  overlay_dir="${WALTER_CONFIG:-${HOME}/.config/walter-os}/overlay/sandbox-profiles"
  default_dir="${WALTER_OS_HOME:-$(pwd)}/setup/sandbox-profiles"
  overlay="${overlay_dir}/${profile}.${suffix}"
  if [[ -f "$overlay" ]]; then
    printf '%s\n' "$overlay"
    return 0
  fi
  printf '%s\n' "${default_dir}/${profile}.${suffix}"
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
  profile_path="$(walter_sandbox_profile_path "$profile" "$provider")" || return 1

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
