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
  value="${value//[$'\001'-$'\010'$'\013'$'\016'-$'\037'$'\177']/}"
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

# D1 (enforcement-audit-deadlock-fix): write the signed audit row for the
# sandboxed child from THIS un-sandboxed context. The child ran with
# WALTER_AUDIT_DELEGATED=1, so its own walter_audit_append calls were no-op
# successes (the hook sandbox is read-only and key-blind, so the child cannot
# sign). This records the decision the child actually emitted, preserving the
# "no decision relayed without an audit row" invariant.
# Refs: docs/specs/enforcement-audit-deadlock-fix.md
_runner_audit_append() {
  local input="$1" out_file="$2" hook_path="$3"
  local audit_lib tool decision reason hook_name
  audit_lib="${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh"
  [[ -f "$audit_lib" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  # shellcheck source=/dev/null
  source "$audit_lib" || return 1
  declare -F walter_audit_append >/dev/null 2>&1 || return 1
  walter_audit_set_repo_from_hook_input "$input" 2>/dev/null || true
  tool="$(printf '%s' "$input" | jq -er '.tool_name // "unknown"' 2>/dev/null)" || tool="unknown"
  decision="$(jq -er '.decision // "allow"' "$out_file" 2>/dev/null)" || decision="allow"
  reason="$(jq -er '.reason // ""' "$out_file" 2>/dev/null)" || reason=""
  hook_name="${hook_path##*/}"
  hook_name="${hook_name%.sh}"
  WALTER_AUDIT_DELEGATED=0 walter_audit_append "$tool" "$input" "$decision" "$hook_name" "$reason" >/dev/null
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

# Capture the hook event: feed it to the sandboxed child via stdin AND use it
# to write the signed audit row from this un-sandboxed context (D1). The child
# runs with WALTER_AUDIT_DELEGATED=1 (exported only inside the subshell, so it
# never leaks to this shell's own append).
HOOK_INPUT="$(cat)"

if printf '%s' "$HOOK_INPUT" | (
     export WALTER_AUDIT_DELEGATED=1
     walter_sandbox_run "$profile" "$hook" "$@"
   ) >"$out_file" 2>"$err_file"; then
  status=0
else
  status=$?
fi

if [[ "$status" -ne 0 ]]; then
  err="$(cat "$err_file" 2>/dev/null || true)"
  [[ -n "$err" ]] || err="exit ${status}"
  _emit_block "sandbox hook runner: sandboxed hook failed for $hook: $err"
fi

# The child decided. Record the signed audit row from here (un-sandboxed)
# BEFORE relaying the decision, so a decision is never surfaced without a
# matching audit row. Fail-closed if the append itself fails.
if ! _runner_audit_append "$HOOK_INPUT" "$out_file" "$hook"; then
  _emit_block "sandbox hook runner: audit-chain append failed for $hook; refusing unaudited decision"
fi

cat "$out_file"
cat "$err_file" >&2
exit 0
