#!/usr/bin/env bash
# Runtime used by generated high-risk tool wrappers.

set -uo pipefail

tool="${1:-}"
if [[ -z "$tool" ]]; then
  echo "walter wrapper: tool name required" >&2
  exit 2
fi
shift

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
WALTER_WRAPPER_DIR="${WALTER_WRAPPER_DIR:-$(cd "$(dirname "$0")" && pwd -P)}"
export WALTER_OS_HOME WALTER_CONFIG WALTER_WRAPPER_DIR
WALTER_WRAPPER_BASH="${WALTER_WRAPPER_BASH:-${BASH:-bash}}"

_shell_quote() {
  printf '%q' "$1"
}

_json_string() {
  local value="$1" output="" char="" escaped="" ordinal i
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      \\) output="${output}\\\\" ;;
      '"') output="${output}\\\"" ;;
      $'\b') output="${output}\\b" ;;
      $'\f') output="${output}\\f" ;;
      $'\n') output="${output}\\n" ;;
      $'\r') output="${output}\\r" ;;
      $'\t') output="${output}\\t" ;;
      *)
        LC_CTYPE=C printf -v ordinal '%d' "'$char"
        if [[ "$ordinal" -lt 32 ]]; then
          printf -v escaped '\\u%04x' "$ordinal"
          output="${output}${escaped}"
        else
          output="${output}${char}"
        fi
        ;;
    esac
  done
  printf '"%s"' "$output"
}

_command_string() {
  local command="$tool" arg
  for arg in "$@"; do
    command+=" $(_shell_quote "$arg")"
  done
  printf '%s' "$command"
}

_is_walter_control_arg() {
  case "$1" in
    --allow-egress-outbound|--allow-no-cap|--allow-denylist-pattern) return 0 ;;
    *) return 1 ;;
  esac
}

_load_real_args() {
  local arg
  WALTER_REAL_ARGS=()
  for arg in "$@"; do
    if _is_walter_control_arg "$arg"; then
      continue
    fi
    WALTER_REAL_ARGS+=("$arg")
  done
}

_curl_output_target_is_pipe_sink() {
  local target="$1"
  [[ "$target" == "-" ]] && return 0
  case "$target" in
    /dev/stdout|/dev/fd/*|/proc/self/fd/*|/proc/"$$"/fd/*)
      return 0
      ;;
  esac
  [[ -e "$target" && ! -f "$target" ]]
}

_curl_stdout_pipe_blocked() {
  local arg output_target_pending=0 output_target current_transfer_has_output=0
  local url_like_count=0 safe_output_count=0
  [[ "$tool" == "curl" ]] || return 1
  [[ -p /dev/stdout ]] || return 1

  for arg in "$@"; do
    if [[ "$output_target_pending" -eq 1 ]]; then
      _curl_output_target_is_pipe_sink "$arg" && return 0
      current_transfer_has_output=1
      safe_output_count=$((safe_output_count + 1))
      output_target_pending=0
      continue
    fi
    case "$arg" in
      http://*|https://*|ftp://*|file://*)
        url_like_count=$((url_like_count + 1))
        ;;
    esac
    case "$arg" in
      --next)
        [[ "$current_transfer_has_output" -eq 0 ]] && return 0
        current_transfer_has_output=0
        ;;
      -o|--output)
        output_target_pending=1
        ;;
      --output=*)
        output_target="${arg#--output=}"
        _curl_output_target_is_pipe_sink "$output_target" && return 0
        current_transfer_has_output=1
        safe_output_count=$((safe_output_count + 1))
        ;;
      -o?*)
        output_target="${arg#-o}"
        _curl_output_target_is_pipe_sink "$output_target" && return 0
        current_transfer_has_output=1
        safe_output_count=$((safe_output_count + 1))
        ;;
      -O|--remote-name)
        current_transfer_has_output=1
        safe_output_count=$((safe_output_count + 1))
        ;;
    esac
  done

  if [[ "$output_target_pending" -eq 1 || "$current_transfer_has_output" -eq 0 ]]; then
    return 0
  fi
  if [[ "$url_like_count" -gt "$safe_output_count" ]]; then
    return 0
  fi

  return 1
}

_path_without_wrapper_dir() {
  local entry normalized_wrapper normalized_entry output="" sep=""
  local -a entries=()
  normalized_wrapper="$(_physical_dir "$WALTER_WRAPPER_DIR")"
  IFS=':' read -r -a entries <<<"${PATH:-}"
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    normalized_entry="$(_physical_dir "$entry")"
    [[ "$normalized_entry" == "$normalized_wrapper" ]] && continue
    output="${output}${sep}${entry}"
    sep=":"
  done
  printf '%s' "$output"
}

_physical_dir() {
  local dir="$1"
  while [[ "$dir" != "/" && "$dir" == */ ]]; do
    dir="${dir%/}"
  done
  if [[ -d "$dir" ]]; then
    (cd "$dir" && pwd -P)
    return
  fi
  printf '%s\n' "$dir"
}

_is_generated_walter_wrapper() {
  local candidate="$1"
  [[ -f "$candidate" ]] || return 1
  grep -qF 'high-risk-tool-wrapper.sh' "$candidate" 2>/dev/null \
    && grep -qF 'WALTER_GENERATED_WRAPPER_DIR' "$candidate" 2>/dev/null
}

_find_real_tool() {
  local search_path real real_dir wrapper_dir entry candidate
  local -a entries=()
  wrapper_dir="$(_physical_dir "$WALTER_WRAPPER_DIR")"
  search_path="$(_path_without_wrapper_dir)"
  IFS=':' read -r -a entries <<<"$search_path"
  for entry in "${entries[@]}"; do
    [[ -n "$entry" ]] || continue
    candidate="${entry}/${tool}"
    [[ -x "$candidate" && ! -d "$candidate" ]] || continue
    real="$candidate"
    real_dir="$(_physical_dir "$(dirname "$real")")"
    [[ "$real_dir" == "$wrapper_dir" ]] && continue
    _is_generated_walter_wrapper "$real" && continue
    printf '%s' "$real"
    return 0
  done
  echo "walter wrapper: real tool not found after removing Walter wrapper dirs from PATH: $tool" >&2
  exit 127
}

_hook_input() {
  local command="$1" cwd
  cwd="$(pwd -P 2>/dev/null || pwd)"
  printf '{"tool_name":"Bash","cwd":%s,"tool_input":{"command":%s}}\n' \
    "$(_json_string "$cwd")" \
    "$(_json_string "$command")"
}

_json_decision_blocked() {
  grep -Eq '"(decision|permissionDecision)"[[:space:]]*:[[:space:]]*"block"'
}

_json_decision_allowed() {
  grep -Eq '"(decision|permissionDecision)"[[:space:]]*:[[:space:]]*"allow"'
}

_run_json_gate() {
  local gate="$1" command="$2" output gate_status
  [[ -x "$gate" || -f "$gate" ]] || {
    echo "walter wrapper: missing gate: $gate" >&2
    exit 7
  }
  output="$(_hook_input "$command" | env \
    -u WALTER_CAP_BYPASS \
    -u WALTER_DENYLIST_BYPASS \
    -u WALTER_EGRESS_ALLOW_OVERRIDE \
    "$WALTER_WRAPPER_BASH" "$gate" 2>&1)"
  gate_status="$?"
  if [[ "$gate_status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    echo "walter wrapper: gate failed: $gate" >&2
    exit 7
  fi
  if printf '%s\n' "$output" | _json_decision_blocked; then
    printf '%s\n' "$output" >&2
    exit 7
  fi
  if ! printf '%s\n' "$output" | _json_decision_allowed; then
    printf '%s\n' "$output" >&2
    echo "walter wrapper: gate returned unrecognized output: $gate" >&2
    exit 7
  fi
}

_run_approval_gate() {
  local gate="$1" command="$2"
  env \
    -u WALTER_AGENT_ALLOW_OVERRIDE \
    -u WALTER_STANDING_APPROVALS_OVERRIDE \
    -u WALTER_STANDING_APPROVALS \
    -u WALTER_TRUST_TIERS \
    "$WALTER_WRAPPER_BASH" "$gate" check "$command" --tool Bash
}

_gh_alias_set_shell_payload() {
  local arg shell_mode=0 alias_seen=0 payload=""
  [[ "$tool" == "gh" ]] || return 1
  [[ "${1:-}" == "alias" && "${2:-}" == "set" ]] || return 1
  shift 2

  for arg in "$@"; do
    if [[ "$alias_seen" -eq 1 && "$arg" == "-" ]]; then
      printf '%s' "$arg"
      return 0
    fi

    case "$arg" in
      --shell|-s|--shell=true|--shell=1)
        shell_mode=1
        continue
        ;;
      --shell=false|--shell=0|--clobber)
        continue
        ;;
      --*=*)
        continue
        ;;
      -*)
        continue
        ;;
    esac

    if [[ "$alias_seen" -eq 0 ]]; then
      alias_seen=1
      continue
    fi

    payload="$arg"
    if [[ "$payload" == !* ]]; then
      printf '%s' "${payload#!}"
      return 0
    fi
    if [[ "$shell_mode" -eq 1 ]]; then
      printf '%s' "$payload"
      return 0
    fi
    return 1
  done

  return 1
}

_run_bash_denylist_gates() {
  local command="$1" payload=""
  shift

  _run_json_gate "${WALTER_OS_HOME}/hooks/bash-denylist.sh" "$command"

  # `gh alias set --shell` stores shell code as an argv payload. The normal
  # command rendering quotes argv safely, so inspect that shell payload directly.
  if payload="$(_gh_alias_set_shell_payload "$@")" && [[ -n "$payload" ]]; then
    if [[ "$payload" == "-" ]]; then
      echo "walter wrapper: BLOCK gh shell alias stdin payload; pass the expansion as an argv payload so Walter can inspect it" >&2
      exit 7
    fi
    _run_json_gate "${WALTER_OS_HOME}/hooks/bash-denylist.sh" "$payload"
  fi
}

command_string="$(_command_string "$@")"
_load_real_args "$@"

if _curl_stdout_pipe_blocked "$@"; then
  echo "walter wrapper: BLOCK curl stdout pipe; write to a file with -o/--output or review the full shell command through Walter hooks" >&2
  exit 7
fi

approval_gate="${WALTER_OS_HOME}/hooks/approval-gate.sh"
if [[ ! -f "$approval_gate" ]]; then
  echo "walter wrapper: missing approval gate: $approval_gate" >&2
  exit 7
fi
_run_approval_gate "$approval_gate" "$command_string"
approval_status="$?"
if [[ "$approval_status" -ne 0 ]]; then
  exit "$approval_status"
fi

_run_bash_denylist_gates "$command_string" "$@"
_run_json_gate "${WALTER_OS_HOME}/hooks/capability-check.sh" "$command_string"
_run_json_gate "${WALTER_OS_HOME}/hooks/network-gate.sh" "$command_string"

real_tool="$(_find_real_tool)"
exec "$real_tool" "${WALTER_REAL_ARGS[@]}"
