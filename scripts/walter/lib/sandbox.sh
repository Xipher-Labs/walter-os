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
  (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
}

_walter_sandbox_path_uid() {
  if stat -f %u "$1" >/dev/null 2>&1; then
    stat -f %u "$1"
  else
    stat -c %u "$1"
  fi
}

_walter_sandbox_path_mode() {
  if stat -f %Lp "$1" >/dev/null 2>&1; then
    stat -f %Lp "$1"
  else
    stat -c %a "$1"
  fi
}

_walter_sandbox_current_uid() {
  local uid
  uid="$(id -u 2>/dev/null)" || {
    echo "walter-sandbox: failed to determine current uid" >&2
    return 1
  }
  if [[ -z "$uid" ]]; then
    echo "walter-sandbox: failed to determine current uid" >&2
    return 1
  fi
  printf '%s\n' "$uid"
}

_walter_sandbox_validate_owned_dir() {
  local path="$1" owner uid mode
  if [[ -L "$path" || ! -d "$path" ]]; then
    echo "walter-sandbox: unsafe runtime path: $path" >&2
    return 1
  fi
  uid="$(_walter_sandbox_current_uid)" || return 1
  owner="$(_walter_sandbox_path_uid "$path")" || return 1
  if [[ "$owner" != "$uid" ]]; then
    echo "walter-sandbox: runtime path not owned by current user: $path" >&2
    return 1
  fi
  mode="$(_walter_sandbox_path_mode "$path")" || return 1
  if (( (8#${mode} & 0022) != 0 )); then
    echo "walter-sandbox: runtime path is group/other-writable: $path" >&2
    return 1
  fi
}

walter_sandbox_runtime_dir() {
  local base dir uid
  uid="$(_walter_sandbox_current_uid)" || return 1
  base="${WALTER_RUNTIME_DIR:-${TMPDIR:-/tmp}/walter-os-${uid}}"
  if [[ -L "$base" ]]; then
    echo "walter-sandbox: unsafe runtime path: $base" >&2
    return 1
  fi
  if [[ -e "$base" && ! -d "$base" ]]; then
    echo "walter-sandbox: runtime path is not a directory: $base" >&2
    return 1
  fi
  mkdir -p "$base" || return 1
  if [[ -z "${WALTER_RUNTIME_DIR:-}" ]]; then
    chmod 700 "$base" || return 1
  fi
  _walter_sandbox_validate_owned_dir "$base" || return 1

  dir="${base}/sandbox"
  if [[ -L "$dir" ]]; then
    echo "walter-sandbox: unsafe runtime path: $dir" >&2
    return 1
  fi
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  _walter_sandbox_validate_owned_dir "$dir" || return 1
  printf '%s\n' "$dir"
}

_walter_sandbox_sed_escape() {
  case "$1" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
  esac
  printf '%s' "$1" | sed 's/[\\\/&]/\\&/g'
}

_walter_sandbox_firejail_path_escape() {
  local path="$1"
  case "$path" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
    *$'\t'*)
      echo "walter-sandbox: firejail path contains tab characters" >&2
      return 1
      ;;
  esac
  path="${path//\\/\\\\}"
  path="${path// /\\ }"
  printf '%s' "$path"
}

_walter_sandbox_quoted_path_escape() {
  local path="$1"
  path="${path//\\/\\\\}"
  path="${path//\"/\\\"}"
  printf '%s' "$path"
}

_walter_sandbox_profile_escape() {
  local provider="$1" value="$2"
  case "$provider" in
    firejail)
      value="$(_walter_sandbox_firejail_path_escape "$value")" || return 1
      ;;
    nsjail|sandbox-exec)
      value="$(_walter_sandbox_quoted_path_escape "$value")" || return 1
      ;;
  esac
  _walter_sandbox_sed_escape "$value"
}

_walter_sandbox_cleanup_materialized() {
  local path="$1"
  rm -f -- "$path" "${path}.tmp"
  [[ ! -d "${path}.scratch" ]] || rm -rf -- "${path}.scratch"
}

_walter_sandbox_profile_has_placeholders() {
  local path="$1"
  grep -q '@WALTER_OS_HOME@' "$path" \
    || grep -q '@WALTER_CONFIG@' "$path" \
    || grep -q '@HOME@' "$path" \
    || grep -q '@WALTER_SANDBOX_SCRATCH@' "$path"
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
  local repo_root repo_root_raw config_dir home_value
  src="$(walter_sandbox_profile_path "$profile" "$provider")" || return 1
  if [[ ! -f "$src" ]]; then
    echo "walter-sandbox: profile missing: $src" >&2
    return 1
  fi
  if ! _walter_sandbox_profile_has_placeholders "$src"; then
    printf '%s\n' "$src"
    return 0
  fi

  runtime_dir="$(walter_sandbox_runtime_dir)" || return 1
  dest="$(mktemp "${runtime_dir}/${profile}.${provider}.XXXXXX")" || return 1
  tmp_dest="${dest}.tmp"
  local scratch_dir scratch_value
  if grep -q '@WALTER_SANDBOX_SCRATCH@' "$src"; then
    scratch_dir="${dest}.scratch"
    mkdir -m 700 "$scratch_dir" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    scratch_value="$(_walter_sandbox_sed_escape "$(cd "$scratch_dir" && pwd -P)")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  else
    scratch_value=""
  fi
  repo_root_raw="$(walter_sandbox_repo_root)" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  repo_root="$(_walter_sandbox_profile_escape "$provider" "$repo_root_raw")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  config_dir="$(_walter_sandbox_profile_escape "$provider" "${WALTER_CONFIG:-${HOME}/.config/walter-os}")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  home_value="$(_walter_sandbox_profile_escape "$provider" "${HOME}")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  sed \
    -e "s/@WALTER_OS_HOME@/${repo_root}/g" \
    -e "s/@WALTER_CONFIG@/${config_dir}/g" \
    -e "s/@HOME@/${home_value}/g" \
    -e "s/@WALTER_SANDBOX_SCRATCH@/${scratch_value}/g" \
    "$src" > "$tmp_dest" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  chmod 600 "$tmp_dest" 2>/dev/null || {
    echo "walter-sandbox: failed to chmod generated profile: $tmp_dest" >&2
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  mv "$tmp_dest" "$dest" || {
    _walter_sandbox_cleanup_materialized "$dest"
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
  local profile="$1" provider profile_path cleanup_profile status
  shift

  provider="$(walter_sandbox_provider)" || return 1
  walter_sandbox_check "$profile" || return 1
  profile_path="$(walter_sandbox_materialize_profile "$profile" "$provider")" || return 1
  cleanup_profile=0
  case "$profile_path" in
    */sandbox/"$profile"."$provider".*) cleanup_profile=1 ;;
  esac

  case "$provider" in
    sandbox-exec)
      if [[ -d "${profile_path}.scratch" ]]; then
        if TMPDIR="${profile_path}.scratch/" "$provider" -f "$profile_path" -- "$@"; then
          status=0
        else
          status=$?
        fi
      else
        if "$provider" -f "$profile_path" -- "$@"; then
          status=0
        else
          status=$?
        fi
      fi
      ;;
    nsjail)
      if "$provider" --config "$profile_path" -- "$@"; then
        status=0
      else
        status=$?
      fi
      ;;
    firejail)
      if "$provider" --profile="$profile_path" -- "$@"; then
        status=0
      else
        status=$?
      fi
      ;;
    *)
      echo "walter-sandbox: unsupported provider: $provider" >&2
      return 1
      ;;
  esac
  if [[ "$cleanup_profile" -eq 1 ]]; then
    _walter_sandbox_cleanup_materialized "$profile_path"
  fi
  return "$status"
}
