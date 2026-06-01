#!/usr/bin/env bash
# sandbox-hook-runner.sh - run Walter-OS security hooks through A-3 sandboxing.
#
# Hook contract:
#   stdin:  forwarded unchanged to the wrapped hook
#   stdout: hook JSON, or a fail-closed hook JSON block if sandbox setup fails
#
# Bypass contract:
#   WALTER_SANDBOX_BYPASS=1 plus --no-sandbox is required. Either signal alone
#   fails closed. Bypass rows are written as JSONL for the future audit-chain
#   writer to ingest once that layer lands.

set -uo pipefail

_runner_dir="${BASH_SOURCE[0]%/*}"
if [[ "$_runner_dir" == "${BASH_SOURCE[0]}" ]]; then
  _runner_dir="."
fi
_runner_dir="$(cd "$_runner_dir" && pwd -P)" || exit 2
WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "${_runner_dir}/../.." && pwd -P)}"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
SANDBOX_LIB="${WALTER_OS_HOME}/scripts/walter/lib/sandbox.sh"

_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\v'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s' "$value"
}

_emit_block() {
  local reason="$1"
  printf '{"decision":"block","reason":"%s"}\n' "$(_json_escape "$reason")"
  exit 0
}

_usage() {
  cat <<'EOF'
Usage: sandbox-hook-runner.sh [--profile <name>] [--no-sandbox] -- <hook> [args...]

Runs a Walter-OS hook through walter_sandbox_run. --no-sandbox only works when
WALTER_SANDBOX_BYPASS=1 is also present.
EOF
}

_audit_bypass() {
  local profile="$1" hook="$2" logfile ts row
  mkdir -p "$WALTER_CONFIG" || return 1
  logfile="${WALTER_CONFIG}/sandbox-bypass.jsonl"
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s' unknown)"
  if command -v jq >/dev/null 2>&1; then
    row="$(jq -ncS \
      --arg ts "$ts" \
      --arg profile "$profile" \
      --arg hook "$hook" \
      '{
        ts:$ts,
        decision:"allow",
        decision_source:"operator-sandbox-bypass",
        profile:$profile,
        hook:$hook
      }')" || row=""
  else
    row="{\"ts\":\"$(_json_escape "$ts")\",\"decision\":\"allow\",\"decision_source\":\"operator-sandbox-bypass\",\"profile\":\"$(_json_escape "$profile")\",\"hook\":\"$(_json_escape "$hook")\"}"
  fi
  [[ -n "$row" ]] || return 1
  printf '%s\n' "$row" >> "$logfile"
}

profile="walter-hook-default"
no_sandbox=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 && -n "${2:-}" ]] || _emit_block "sandbox hook runner: --profile requires a value"
      profile="$2"
      shift 2
      ;;
    --no-sandbox)
      no_sandbox=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      _usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

[[ "$#" -ge 1 ]] || _emit_block "sandbox hook runner: hook path required"
hook="$1"
shift

if [[ ! -f "$hook" || ! -x "$hook" ]]; then
  _emit_block "sandbox hook runner: hook is not executable: $hook"
fi

if [[ "$no_sandbox" -eq 1 || "${WALTER_SANDBOX_BYPASS:-0}" == "1" ]]; then
  if [[ "$no_sandbox" -eq 1 && "${WALTER_SANDBOX_BYPASS:-0}" == "1" ]]; then
    if ! _audit_bypass "$profile" "$hook"; then
      _emit_block "sandbox hook runner: bypass audit failed for $hook"
    fi
    printf '%s\n' "sandbox hook runner: WARN two-factor sandbox bypass used for ${hook}" >&2
    exec "$hook" "$@"
  fi
  _emit_block "sandbox hook runner: bypass requires WALTER_SANDBOX_BYPASS=1 and --no-sandbox"
fi

if [[ ! -f "$SANDBOX_LIB" ]]; then
  _emit_block "sandbox hook runner: sandbox unavailable: missing $SANDBOX_LIB"
fi

# shellcheck source=/dev/null
if ! source "$SANDBOX_LIB" 2>/dev/null; then
  _emit_block "sandbox hook runner: sandbox unavailable: cannot load $SANDBOX_LIB"
fi

check_error="$(walter_sandbox_check "$profile" 2>&1)" || {
  _emit_block "sandbox hook runner: sandbox unavailable for $hook: $check_error"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/walter-sandbox-hook.XXXXXX" 2>/dev/null \
  || mktemp -d -t walter-sandbox-hook.XXXXXX 2>/dev/null)" || {
  _emit_block "sandbox hook runner: cannot create temporary output directory"
}
out_file="${tmp_dir}/stdout"
err_file="${tmp_dir}/stderr"
# shellcheck disable=SC2329 # Invoked indirectly via trap.
cleanup() {
  rm -rf "$tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT

if walter_sandbox_run "$profile" "$hook" "$@" >"$out_file" 2>"$err_file"; then
  cat "$out_file"
  cat "$err_file" >&2
  exit 0
else
  status=$?
fi

err="$(cat "$err_file" 2>/dev/null || true)"
[[ -n "$err" ]] || err="exit ${status}"
_emit_block "sandbox hook runner: sandboxed hook failed for $hook: $err"
