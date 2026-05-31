#!/usr/bin/env bash
# hooks/capability-check.sh
# PreToolUse hook for Walter-OS session capability tokens.
#
# This hook composes after approval-gate.sh. Approval-gate decides whether the
# operator/trust policy allows an operation at all; this hook requires a valid
# session-bound capability token for high-blast-radius tool calls.

set -uo pipefail

REPO_ROOT="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SESSION_LIB="${REPO_ROOT}/scripts/walter/lib/session-state.sh"
CAP_LIB="${REPO_ROOT}/scripts/walter/lib/capability-token.sh"

CAP_HIGH_TIER_PATH_PATTERNS=(
  'hooks/*.sh'
  '.claude/settings.json'
  '.github/workflows/*'
  'install.sh'
  'AGENTS.md'
  'CLAUDE.md'
  'mcp/servers.json'
  'agents/*.md'
  'skills/*/SKILL.md'
  'auth/*'
  'crypto/*'
  'personal/health/*'
  '*.key'
  '*.pem'
  '*.crt'
  '.ssh/*'
  '*/.ssh/*'
  '*.env'
  '*.env.*'
)

if [[ ! -f "$SESSION_LIB" || ! -f "$CAP_LIB" ]]; then
  printf '%s\n' '{"decision":"block","reason":"capability-check: missing Walter-OS capability libraries — failing closed"}'
  exit 0
fi

# shellcheck source=/dev/null
source "$SESSION_LIB"
# shellcheck source=/dev/null
source "$CAP_LIB"

_cap_emit_allow() {
  printf '%s\n' '{"decision":"allow"}'
  exit 0
}

_cap_emit_allow_warn() {
  local msg="$1"
  printf '{"decision":"allow","systemMessage":%s}\n' "$(jq -n --arg m "$msg" '$m')"
  exit 0
}

_cap_emit_block() {
  local reason="$1"
  printf '{"decision":"block","reason":%s}\n' "$(jq -n --arg r "$reason" '$r')"
  exit 0
}

_cap_mktemp_file() {
  mktemp -t walter-capability-check.XXXXXX 2>/dev/null \
    || mktemp "${TMPDIR:-/tmp}/walter-capability-check.XXXXXX" 2>/dev/null
}

_cap_has_bypass_flag() {
  local command="$1" tokfile hit=1
  tokfile="$(_cap_mktemp_file)"
  if [[ -n "$tokfile" ]] && printf '%s' "$command" | xargs -n1 > "$tokfile" 2>/dev/null; then
    grep -qxF -- '--allow-no-cap' "$tokfile" && hit=0
  fi
  rm -f "$tokfile" 2>/dev/null || true
  return "$hit"
}

_cap_extract_hosts() {
  local command="$1" token host
  {
    printf '%s\n' "$command" | tr '[:space:]' '\n' | while IFS= read -r token; do
      token="${token#\"}"
      token="${token%\"}"
      token="${token#\'}"
      token="${token%\'}"
      token="${token%)}"

      host=""
      case "$token" in
        http://*|https://*)
          host="${token#*://}"
          host="${host%%/*}"
          ;;
        ssh://*)
          host="${token#ssh://}"
          host="${host%%/*}"
          ;;
        git@*:*)
          host="${token#git@}"
          host="${host%%:*}"
          ;;
      esac

      host="${host#*@}"
      host="${host%%:*}"
      [[ -n "$host" ]] && printf '%s\n' "$host"
    done
    _cap_extract_gh_host "$command"
    _cap_extract_positional_network_hosts "$command"
  } | awk 'NF && !seen[$0]++'
}

_cap_extract_gh_host() {
  local command="$1" host=""
  if [[ "$command" =~ (^|[[:space:]])--hostname=([^[:space:];|&()]+) ]]; then
    host="${BASH_REMATCH[2]}"
  elif [[ "$command" =~ (^|[[:space:]])(--hostname|-h)[[:space:]]+([^[:space:];|&()]+) ]]; then
    host="${BASH_REMATCH[3]}"
  elif [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?gh([[:space:]]|$) ]]; then
    host="${GH_HOST:-github.com}"
  fi
  [[ -n "$host" ]] && printf '%s\n' "$host"
}

_cap_extract_positional_network_hosts() {
  local command="$1" tokfile token cli idx j candidate host
  local -a tokens=()

  tokfile="$(_cap_mktemp_file)"
  if [[ -n "$tokfile" ]] && printf '%s' "$command" | xargs -n1 > "$tokfile" 2>/dev/null; then
    while IFS= read -r token; do
      tokens+=("$token")
    done < "$tokfile"
  fi
  rm -f "$tokfile" 2>/dev/null || true

  idx=0
  while [[ "$idx" -lt "${#tokens[@]}" ]]; do
    token="${tokens[$idx]}"
    cli="${token##*/}"
    case "$cli" in
      ssh|scp|rsync|nc|ncat|telnet)
        j=$((idx + 1))
        while [[ "$j" -lt "${#tokens[@]}" ]]; do
          candidate="${tokens[$j]}"
          case "$candidate" in
            -*) j=$((j + 1)); continue ;;
          esac
          host="${candidate#*@}"
          host="${host%%:*}"
          host="${host%%/*}"
          [[ -n "$host" ]] && printf '%s\n' "$host"
          break
        done
        ;;
    esac
    idx=$((idx + 1))
  done
}

_cap_is_network_command() {
  local command="$1" tokfile token cli idx j sub
  local -a tokens=()

  tokfile="$(_cap_mktemp_file)"
  if [[ -n "$tokfile" ]] && printf '%s' "$command" | xargs -n1 > "$tokfile" 2>/dev/null; then
    while IFS= read -r token; do
      tokens+=("$token")
    done < "$tokfile"
  fi
  rm -f "$tokfile" 2>/dev/null || true

  idx=0
  while [[ "$idx" -lt "${#tokens[@]}" ]]; do
    token="${tokens[$idx]}"
    cli="${token##*/}"
    case "$cli" in
      curl|wget|gh|ssh|scp|rsync|nc|ncat|telnet)
        return 0
        ;;
      git)
        j=$((idx + 1))
        while [[ "$j" -lt "${#tokens[@]}" ]]; do
          sub="${tokens[$j]}"
          case "$sub" in
            -C|-c|--git-dir|--work-tree) j=$((j + 2)); continue ;;
            -C*|--git-dir=*|--work-tree=*|--namespace=*|-*) j=$((j + 1)); continue ;;
          esac
          case "$sub" in
            clone|fetch|pull|push|ls-remote) return 0 ;;
          esac
          break
        done
        ;;
      pip|pip3|uv|uvx)
        j=$((idx + 1))
        while [[ "$j" -lt "${#tokens[@]}" ]]; do
          sub="${tokens[$j]}"
          case "$sub" in
            -*) j=$((j + 1)); continue ;;
            pip) j=$((j + 1)); continue ;;
            install|download|sync) return 0 ;;
          esac
          break
        done
        ;;
      npm|pnpm|yarn)
        j=$((idx + 1))
        while [[ "$j" -lt "${#tokens[@]}" ]]; do
          sub="${tokens[$j]}"
          case "$sub" in
            --prefix|--cwd|-C) j=$((j + 2)); continue ;;
            --prefix=*|--cwd=*|-*) j=$((j + 1)); continue ;;
            install|add|update|upgrade|dlx|exec) return 0 ;;
            test|run|lint|build) break ;;
          esac
          j=$((j + 1))
        done
        ;;
      cargo|brew|gem)
        j=$((idx + 1))
        while [[ "$j" -lt "${#tokens[@]}" ]]; do
          sub="${tokens[$j]}"
          case "$sub" in
            -*) j=$((j + 1)); continue ;;
            install|search|update|upgrade) return 0 ;;
          esac
          break
        done
        ;;
      go)
        j=$((idx + 1))
        sub="${tokens[$j]:-}"
        case "$sub" in
          get|install) return 0 ;;
          mod)
            sub="${tokens[$((j + 1))]:-}"
            case "$sub" in
              download|tidy|why) return 0 ;;
            esac
            ;;
        esac
        ;;
    esac
    idx=$((idx + 1))
  done

  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?(curl|wget)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?gh([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?(ssh|scp|rsync|nc|ncat|telnet)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?git[[:space:]]+(clone|fetch|pull|push|ls-remote)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?(pip|pip3|uv|uvx)[[:space:]]+(install|download|sync)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?(npm|pnpm|yarn)[[:space:]]+(install|add|update|upgrade|dlx|exec)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?(cargo|brew|gem)[[:space:]]+(install|search|update|upgrade)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?go[[:space:]]+(get|install)([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?go[[:space:]]+mod[[:space:]]+tidy([[:space:]]|$) ]] && return 0
  return 1
}

_cap_is_mint_command() {
  local command="$1"
  [[ "$command" =~ [\;\|\&] ]] && return 1
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?walter-os[[:space:]]+cap[[:space:]]+mint([[:space:]]|$) ]] && return 0
  [[ "$command" =~ (^|[[:space:];|&()])([^[:space:];|&()]*/)?cap[.]sh[[:space:]]+mint([[:space:]]|$) ]] && return 0
  return 1
}

_cap_is_high_tier_path() {
  local target="$1" repo="$2" pattern
  for pattern in "${CAP_HIGH_TIER_PATH_PATTERNS[@]}"; do
    _cap_glob_matches_path "$target" "$repo" "$pattern" && return 0
  done
  return 1
}

_cap_is_high_tier() {
  local tool="$1" target="$2" repo="$3"
  local sensitive_bash_re='capability-token[.]sh|walter_cap_sign_claims|session-[^[:space:];|&]*[.]key'
  case "$tool" in
    Edit|Write|MultiEdit|NotebookEdit)
      [[ -n "$target" ]] && _cap_is_high_tier_path "$target" "$repo"
      ;;
    Bash)
      _cap_is_mint_command "$target" && return 1
      _cap_is_network_command "$target" && return 0
      [[ "$target" =~ (^|[[:space:];|&()])gh[[:space:]]+pr[[:space:]]+review.*--approve ]] && return 0
      [[ "$target" =~ walter-os[[:space:]]+cap[[:space:]]+mint ]] && return 0
      [[ "$target" =~ $sensitive_bash_re ]] && return 0
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

_cap_glob_matches() {
  local value="$1" pattern="$2"
  [[ -n "$pattern" ]] || return 1
  # shellcheck disable=SC2053 # Capability path scopes intentionally use glob semantics.
  [[ "$value" == $pattern ]]
}

_cap_glob_matches_path() {
  local target="$1" repo="$2" pattern="$3" rel_target
  while [[ "$target" == ./* ]]; do
    target="${target#./}"
  done
  _cap_glob_matches "$target" "$pattern" && return 0
  if [[ -n "$repo" ]]; then
    case "$target" in
      "$repo"/*)
        rel_target="${target#"$repo"/}"
        while [[ "$rel_target" == ./* ]]; do
          rel_target="${rel_target#./}"
        done
        _cap_glob_matches "$rel_target" "$pattern" && return 0
        ;;
    esac
  fi
  return 1
}

_cap_host_matches() {
  local host="$1" pattern="$2"
  [[ -n "$host" && -n "$pattern" ]] || return 1
  case "$pattern" in
    '*') return 0 ;;
    '*.'*) [[ "$host" == "${pattern#*.}" ]] && return 1; [[ "$host" == *".${pattern#*.}" ]] ;;
    *) [[ "$host" == "$pattern" ]] ;;
  esac
}

_cap_claim_covers_host() {
  local claims="$1" host="$2" count idx value
  count="$(jq '.scope.network // [] | length' <<< "$claims")"
  idx=0
  while [[ "$idx" -lt "$count" ]]; do
    value="$(jq -r --argjson idx "$idx" '.scope.network[$idx]' <<< "$claims")"
    _cap_host_matches "$host" "$value" && return 0
    idx=$((idx + 1))
  done
  return 1
}

_cap_claim_covers_hosts() {
  local claims="$1" hosts="$2" host
  [[ -n "$hosts" ]] || return 1
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    _cap_claim_covers_host "$claims" "$host" || return 1
  done <<< "$hosts"
}

_cap_claim_matches() {
  local claims="$1" tool="$2" target="$3" hosts="$4" repo="$5"
  local cap_tool count idx value
  cap_tool="$(jq -r '.tool // empty' <<< "$claims")"
  [[ "$cap_tool" == "$tool" ]] || return 1

  case "$tool" in
    Edit|Write|MultiEdit|NotebookEdit)
      count="$(jq '.scope.paths // [] | length' <<< "$claims")"
      idx=0
      while [[ "$idx" -lt "$count" ]]; do
        value="$(jq -r --argjson idx "$idx" '.scope.paths[$idx]' <<< "$claims")"
        _cap_glob_matches_path "$target" "$repo" "$value" && return 0
        idx=$((idx + 1))
      done
      ;;
    Bash)
      count="$(jq '.scope.patterns // [] | length' <<< "$claims")"
      idx=0
      while [[ "$idx" -lt "$count" ]]; do
        value="$(jq -r --argjson idx "$idx" '.scope.patterns[$idx]' <<< "$claims")"
        [[ -n "$value" && "$target" =~ $value ]] && return 0
        idx=$((idx + 1))
      done

      if [[ -n "$hosts" ]]; then
        _cap_claim_covers_hosts "$claims" "$hosts" && return 0
        return 1
      fi
      ;;
  esac
  return 1
}

_cap_find_match() {
  local repo="$1" tool="$2" target="$3" hosts="$4"
  local state_file caps_dir token_file claims
  state_file="$(walter_session_state_file "$repo")"
  [[ -f "$state_file" ]] || return 1
  _walter_cap_validate_state "$state_file" >/dev/null 2>&1 || return 1
  caps_dir="$(jq -r '.capability_tokens_dir // empty' "$state_file")"
  [[ -d "$caps_dir" ]] || return 1

  for token_file in "$caps_dir"/cap-*.paseto; do
    [[ -f "$token_file" ]] || continue
    if claims="$(walter_cap_verify_token "$state_file" "$(cat "$token_file")" 2>/dev/null)" && \
       _cap_claim_matches "$claims" "$tool" "$target" "$hosts" "$repo"; then
      return 0
    fi
  done
  return 1
}

_cap_target_from_json() {
  local tool="$1" input="$2"
  case "$tool" in
    Bash) jq -r '.tool_input.command // ""' <<< "$input" ;;
    Edit|Write|MultiEdit) jq -r '.tool_input.file_path // ""' <<< "$input" ;;
    NotebookEdit) jq -r '.tool_input.notebook_path // .tool_input.file_path // ""' <<< "$input" ;;
    *) printf '' ;;
  esac
}

_cap_main_json() {
  local input="$1" tool target repo hosts
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"decision":"block","reason":"capability-check: jq missing — failing closed"}'
    exit 0
  fi
  if ! jq -e type >/dev/null 2>&1 <<< "$input"; then
    _cap_emit_block "capability-check: malformed hook JSON — failing closed"
  fi
  tool="$(jq -r '.tool_name // ""' <<< "$input")"
  target="$(_cap_target_from_json "$tool" "$input")"
  repo="${WALTER_SESSION_REPO:-$PWD}"
  hosts="$(_cap_extract_hosts "$target")"

  _cap_is_high_tier "$tool" "$target" "$repo" || _cap_emit_allow

  if [[ "$tool" == "Bash" && "${WALTER_CAP_BYPASS:-0}" == "1" ]] && _cap_has_bypass_flag "$target"; then
    _cap_emit_allow_warn "capability-check: WALTER_CAP_BYPASS=1 + --allow-no-cap bypassed capability enforcement"
  fi

  if _cap_find_match "$repo" "$tool" "$target" "$hosts"; then
    _cap_emit_allow
  fi

  _cap_emit_block "capability-check: no valid token for ${tool} on ${target:-<empty>}; mint with: walter-os cap mint ${tool} --duration 30m"
}

input="$(cat)"
[[ -z "$input" ]] && _cap_emit_allow
_cap_main_json "$input"
