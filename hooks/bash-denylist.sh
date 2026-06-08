#!/usr/bin/env bash
# bash-denylist.sh
# PreToolUse hook: blocks dangerous shell injection patterns NOT covered by
# approval-gate.sh (which focuses on destructive ops and path protection).
# This hook focuses on remote-code-execution via pipe-to-shell patterns.
#
# Registered in ~/.claude/settings.json PreToolUse hook chain.
# See docs/specs/walter-os-oss-security-hardening.md AC-7.
#
# Re-exec under bash 4+ if launched by the macOS default /bin/bash 3.2,
# which does NOT support `declare -A` (associative arrays). Without
# this re-exec the hook silently fails at load time on operator Macs
# (the `declare -A DENYLIST_PATTERNS` line below errors), and the
# PreToolUse chain treats that as fail-open. Codex caught this in
# the bash-3.2-related fixes already shipped for approval-gate.sh
# (P1-05 side fix); same class of bug here.
WALTER_HOOK_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALTER_OS_HOME="$WALTER_HOOK_REPO_ROOT"
if [[ -f "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" ]]; then
  # shellcheck source=/dev/null
  source "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" || true
fi

_audit_early_decision() {
  local decision="$1" reason="${2:-}"
  if declare -F walter_audit_append >/dev/null 2>&1; then
    walter_audit_append Bash "" "$decision" "bash-denylist" "$reason" >/dev/null 2>&1 || {
      printf '%s\n' '{"decision":"block","reason":"bash-denylist: audit-chain append failed; refusing unaudited decision"}'
      exit 0
    }
  else
    printf '%s\n' '{"decision":"block","reason":"bash-denylist: audit-chain writer unavailable; refusing unaudited decision"}'
    exit 0
  fi
}

_walter_bash_major="${BASH_VERSION%%.*}"
_walter_hook_sourced=0
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  _walter_hook_sourced=1
fi
if [[ "$_walter_hook_sourced" == "1" && "${WALTER_HOOK_TEST_MODE:-0}" == "1" && -n "${WALTER_BASH_MAJOR_FOR_TESTS:-}" ]]; then
  _walter_bash_major="$WALTER_BASH_MAJOR_FOR_TESTS"
fi

_walter_bash_denylist_self_path() {
  local self="$1"
  local self_dir self_base resolved

  case "$self" in
    */*)
      self_dir="$(cd "$(dirname "$self")" && pwd -P)" || return 1
      self_base="$(basename "$self")"
      printf '%s/%s\n' "$self_dir" "$self_base"
      ;;
    *)
      resolved="$(command -v "$self" 2>/dev/null || true)"
      if [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
      else
        printf '%s\n' "$self"
      fi
      ;;
  esac
}

if [[ -n "$_walter_bash_major" && "$_walter_bash_major" -lt 4 ]]; then
  # One-shot guard: if we already attempted a re-exec and ended up back in
  # bash < 4, stop. Without this, a candidate path that itself resolves to
  # bash 3.2 (e.g., symlink chain) would loop forever. Codex review of #81.
  if [[ "${WALTER_BASH_DENYLIST_REEXEC:-0}" == "1" ]]; then
    _reason="bash-denylist: re-exec landed on bash < 4 again. Refusing to loop. Install GNU bash >= 4 at /opt/homebrew/bin/bash or /usr/local/bin/bash (the two paths this hook probes)."
    _audit_early_decision block "$_reason"
    printf '%s\n' '{"decision":"block","reason":"bash-denylist: re-exec landed on bash < 4 again. Refusing to loop. Install GNU bash >= 4 at /opt/homebrew/bin/bash or /usr/local/bin/bash (the two paths this hook probes)."}'
    exit 0
  fi
  # Resolve BASH_SOURCE[0] to a usable script path. When the hook is invoked
  # as a bare filename via PATH, BASH_SOURCE[0] may also be bare; passing that
  # through exec would fail outside the original cwd.
  _self="$(_walter_bash_denylist_self_path "${BASH_SOURCE[0]}")"
  _reexec_candidates="${WALTER_BASH_DENYLIST_REEXEC_CANDIDATES_FOR_TESTS:-/opt/homebrew/bin/bash /usr/local/bin/bash}"
  for _candidate in $_reexec_candidates; do
    if [[ -x "$_candidate" && -f "$_self" ]]; then
      WALTER_BASH_DENYLIST_REEXEC=1 exec "$_candidate" "$_self" "$@"
    fi
  done
  # No newer bash available — emit fail-CLOSED block so the hook does
  # not silently fail-open. Use printf to stay consistent with the rest
  # of the hook's JSON-output convention.
  _reason="bash-denylist: requires bash >= 4.0 (macOS /bin/bash 3.2 does not support declare -A). Install brew bash or upgrade /bin/bash."
  _audit_early_decision block "$_reason"
  printf '%s\n' '{"decision":"block","reason":"bash-denylist: requires bash >= 4.0 (macOS /bin/bash 3.2 does not support declare -A). Install brew bash or upgrade /bin/bash."}'
  exit 0
fi
unset _walter_bash_major _walter_hook_sourced _reexec_candidates
#
# Bypass escape (two-factor): the hook allows a matched pattern only if BOTH
#   1. the env var WALTER_DENYLIST_BYPASS=1 is set in the hook's environment, AND
#   2. the command contains the literal string `--allow-denylist-pattern`.
# Either signal alone is NOT enough. This addresses Codex R2 MEDIUM M1: a raw
# substring bypass was too easy — any generated command could include the flag
# and skip all checks. Requiring an explicit env var means the operator (or a
# trusted wrapper) must opt in out-of-band, not via the agent-controlled
# command string. Document the bypass in the task comment.
#
# Stdin: JSON {"tool_name":"Bash","tool_input":{"command":"..."}}
# Stdout: JSON {"decision":"allow"} or {"decision":"block","reason":"..."}

set -uo pipefail

# Read the tool call from stdin
INPUT="$(cat)"

_audit_decision() {
  local decision="$1" reason="${2:-}" input_summary="${3:-${CMD:-}}"
  if declare -F walter_audit_append >/dev/null 2>&1; then
    walter_audit_append Bash "$input_summary" "$decision" "bash-denylist" "$reason" >/dev/null 2>&1 || {
      printf '%s\n' '{"decision":"block","reason":"bash-denylist: audit-chain append failed; refusing unaudited decision"}'
      exit 0
    }
  else
    printf '%s\n' '{"decision":"block","reason":"bash-denylist: audit-chain writer unavailable; refusing unaudited decision"}'
    exit 0
  fi
}

_audit_dependency_failure_best_effort() {
  local reason="$1"
  # jq-missing blocks happen before normal JSON tooling is available. The
  # audit-chain helper can create an initial dependency-failure row without jq,
  # but refuses to extend an existing chain because it cannot verify canonical
  # JSON/root integrity. Keep the safety decision fail-closed either way.
  if declare -F walter_audit_append >/dev/null 2>&1; then
    walter_audit_append Bash "$INPUT" block "bash-denylist" "$reason" >/dev/null 2>&1 || true
  fi
}

_emit_allow() {
  _audit_decision allow "${1:-}"
  printf '{"decision":"allow"}\n'
  exit 0
}

_emit_allow_with_warn() {
  local message="$1"
  _audit_decision allow "$message"
  printf '{"decision":"allow","systemMessage":%s}\n' "$(jq -n --arg m "$message" '$m')"
  exit 0
}

_emit_block() {
  local reason="$1" input_summary="${2:-${CMD:-}}"
  _audit_decision block "$reason" "$input_summary"
  printf '{"decision":"block","reason":%s}\n' "$(jq -n --arg r "$reason" '$r')"
  exit 0
}

# Extract command (using jq if available, fail-closed otherwise)
if ! command -v jq >/dev/null 2>&1 || ! jq -n true >/dev/null 2>&1; then
  # Fail CLOSED — without jq we cannot parse the hook event.
  # Allowing all ops when jq is missing would let an attacker bypass the hook
  # by shadowing jq on PATH. See approval-gate.sh P0-03 for the same pattern.
  _audit_dependency_failure_best_effort "bash-denylist: jq missing — failing closed for safety. Install jq to proceed."
  printf '{"decision":"block","reason":"bash-denylist: jq missing — failing closed for safety. Install jq to proceed."}\n'
  exit 0
fi

if declare -F walter_audit_set_repo_from_hook_input >/dev/null 2>&1; then
  walter_audit_set_repo_from_hook_input "$INPUT"
fi

# Extract command. Fail CLOSED if jq cannot parse the input or the command
# field is absent / empty — we cannot make a security decision about a
# command we cannot read. Codex R2 MEDIUM M4: previously, malformed JSON or
# jq parse failure was silently coerced to CMD="" via `// ""`, causing the
# hook to fall through to "allow".
if ! CMD="$(printf '%s' "$INPUT" | jq -er 'if (.tool_input.command | type) == "string" and (.tool_input.command | length) > 0 then .tool_input.command else empty end' 2>/dev/null)"; then
  _emit_block "bash-denylist: cannot parse hook input (malformed JSON, missing tool_input.command, or non-string command) — failing closed for safety." "$INPUT"
fi
if [[ -z "$CMD" ]]; then
  _emit_block "bash-denylist: empty command in hook input — failing closed for safety."
fi

# Two-factor bypass: requires WALTER_DENYLIST_BYPASS=1 (operator opt-in via env)
# AND the literal flag `--allow-denylist-pattern` (acknowledgment in the command).
# Either alone does NOT bypass. See header comment for rationale (Codex R2 M1).
if [[ "${WALTER_DENYLIST_BYPASS:-0}" == "1" ]] \
  && echo "$CMD" | grep -qF -- '--allow-denylist-pattern'; then
  _emit_allow_with_warn "bash-denylist: two-factor bypass used (WALTER_DENYLIST_BYPASS=1 + --allow-denylist-pattern). Command allowed with operator acknowledgment."
fi

# ---------- denylist patterns ----------
# Each entry is an extended regex (grep -E). Pattern names are used in the
# block reason for operator clarity.
#
# These patterns target RCE injection vectors not covered by approval-gate.sh:
# - pipe-to-shell (curl/wget piping to sh/bash)
# - process substitution with remote fetch
# - eval of variable (not literal strings)
# - python -c with variable interpolation
# - rm -rf / (root deletion, distinct from path-scoped rm in approval-gate.sh)

declare -A DENYLIST_PATTERNS
# curl|...|bash/sh, including absolute paths to bash/sh and sudo-wrapped form.
# Matches: `curl X | bash`, `curl X | /bin/bash`, `curl X | sudo bash`,
# `curl X | sudo sh`, `curl X | /usr/bin/sh`. The shell token is the LAST
# part of the pipe so we anchor on `sh` or `bash` (with optional path prefix
# and optional `sudo`) at the end of a pipe segment.
# pipe-to-shell. Matches everything the M3 set caught PLUS Codex R2 P1#2:
#   curl X | env bash                  (env wrapper)
#   curl X | /usr/bin/env bash         (absolute env)
#   curl X | sudo /usr/bin/env bash    (absolute env + sudo)
#   curl X | bash${IFS}-x              (IFS-based parameter expansion)
# Structure: optional (sudo + optional path), optional (env or absolute-path
# env), then the shell token, then a "boundary" that includes shell
# parameter expansion (`${...}` / `$...`) so `bash${IFS}` is caught.
# Shell token alternation. Explicit OR rather than `(ba|z|d|k)?sh`, which
# (per Copilot review of #81) does NOT match `dash` — it expands to
# `(ba|z|d|k)? + sh` and so matches `dsh` instead. We now match the full
# names plus standalone `sh`. Used in pipe-to-shell + -c patterns below.
#
# Note: not a shell variable; just a comment grouping the alternation so
# the regex strings below stay readable.
#   SHELL_TOKEN = (bash|zsh|ksh|dash|sh)
DENYLIST_PATTERNS[curl-pipe-shell]='curl[[:space:]]+.*\|[[:space:]]*(sudo[[:space:]]+)?((/[A-Za-z0-9_/-]*/)?env[[:space:]]+)?(/[A-Za-z0-9_/-]*/)?(bash|zsh|ksh|dash|sh)([[:space:]]|$|;|&|\||\$)'
DENYLIST_PATTERNS[wget-pipe-shell]='wget[[:space:]]+.*\|[[:space:]]*(sudo[[:space:]]+)?((/[A-Za-z0-9_/-]*/)?env[[:space:]]+)?(/[A-Za-z0-9_/-]*/)?(bash|zsh|ksh|dash|sh)([[:space:]]|$|;|&|\||\$)'
# Process substitution: <ANY_SHELL> <(curl ...) or <ANY_SHELL> <(wget ...)
# Covers bash, sh, zsh, dash, ksh; also covers `source <(...)` and `. <(...)`.
DENYLIST_PATTERNS[shell-process-sub-curl]='(^|[[:space:]])(bash|sh|zsh|dash|ksh|source|\.)[[:space:]]+<\([[:space:]]*curl'
DENYLIST_PATTERNS[shell-process-sub-wget]='(^|[[:space:]])(bash|sh|zsh|dash|ksh|source|\.)[[:space:]]+<\([[:space:]]*wget'
# eval of a variable or command substitution.
# Matches: the eval builtin followed by a shell-variable expansion (with or
# without braces) OR a command-substitution `$(...)`. Deliberately does NOT
# catch eval applied to a quoted literal string.
# (Documentation uses words rather than the literal pattern so the
# walter-os-eval-with-variable semgrep rule doesn't false-positive on this
# file. The pattern itself is the regex on the next line.)
DENYLIST_PATTERNS[eval-variable]='eval[[:space:]]+"?\$[{(]?[A-Za-z_(]'
# python -c with variable or command substitution: python3 -c "$CMD", python -c "$(cat ...)"
DENYLIST_PATTERNS[python-c-variable]='python3?[[:space:]]+-c[[:space:]]+["'\'']?\$'
# rm -rf / or rm -r / targeting root (exact root, not subdirs)
DENYLIST_PATTERNS[rm-rf-root]='(^|[;&|][[:space:]]*)rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f?[a-zA-Z]*[[:space:]]+\/$|rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*[[:space:]]+\/$'

_walter_shell_word_after_c() {
  local text="$1"
  local i=0 len="${#text}" out="" c

  while (( i < len )); do
    c="${text:i:1}"
    if [[ "$c" =~ [[:space:]\;\|\&] ]]; then
      break
    fi

    if [[ "$c" == "'" ]]; then
      out+="$c"
      ((i++))
      while (( i < len )); do
        c="${text:i:1}"
        out+="$c"
        ((i++))
        [[ "$c" == "'" ]] && break
      done
      continue
    fi

    if [[ "$c" == '"' ]]; then
      out+="$c"
      ((i++))
      while (( i < len )); do
        c="${text:i:1}"
        out+="$c"
        ((i++))
        if [[ "$c" == "\\" && i -lt len ]]; then
          out+="${text:i:1}"
          ((i++))
          continue
        fi
        [[ "$c" == '"' ]] && break
      done
      continue
    fi

    if [[ "$c" == '$' && "${text:i+1:1}" == "'" ]]; then
      out+="$c${text:i+1:1}"
      ((i += 2))
      while (( i < len )); do
        c="${text:i:1}"
        out+="$c"
        ((i++))
        [[ "$c" == "'" ]] && break
      done
      continue
    fi

    out+="$c"
    ((i++))
  done

  printf '%s\n' "$out"
}

_walter_shell_c_payload_has_command_substitution() {
  local remaining="$1"
  local shell_c_prefix='(^|[[:space:]|;&])(sudo[[:space:]]+)?((/[A-Za-z0-9_/-]*/)?env([[:space:]]|(\$\{IFS\}))+)?(/[A-Za-z0-9_/-]*/)?(bash|zsh|ksh|dash|sh)([[:space:]]|(\$\{IFS\}))+-c([[:space:]]|(\$\{IFS\}))*'
  local matched after payload
  local dollar_paren dollar_brace dollar_bracket backtick
  printf -v dollar_paren '%b' '\044\050'
  printf -v dollar_brace '%b' '\044\173'
  printf -v dollar_bracket '%b' '\044\133'
  printf -v backtick '%b' '\140'

  while [[ "$remaining" =~ $shell_c_prefix ]]; do
    matched="${BASH_REMATCH[0]}"
    after="${remaining:${#matched}}"
    payload="$(_walter_shell_word_after_c "$after")"
    if [[ "$payload" == *"$dollar_paren"* || "$payload" == *"$dollar_brace"* || "$payload" == *"$dollar_bracket"* || "$payload" == *"$backtick"* ]]; then
      return 0
    fi
    if [[ -z "$after" ]]; then
      break
    fi
    remaining="${after:1}"
  done

  return 1
}

if _walter_shell_c_payload_has_command_substitution "$CMD"; then
  truncated="${CMD:0:120}"
  reason="bash-denylist: command matches blocked pattern 'shell-c-command-substitution': ${truncated}"
  _emit_block "$reason"
fi

for pattern_name in "${!DENYLIST_PATTERNS[@]}"; do
  pattern="${DENYLIST_PATTERNS[$pattern_name]}"
  if echo "$CMD" | grep -qE "$pattern"; then
    # Truncate command to 120 chars for the reason string
    truncated="${CMD:0:120}"
    # Use jq to safely construct the JSON reason (handles special chars)
    reason="bash-denylist: command matches blocked pattern '${pattern_name}': ${truncated}"
    _emit_block "$reason"
  fi
done

# No pattern matched — allow
_emit_allow ""
