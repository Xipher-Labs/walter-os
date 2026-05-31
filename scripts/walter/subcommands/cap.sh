#!/usr/bin/env bash
# scripts/walter/subcommands/cap.sh
# Manage Walter-OS session capability tokens.

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"

CAP_LIB="${WALTER_OS_HOME}/scripts/walter/lib/capability-token.sh"
if [[ ! -f "$CAP_LIB" ]]; then
  echo "walter-os cap: missing capability-token library: $CAP_LIB" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$CAP_LIB"

cap_usage() {
  cat <<'EOF'
Usage: walter-os cap <subcommand> [args]

Subcommands:
  mint <tool> --duration <N>[smh] [--paths <glob>]... [--network <host>]... [--patterns <regex>]...
  list [repo-path]
  verify <token-file> [repo-path]
  revoke <nonce> [repo-path]

repo-path defaults to the current working directory.
EOF
}

_cap_json_array_append() {
  local array_json="$1" value="$2"
  jq -cn --argjson arr "$array_json" --arg value "$value" '$arr + [$value]'
}

_cap_option_value() {
  local opt="$1" value="${2-}"
  if [[ $# -lt 2 || -z "$value" ]]; then
    echo "walter-os cap mint: missing value for $opt" >&2
    return 2
  fi
  printf '%s' "$value"
}

_cap_start_or_get_state_file() {
  local repo="$1" result status state_file
  set +e
  result="$(walter_session_touch "$repo")"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$result" >&2
    return "$status"
  fi
  state_file="$(walter_session_state_file "$repo")"
  [[ -f "$state_file" ]] || {
    echo "walter-os cap: session state missing after touch: $state_file" >&2
    return 12
  }
  printf '%s' "$state_file"
}

_cap_existing_state_file() {
  local repo="$1" state_file
  state_file="$(walter_session_state_file "$repo")"
  [[ -f "$state_file" ]] || return 1
  printf '%s' "$state_file"
}

_cap_session_expiry_epoch() {
  local state_file="$1" started_at max_hours started_epoch
  started_at="$(jq -r '.started_at // empty' "$state_file")"
  max_hours="$(jq -r '.max_hours_at_start // empty' "$state_file")"
  [[ "$max_hours" =~ ^[1-9][0-9]*$ ]] || return 1
  started_epoch="$(_walter_session_epoch "$started_at")"
  [[ "$started_epoch" =~ ^[0-9]+$ ]] || return 1
  printf '%s' $((started_epoch + (max_hours * 3600)))
}

_cap_write_token_file() {
  local state_file="$1" nonce="$2" token="$3"
  local caps_dir token_file tmp_file
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  [[ -d "$caps_dir" ]] || {
    echo "walter-os cap: caps directory missing: $caps_dir" >&2
    return 1
  }
  [[ "$nonce" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "walter-os cap: unsafe nonce" >&2
    return 1
  }
  token_file="${caps_dir}/cap-${nonce}.paseto"
  tmp_file="$(mktemp "${token_file}.XXXXXX")"
  printf '%s\n' "$token" > "$tmp_file"
  chmod 600 "$tmp_file"
  mv "$tmp_file" "$token_file"
}

cmd_cap_mint() {
  local tool="${1:-}" duration="" repo="$PWD" paths='[]' network='[]' patterns='[]'
  local state_file now_epoch now_iso duration_seconds requested_exp session_exp exp_epoch exp_iso nonce session_id claims token value
  [[ -n "$tool" ]] || {
    echo "walter-os cap mint: tool required" >&2
    return 2
  }
  shift || true

  if [[ -n "${WALTER_AGENT_CONTEXT:-}" ]]; then
    echo "walter-os cap mint: cap minting blocked inside subagent context (caller=${WALTER_AGENT_CONTEXT}). Operator must mint caps in the top-level session." >&2
    return 4
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --duration)
        duration="$(_cap_option_value "$1" "${2-}")" || return $?
        shift 2 ;;
      --paths|--path)
        value="$(_cap_option_value "$1" "${2-}")" || return $?
        paths="$(_cap_json_array_append "$paths" "$value")"
        shift 2 ;;
      --network)
        value="$(_cap_option_value "$1" "${2-}")" || return $?
        network="$(_cap_json_array_append "$network" "$value")"
        shift 2 ;;
      --patterns|--pattern)
        value="$(_cap_option_value "$1" "${2-}")" || return $?
        patterns="$(_cap_json_array_append "$patterns" "$value")"
        shift 2 ;;
      --repo)
        repo="$(_cap_option_value "$1" "${2-}")" || return $?
        shift 2 ;;
      -h|--help|help)
        cap_usage; return 0 ;;
      *)
        echo "walter-os cap mint: unknown argument: $1" >&2
        return 2 ;;
    esac
  done

  [[ -n "$duration" ]] || {
    echo "walter-os cap mint: --duration required" >&2
    return 2
  }
  duration_seconds="$(walter_cap_duration_to_seconds "$duration")" || return $?
  state_file="$(_cap_start_or_get_state_file "$repo")" || return $?
  now_epoch="$(_walter_session_now_epoch)"
  now_iso="$(_walter_session_iso "$now_epoch")"
  requested_exp=$((now_epoch + duration_seconds))
  session_exp="$(_cap_session_expiry_epoch "$state_file")" || {
    echo "walter-os cap mint: cannot derive session expiry" >&2
    return 1
  }
  exp_epoch="$requested_exp"
  if (( exp_epoch > session_exp )); then
    exp_epoch="$session_exp"
  fi
  if (( exp_epoch <= now_epoch )); then
    echo "walter-os cap mint: active session has no remaining lifetime for a capability token" >&2
    return 1
  fi
  exp_iso="$(_walter_session_iso "$exp_epoch")"
  nonce="$(_walter_session_uuid)"
  session_id="$(jq -r '.session_id' "$state_file")"

  claims="$(jq -ncS \
    --arg session_id "$session_id" \
    --arg tool "$tool" \
    --arg iat "$now_iso" \
    --arg exp "$exp_iso" \
    --arg nonce "$nonce" \
    --arg sub "${USER:-operator}" \
    --argjson paths "$paths" \
    --argjson network "$network" \
    --argjson patterns "$patterns" \
    '{
      iss:"walter-os",
      sub:$sub,
      session_id:$session_id,
      tool:$tool,
      scope:{paths:$paths, network:$network, patterns:$patterns},
      iat:$iat,
      exp:$exp,
      nonce:$nonce
    }')"
  token="$(walter_cap_sign_claims "$state_file" "$claims")" || return $?
  _cap_write_token_file "$state_file" "$nonce" "$token" || return $?
  printf '%s\n' "$token"
}

cmd_cap_list() {
  local repo="${1:-$PWD}" state_file caps_dir token_file claims
  if ! state_file="$(_cap_existing_state_file "$repo")"; then
    echo "[]"
    return 0
  fi
  caps_dir="$(jq -r '.capability_tokens_dir // empty' "$state_file")"
  if [[ ! -d "$caps_dir" ]]; then
    echo "[]"
    return 0
  fi
  {
    for token_file in "$caps_dir"/cap-*.paseto; do
      [[ -f "$token_file" ]] || continue
      if claims="$(walter_cap_verify_token "$state_file" "$(cat "$token_file")" 2>/dev/null)"; then
        jq -cS --arg file "$token_file" '. + {file:$file}' <<< "$claims"
      fi
    done
  } | jq -s .
}

cmd_cap_verify() {
  local token_file="${1:-}" repo="${2:-$PWD}" state_file
  [[ -n "$token_file" && -f "$token_file" ]] || {
    echo "walter-os cap verify: token file required" >&2
    return 2
  }
  state_file="$(_cap_existing_state_file "$repo")" || {
    echo "walter-os cap verify: active session required" >&2
    return 1
  }
  walter_cap_verify_token "$state_file" "$(cat "$token_file")"
}

cmd_cap_revoke() {
  local nonce="${1:-}" repo="${2:-$PWD}" state_file caps_dir token_file
  [[ "$nonce" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "walter-os cap revoke: safe nonce required" >&2
    return 2
  }
  state_file="$(_cap_existing_state_file "$repo")" || {
    echo "walter-os cap revoke: active session required" >&2
    return 1
  }
  _walter_cap_validate_state "$state_file" || return 1
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  token_file="${caps_dir}/cap-${nonce}.paseto"
  rm -f "$token_file"
  echo "walter-os cap: revoked $nonce"
}

sub="${1:-help}"
shift || true

case "$sub" in
  mint) cmd_cap_mint "$@" ;;
  list|ls) cmd_cap_list "$@" ;;
  verify) cmd_cap_verify "$@" ;;
  revoke|rm) cmd_cap_revoke "$@" ;;
  -h|--help|help) cap_usage ;;
  *)
    echo "walter-os cap: unknown subcommand: $sub" >&2
    cap_usage >&2
    exit 2
    ;;
esac
