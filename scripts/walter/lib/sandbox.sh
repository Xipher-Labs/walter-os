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
  _walter_sandbox_firejail_validate_path "$path" || return 1
  path="${path//\\/\\\\}"
  path="${path// /\\ }"
  printf '%s' "$path"
}

_walter_sandbox_regex_escape() {
  local escaped
  case "$1" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
  esac
  escaped="$(printf '%s' "$1" | sed 's/[][\\.^$*+?{}()|]/\\&/g')" || return 1
  escaped="${escaped//\"/\\\"}"
  printf '%s' "$escaped"
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
  rm -f -- "$path" "${path}.tmp" "${path}.pre" "${path}.deny"
  [[ ! -d "${path}.scratch" ]] || rm -rf -- "${path}.scratch"
  [[ ! -d "${path}.root" ]] || rm -rf -- "${path}.root"
}

_walter_sandbox_profile_has_placeholders() {
  local path="$1"
  grep -q -- '@WALTER_OS_HOME@' "$path" \
    || grep -q -- '@WALTER_CONFIG@' "$path" \
    || grep -q -- '@WALTER_CONFIG_REGEX@' "$path" \
    || grep -q -- '@HOME@' "$path" \
    || grep -q -- '@WALTER_NSJAIL_ROOT@' "$path" \
    || grep -q -- '@WALTER_SANDBOX_SCRATCH@' "$path" \
    || grep -q -- '@WALTER_SANDBOX_CWD@' "$path" \
    || grep -q -- '@WALTER_SANDBOX_PARENT@' "$path" \
    || grep -q -- '@WALTER_NSJAIL_SESSION_KEY_MASKS@' "$path" \
    || grep -q -- '@WALTER_NSJAIL_CONFIG_KEY_MASKS@' "$path" \
    || grep -q -- '@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@' "$path" \
    || grep -q -- '@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@' "$path" \
    || grep -q -- '@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@' "$path" \
    || grep -q -- '@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@' "$path"
}

_walter_sandbox_workspace_root() {
  local cwd="$1" root
  if command -v git >/dev/null 2>&1 \
    && root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" \
    && [[ -n "$root" ]]; then
    (cd "$root" && pwd -P)
    return 0
  fi
  printf '%s\n' "$cwd"
}

_walter_sandbox_nsjail_root_mkdir_for_path() {
  local root="$1" path="$2" target
  case "$path" in
    /*) ;;
    *) return 0 ;;
  esac
  case "$path" in
    */../*|*/..)
      echo "walter-sandbox: refusing parent-directory component in nsjail root path: $path" >&2
      return 1
      ;;
  esac
  target="${root}${path}"
  mkdir -p "$target"
}

_walter_sandbox_prepare_nsjail_root() {
  local root="$1" workspace="$2" config="$3" home="$4"
  mkdir -p "$root"/{tmp,dev,etc,usr,bin,lib,lib64} || return 1
  : > "$root/dev/null" || return 1
  : > "$root/dev/urandom" || return 1
  : > "$root/etc/passwd" || return 1
  : > "$root/etc/group" || return 1
  : > "$root/etc/nsswitch.conf" || return 1
  : > "$root/etc/hosts" || return 1
  : > "$root/etc/resolv.conf" || return 1
  : > "$root/etc/gitconfig" || return 1
  _walter_sandbox_nsjail_root_mkdir_for_path "$root" "$workspace" || return 1
  _walter_sandbox_nsjail_root_mkdir_for_path "$root" "$config" || return 1
  _walter_sandbox_nsjail_root_mkdir_for_path "$root" "$home/.ssh" || return 1
  _walter_sandbox_nsjail_root_mkdir_for_path "$root" "$home/.aws" || return 1
  _walter_sandbox_nsjail_root_mkdir_for_path "$root" "$home/.gnupg" || return 1
}

_walter_sandbox_nsjail_quote() {
  case "$1" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
  esac
  printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

_walter_sandbox_nsjail_denied_file_mount() {
  local path="$1" deny_file="$2" quoted_path quoted_deny_file
  quoted_path="$(_walter_sandbox_nsjail_quote "$path")" || return 1
  quoted_deny_file="$(_walter_sandbox_nsjail_quote "$deny_file")" || return 1
  printf 'mount {\n'
  printf '  src: "%s"\n' "$quoted_deny_file"
  printf '  dst: "%s"\n' "$quoted_path"
  printf '  is_bind: true\n'
  printf '  rw: false\n'
  printf '  mandatory: true\n'
  printf '}\n'
}

_walter_sandbox_nsjail_session_key_mounts() {
  local deny_file="$1" state_dir key
  state_dir="${WALTER_CONFIG:-${HOME}/.config/walter-os}/state"
  for key in "$state_dir"/session-*.key "$state_dir"/session-*.key.tmp; do
    [[ -f "$key" ]] || continue
    _walter_sandbox_nsjail_denied_file_mount "$key" "$deny_file" || return 1
  done
}

_walter_sandbox_key_scan_max_depth() {
  local value="${WALTER_SANDBOX_KEY_SCAN_MAX_DEPTH:-8}"
  case "$value" in
    ''|*[!0-9]*)
      echo "walter-sandbox: invalid WALTER_SANDBOX_KEY_SCAN_MAX_DEPTH: $value" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$((10#$value))"
}

_walter_sandbox_key_scan_max_entries() {
  local value="${WALTER_SANDBOX_KEY_SCAN_MAX_ENTRIES:-20000}"
  case "$value" in
    ''|*[!0-9]*)
      echo "walter-sandbox: invalid WALTER_SANDBOX_KEY_SCAN_MAX_ENTRIES: $value" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$((10#$value))"
}

_walter_sandbox_key_scan_emit() {
  local renderer="$1" path="$2" renderer_arg="${3:-}"
  case "$path" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
  esac
  "$renderer" "$path" "$renderer_arg"
}

_walter_sandbox_key_scan_count_entry() {
  local max_entries="$1" path="$2"
  case "$path" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
  esac
  WALTER_SANDBOX_KEY_SCAN_VISITED=$((WALTER_SANDBOX_KEY_SCAN_VISITED + 1))
  if [[ "$WALTER_SANDBOX_KEY_SCAN_VISITED" -gt "$max_entries" ]]; then
    echo "walter-sandbox: sensitive key scan exceeded ${max_entries} entries under $path" >&2
    return 1
  fi
}

_walter_sandbox_key_scan_depth() {
  local root="$1" path="$2" rel
  rel="${path#"$root"/}"
  if [[ "$rel" == "$path" || -z "$rel" ]]; then
    printf '0\n'
    return 0
  fi
  rel="${rel//[^\/]/}"
  printf '%s\n' "$((${#rel} + 1))"
}

_walter_sandbox_key_scan() {
  local root="$1" renderer="$2" renderer_arg="${3:-}" max_depth max_entries scan_depth entry_depth entry base
  local fifo find_stderr find_pid scan_status find_status old_umask
  [[ -d "$root" ]] || return 0
  max_depth="$(_walter_sandbox_key_scan_max_depth)" || return 1
  max_entries="$(_walter_sandbox_key_scan_max_entries)" || return 1
  WALTER_SANDBOX_KEY_SCAN_VISITED=0
  scan_depth=$((max_depth + 1))

  fifo="$(mktemp "${TMPDIR:-/tmp}/walter-sandbox-find.XXXXXX")" || return 1
  rm -f -- "$fifo"
  find_stderr="$(mktemp "${TMPDIR:-/tmp}/walter-sandbox-find-stderr.XXXXXX")" || {
    rm -f -- "$fifo"
    return 1
  }
  old_umask="$(umask)" || {
    rm -f -- "$fifo" "$find_stderr"
    return 1
  }
  umask 077 || {
    rm -f -- "$fifo" "$find_stderr"
    return 1
  }
  if ! mkfifo "$fifo"; then
    umask "$old_umask" || true
    rm -f -- "$fifo" "$find_stderr"
    return 1
  fi
  umask "$old_umask" || {
    rm -f -- "$fifo" "$find_stderr"
    return 1
  }
  find "$root" -mindepth 1 -maxdepth "$scan_depth" -print0 > "$fifo" 2> "$find_stderr" &
  find_pid="$!"

  scan_status=0
  while IFS= read -r -d '' entry; do
    _walter_sandbox_key_scan_count_entry "$max_entries" "$entry" || {
      scan_status=1
      break
    }
    entry_depth="$(_walter_sandbox_key_scan_depth "$root" "$entry")" || {
      scan_status=1
      break
    }
    if [[ "$entry_depth" -gt "$max_depth" ]]; then
      echo "walter-sandbox: sensitive key scan exceeded max depth ${max_depth} under $entry" >&2
      scan_status=1
      break
    fi
    if [[ -f "$entry" ]]; then
      base="${entry##*/}"
      case "$base" in
        *.pem|*.key)
          _walter_sandbox_key_scan_emit "$renderer" "$entry" "$renderer_arg" || {
            scan_status=1
            break
          }
          ;;
      esac
    fi
  done < "$fifo"
  if [[ "$scan_status" -ne 0 ]]; then
    kill "$find_pid" 2>/dev/null || true
    wait "$find_pid" 2>/dev/null || true
    rm -f -- "$fifo" "$find_stderr"
    return 1
  fi
  if wait "$find_pid"; then
    find_status=0
  else
    find_status="$?"
  fi
  rm -f -- "$fifo"
  if [[ "$find_status" -ne 0 ]]; then
    cat "$find_stderr" >&2
    rm -f -- "$find_stderr"
    echo "walter-sandbox: sensitive key scan failed under $root" >&2
    return 1
  fi
  rm -f -- "$find_stderr"
  return "$scan_status"
}

_walter_sandbox_nsjail_key_mount_renderer() {
  local path="$1" deny_file="$2"
  _walter_sandbox_nsjail_denied_file_mount "$path" "$deny_file"
}

_walter_sandbox_nsjail_config_key_mount_renderer() {
  local path="$1" deny_file="$2" state_dir
  state_dir="${WALTER_CONFIG:-${HOME}/.config/walter-os}/state"
  case "$path" in
    "$state_dir"/session-*.key|"$state_dir"/session-*.key.tmp)
      return 0
      ;;
  esac
  _walter_sandbox_nsjail_denied_file_mount "$path" "$deny_file"
}

_walter_sandbox_firejail_validate_path() {
  case "$1" in
    *$'\n'*|*$'\r'*)
      echo "walter-sandbox: path contains newline characters" >&2
      return 1
      ;;
    *$'\t'*)
      echo "walter-sandbox: firejail profile paths must not contain tab characters: $1" >&2
      return 1
      ;;
    *\"*)
      echo "walter-sandbox: firejail profile paths must not contain double quote characters: $1" >&2
      return 1
      ;;
    *'*'*|*'?'*|*'['*|*']'*)
      echo "walter-sandbox: firejail profile paths must not contain glob metacharacters: $1" >&2
      return 1
      ;;
  esac
}

_walter_sandbox_firejail_key_blacklist_renderer() {
  local path="$1"
  path="$(_walter_sandbox_firejail_path_escape "$path")" || return 1
  printf 'blacklist %s\n' "$path"
}

_walter_sandbox_nsjail_sensitive_key_mounts() {
  local root="$1" deny_file="$2"
  _walter_sandbox_key_scan "$root" _walter_sandbox_nsjail_key_mount_renderer "$deny_file"
}

_walter_sandbox_nsjail_config_key_mounts() {
  local root="$1" deny_file="$2"
  _walter_sandbox_key_scan "$root" _walter_sandbox_nsjail_config_key_mount_renderer "$deny_file"
}

_walter_sandbox_firejail_sensitive_key_blacklists() {
  local root="$1"
  _walter_sandbox_key_scan "$root" _walter_sandbox_firejail_key_blacklist_renderer
}

_walter_sandbox_firejail_config_key_blacklists() {
  local root="$1"
  _walter_sandbox_key_scan "$root" _walter_sandbox_firejail_key_blacklist_renderer
}

_walter_sandbox_firejail_home_key_blacklists() {
  local root="$1"
  _walter_sandbox_key_scan "$root" _walter_sandbox_firejail_key_blacklist_renderer
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
  local profile="$1" provider="$2" src runtime_dir dest tmp_dest tmp_pre
  local repo_root repo_root_raw config_dir config_dir_raw config_dir_regex config_dir_regex_raw
  local home_value cwd_raw cwd_value parent_raw parent_value nsjail_root_raw nsjail_root_value needs_cwd needs_parent
  local nsjail_deny_file nsjail_session_key_mounts nsjail_config_key_mounts nsjail_sensitive_key_mounts firejail_config_key_blacklists firejail_home_key_blacklists firejail_sensitive_key_blacklists
  local placeholder trimmed
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
    scratch_value="$(_walter_sandbox_profile_escape "$provider" "$(cd "$scratch_dir" && pwd -P)")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  else
    scratch_value=""
  fi
  nsjail_root_raw=""
  nsjail_root_value=""
  repo_root_raw="$(walter_sandbox_repo_root)" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  repo_root="$(_walter_sandbox_profile_escape "$provider" "$repo_root_raw")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  config_dir_raw="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
  config_dir="$(_walter_sandbox_profile_escape "$provider" "$config_dir_raw")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  config_dir_regex_raw="$(_walter_sandbox_regex_escape "$config_dir_raw")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  config_dir_regex="$(_walter_sandbox_sed_escape "$config_dir_regex_raw")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  home_value="$(_walter_sandbox_profile_escape "$provider" "${HOME}")" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  cwd_raw=""
  cwd_value=""
  parent_raw=""
  parent_value=""
  needs_cwd=0
  needs_parent=0
  grep -q '@WALTER_SANDBOX_CWD@' "$src" && needs_cwd=1
  if grep -q '@WALTER_SANDBOX_PARENT@' "$src" \
    || grep -q '@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@' "$src" \
    || grep -q '@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@' "$src"; then
    needs_parent=1
  fi
  if [[ "$needs_cwd" -eq 1 || "$needs_parent" -eq 1 ]]; then
    cwd_raw="$(pwd -P)" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    cwd_value="$(_walter_sandbox_profile_escape "$provider" "$cwd_raw")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  if [[ "$needs_parent" -eq 1 ]]; then
    parent_raw="$(_walter_sandbox_workspace_root "$cwd_raw")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    if [[ "$parent_raw" == "/" ]]; then
      echo "walter-sandbox: refusing root workspace scope for skill profile: $cwd_raw" >&2
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    fi
    case "$parent_raw" in
      *\"*)
        echo "walter-sandbox: workspace path contains double quote characters: $parent_raw" >&2
        _walter_sandbox_cleanup_materialized "$dest"
        return 1
        ;;
    esac
    parent_value="$(_walter_sandbox_profile_escape "$provider" "$parent_raw")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  if [[ "$provider" == "firejail" ]]; then
    if grep -q '@WALTER_OS_HOME@' "$src"; then
      _walter_sandbox_firejail_validate_path "$repo_root_raw" || {
        _walter_sandbox_cleanup_materialized "$dest"
        return 1
      }
    fi
    _walter_sandbox_firejail_validate_path "$config_dir_raw" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    _walter_sandbox_firejail_validate_path "$HOME" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    if [[ -n "$parent_raw" ]]; then
      _walter_sandbox_firejail_validate_path "$parent_raw" || {
        _walter_sandbox_cleanup_materialized "$dest"
        return 1
      }
    fi
    if [[ -n "${scratch_dir:-}" ]]; then
      _walter_sandbox_firejail_validate_path "$scratch_dir" || {
        _walter_sandbox_cleanup_materialized "$dest"
        return 1
      }
    fi
  fi
  if grep -q '@WALTER_NSJAIL_ROOT@' "$src"; then
    nsjail_root_raw="${dest}.root"
    mkdir -m 700 "$nsjail_root_raw" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    _walter_sandbox_prepare_nsjail_root "$nsjail_root_raw" "$parent_raw" "$config_dir_raw" "$HOME" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    nsjail_root_value="$(_walter_sandbox_profile_escape "$provider" "$(cd "$nsjail_root_raw" && pwd -P)")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  nsjail_session_key_mounts=""
  nsjail_deny_file=""
  if grep -q '@WALTER_NSJAIL_SESSION_KEY_MASKS@' "$src" \
    || grep -q '@WALTER_NSJAIL_CONFIG_KEY_MASKS@' "$src" \
    || grep -q '@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@' "$src"; then
    nsjail_deny_file="${dest}.deny"
    : > "$nsjail_deny_file" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
    chmod 000 "$nsjail_deny_file" 2>/dev/null || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  if grep -q '@WALTER_NSJAIL_SESSION_KEY_MASKS@' "$src"; then
    nsjail_session_key_mounts="$(_walter_sandbox_nsjail_session_key_mounts "$nsjail_deny_file")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  nsjail_config_key_mounts=""
  if grep -q '@WALTER_NSJAIL_CONFIG_KEY_MASKS@' "$src"; then
    nsjail_config_key_mounts="$(_walter_sandbox_nsjail_config_key_mounts "$config_dir_raw" "$nsjail_deny_file")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  nsjail_sensitive_key_mounts=""
  if grep -q '@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@' "$src"; then
    nsjail_sensitive_key_mounts="$(_walter_sandbox_nsjail_sensitive_key_mounts "$parent_raw" "$nsjail_deny_file")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  firejail_config_key_blacklists=""
  if grep -q '@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@' "$src"; then
    firejail_config_key_blacklists="$(_walter_sandbox_firejail_config_key_blacklists "$config_dir_raw")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  firejail_home_key_blacklists=""
  if grep -q '@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@' "$src"; then
    firejail_home_key_blacklists="$(_walter_sandbox_firejail_home_key_blacklists "$HOME")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  firejail_sensitive_key_blacklists=""
  if grep -q '@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@' "$src"; then
    firejail_sensitive_key_blacklists="$(_walter_sandbox_firejail_sensitive_key_blacklists "$parent_raw")" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  fi
  tmp_pre="${dest}.pre"
  sed \
    -e "s/@WALTER_OS_HOME@/${repo_root}/g" \
    -e "s/@WALTER_CONFIG@/${config_dir}/g" \
    -e "s/@WALTER_CONFIG_REGEX@/${config_dir_regex}/g" \
    -e "s/@HOME@/${home_value}/g" \
    -e "s/@WALTER_NSJAIL_ROOT@/${nsjail_root_value}/g" \
    -e "s/@WALTER_SANDBOX_SCRATCH@/${scratch_value}/g" \
    -e "s/@WALTER_SANDBOX_CWD@/${cwd_value}/g" \
    -e "s/@WALTER_SANDBOX_PARENT@/${parent_value}/g" \
    "$src" > "$tmp_pre" || {
      _walter_sandbox_cleanup_materialized "$dest"
      return 1
    }
  : > "$tmp_dest" || {
    _walter_sandbox_cleanup_materialized "$dest"
    return 1
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    placeholder=""
    case "$line" in
      *'@WALTER_NSJAIL_SESSION_KEY_MASKS@'*) placeholder="@WALTER_NSJAIL_SESSION_KEY_MASKS@" ;;
      *'@WALTER_NSJAIL_CONFIG_KEY_MASKS@'*) placeholder="@WALTER_NSJAIL_CONFIG_KEY_MASKS@" ;;
      *'@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@'*) placeholder="@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@" ;;
      *'@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@'*) placeholder="@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@" ;;
      *'@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@'*) placeholder="@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@" ;;
      *'@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@'*) placeholder="@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@" ;;
    esac
    if [[ -n "$placeholder" ]]; then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      if [[ "$trimmed" != "$placeholder" ]]; then
        echo "walter-sandbox: multiline placeholder must be on a standalone line: $placeholder" >&2
        _walter_sandbox_cleanup_materialized "$dest"
        return 1
      fi
    fi

    if [[ "$placeholder" == "@WALTER_NSJAIL_SESSION_KEY_MASKS@" ]]; then
      if [[ -n "$nsjail_session_key_mounts" ]]; then
        printf '%s\n' "$nsjail_session_key_mounts" >> "$tmp_dest" || {
          _walter_sandbox_cleanup_materialized "$dest"
          return 1
        }
      fi
    elif [[ "$placeholder" == "@WALTER_NSJAIL_CONFIG_KEY_MASKS@" ]]; then
      if [[ -n "$nsjail_config_key_mounts" ]]; then
        printf '%s\n' "$nsjail_config_key_mounts" >> "$tmp_dest" || {
          _walter_sandbox_cleanup_materialized "$dest"
          return 1
        }
      fi
    elif [[ "$placeholder" == "@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@" ]]; then
      if [[ -n "$nsjail_sensitive_key_mounts" ]]; then
        printf '%s\n' "$nsjail_sensitive_key_mounts" >> "$tmp_dest" || {
          _walter_sandbox_cleanup_materialized "$dest"
          return 1
        }
      fi
    elif [[ "$placeholder" == "@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@" ]]; then
      if [[ -n "$firejail_config_key_blacklists" ]]; then
        printf '%s\n' "$firejail_config_key_blacklists" >> "$tmp_dest" || {
          _walter_sandbox_cleanup_materialized "$dest"
          return 1
        }
      fi
    elif [[ "$placeholder" == "@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@" ]]; then
      if [[ -n "$firejail_home_key_blacklists" ]]; then
        printf '%s\n' "$firejail_home_key_blacklists" >> "$tmp_dest" || {
          _walter_sandbox_cleanup_materialized "$dest"
          return 1
        }
      fi
    elif [[ "$placeholder" == "@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@" ]]; then
      if [[ -n "$firejail_sensitive_key_blacklists" ]]; then
        printf '%s\n' "$firejail_sensitive_key_blacklists" >> "$tmp_dest" || {
          _walter_sandbox_cleanup_materialized "$dest"
          return 1
        }
      fi
    else
      printf '%s\n' "$line" >> "$tmp_dest" || {
        _walter_sandbox_cleanup_materialized "$dest"
        return 1
      }
    fi
  done < "$tmp_pre"
  rm -f -- "$tmp_pre"
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

walter_sandbox_provider_path() {
  [[ "$#" -eq 1 ]] || {
    echo "walter-sandbox: usage: walter_sandbox_provider_path <provider>" >&2
    return 2
  }
  local provider="$1" provider_path provider_dir provider_base
  provider_path="$(command -v -- "$provider" 2>/dev/null || true)"
  if [[ -z "$provider_path" || "$provider_path" != */* || ! -f "$provider_path" || ! -x "$provider_path" ]]; then
    echo "walter-sandbox: provider missing: $provider" >&2
    return 1
  fi
  provider_dir="${provider_path%/*}"
  provider_base="${provider_path##*/}"
  if [[ "$provider_dir" == "$provider_path" ]]; then
    provider_dir="."
  fi
  provider_dir="$(cd "$provider_dir" && pwd -P)" || return 1
  printf '%s\n' "${provider_dir}/${provider_base}"
}

walter_sandbox_check() {
  local profile="${1:-walter-hook-default}" provider profile_path
  provider="$(walter_sandbox_provider)" || return 1
  walter_sandbox_provider_path "$provider" >/dev/null || return 1
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
  local profile="$1" provider provider_path profile_path cleanup_profile status
  shift

  provider="$(walter_sandbox_provider)" || return 1
  provider_path="$(walter_sandbox_provider_path "$provider")" || return 1
  profile_path="$(walter_sandbox_materialize_profile "$profile" "$provider")" || return 1
  cleanup_profile=0
  case "$profile_path" in
    */sandbox/"$profile"."$provider".*) cleanup_profile=1 ;;
  esac

  case "$provider" in
    sandbox-exec)
      if [[ -d "${profile_path}.scratch" ]]; then
        if TMPDIR="${profile_path}.scratch/" "$provider_path" -f "$profile_path" -- "$@"; then
          status=0
        else
          status=$?
        fi
      else
        if "$provider_path" -f "$profile_path" -- "$@"; then
          status=0
        else
          status=$?
        fi
      fi
      ;;
    nsjail)
      if "$provider_path" --config "$profile_path" -- "$@"; then
        status=0
      else
        status=$?
      fi
      ;;
    firejail)
      if "$provider_path" --profile="$profile_path" -- "$@"; then
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
