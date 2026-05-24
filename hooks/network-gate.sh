#!/usr/bin/env bash
# hooks/network-gate.sh
# PreToolUse hook — default-deny egress gate. Composes with
# `bash-denylist.sh` (RCE patterns) and `approval-gate.sh` (destructive
# ops) in the PreToolUse Bash chain: ALL hooks must allow.
#
# Spec:   docs/specs/network-egress-allowlist.md (OSS Trust A-2)
# Parent: #122
# Sibling pattern: hooks/bash-denylist.sh (same I/O contract, same
# fail-closed posture).
#
# I/O contract (Claude Code hook spec):
#   stdin:  JSON {"tool_name":"<name>","tool_input":{"command":"..."}}
#   stdout: JSON {"decision":"allow"|"block","reason":"..."}
#
# Posture (per spec D-3):
#   - Default-deny: missing or empty allowlist → every outbound call is
#     blocked.
#   - Fail-CLOSED: malformed input, missing command, missing jq, or a
#     known network CLI whose host can't be parsed → block.
#   - Two-factor bypass (spec D-6): both
#       WALTER_EGRESS_ALLOW_OVERRIDE=1 (env, operator-set)
#       AND the literal `--allow-egress-outbound` token in the command
#     must be present to override a deny. Either alone is rejected.
#
# Threat model + scope notes are in the spec. This hook ONLY inspects
# command-line strings for a known set of network CLIs; it does NOT
# intercept connection-layer traffic (that's A-3 / process-isolation).

set -uo pipefail

# Re-exec under bash 4+ if we landed on bash 3.2 (macOS default). We use
# `=~` and `read -a` which both work in 3.2 — but indexed-array growth +
# `${arr[@]}` semantics differ in subtle ways. Inherit the same re-exec
# dance bash-denylist.sh uses so this hook behaves identically.
if [[ -n "${BASH_VERSION:-}" && "${BASH_VERSION%%.*}" -lt 4 ]]; then
  if [[ "${WALTER_NETWORK_GATE_REEXEC:-0}" == "1" ]]; then
    printf '%s\n' '{"decision":"block","reason":"network-gate: re-exec landed on bash < 4 again. Install GNU bash >= 4."}'
    exit 0
  fi
  _self="${BASH_SOURCE[0]}"
  for _candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_candidate" && -f "$_self" ]]; then
      WALTER_NETWORK_GATE_REEXEC=1 exec "$_candidate" "$_self" "$@"
    fi
  done
  printf '%s\n' '{"decision":"block","reason":"network-gate: requires bash >= 4.0 — install brew bash or upgrade /bin/bash."}'
  exit 0
fi

# ---------- stdin parsing ----------

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  # Same posture as bash-denylist.sh: without jq we cannot parse the
  # hook event. Fail-closed.
  printf '%s\n' '{"decision":"block","reason":"network-gate: jq missing — failing closed for safety. Install jq to proceed."}'
  exit 0
fi

if [[ -z "$INPUT" ]]; then
  printf '%s\n' '{"decision":"block","reason":"network-gate: empty hook input — failing closed for safety."}'
  exit 0
fi

if ! TOOL_NAME="$(printf '%s' "$INPUT" | jq -er '.tool_name // empty' 2>/dev/null)"; then
  printf '%s\n' '{"decision":"block","reason":"network-gate: malformed JSON or missing tool_name — failing closed for safety."}'
  exit 0
fi

# Pass through every tool that isn't Bash. We only inspect command strings.
if [[ "$TOOL_NAME" != "Bash" ]]; then
  printf '%s\n' '{"decision":"allow"}'
  exit 0
fi

if ! CMD="$(printf '%s' "$INPUT" | jq -er '.tool_input.command // empty' 2>/dev/null)"; then
  printf '%s\n' '{"decision":"block","reason":"network-gate: cannot parse hook input (malformed JSON or missing tool_input.command) — failing closed for safety."}'
  exit 0
fi
if [[ -z "$CMD" ]]; then
  printf '%s\n' '{"decision":"block","reason":"network-gate: empty Bash command — failing closed for safety."}'
  exit 0
fi

# ---------- bypass detection ----------

# Spec D-6: BOTH env + flag must be present.
#
# R6 refinement (token-aware): the flag must be a REAL shell-quoted
# token, not just a whitespace-bracketed substring. We use `xargs -n1`
# which parses POSIX shell quoting and emits one token per line; then
# `grep -qxF` requires an EXACT line match — so an embedded
# `--allow-egress-outbound` inside a single-quoted string literal
# (`curl 'a b --allow-egress-outbound c d'`) is part of a larger token
# (`a b --allow-egress-outbound c d`) and does NOT trigger the bypass.
# Falls back to the previous whitespace-bracketed regex if xargs fails
# (e.g. unmatched quote in the command — also fail-safe in the deny
# direction since the regex is stricter than substring match).
_has_bypass_flag() {
  local _tokfile
  _tokfile="$(mktemp 2>/dev/null)"
  if [[ -n "$_tokfile" ]] && printf '%s' "$1" | xargs -n1 > "$_tokfile" 2>/dev/null; then
    local _hit=1
    grep -qxF -- '--allow-egress-outbound' "$_tokfile" && _hit=0
    rm -f "$_tokfile"
    return "$_hit"
  fi
  rm -f "$_tokfile" 2>/dev/null
  # xargs failed (unmatched quote etc.) — fall back to the previous
  # whitespace-bracketed regex (still stricter than substring match).
  # `printf '%s\n'` over `echo` so leading `-n`/`-e` isn't treated as
  # echo options.
  printf '%s\n' "$1" | grep -qE -- '(^|[[:space:]])--allow-egress-outbound([[:space:]]|$)'
}

_two_factor_bypass_active() {
  [[ "${WALTER_EGRESS_ALLOW_OVERRIDE:-0}" == "1" ]] && _has_bypass_flag "$CMD"
}

# ---------- network CLI detection ----------

# Returns 0 if the command appears to invoke a network CLI we recognize.
# The detection looks at the FIRST tokens of the command and at any
# segment after a `;`, `&&`, `||`, `|`, or `&` separator — because chained
# commands like `cd foo && curl X` still need inspecting.
#
# `git` is a network CLI only for a known subcommand allowlist
# (clone/fetch/pull/push/ls-remote/fetch-pack/send-pack/http-fetch/
# http-push/imap-send/upload-pack/upload-archive/receive-pack/bundle/
# send-email/lfs/svn/annex/p4/cvsimport/cvsexportcommit + `archive`
# only when --remote= is present). All other subcommands — including
# status/log/diff/add/commit/rev-parse/config/branch/cherry/remote/
# submodule/archive (no --remote=) — are LOCAL and pass through.

# Output helper.
_emit_allow() {
  printf '%s\n' '{"decision":"allow"}'
  exit 0
}
_emit_block() {
  local reason="$1"
  printf '{"decision":"block","reason":%s}\n' "$(jq -n --arg r "$reason" '$r')"
  exit 0
}
_emit_allow_with_warn() {
  local msg="$1"
  printf '{"decision":"allow","systemMessage":%s}\n' "$(jq -n --arg m "$msg" '$m')"
  exit 0
}

# Split the command into segments by shell separators (`;`, `&&`, `||`,
# `|`, `&`). We then inspect each segment as if it were its own command.
# Using `sed` to insert NEWLINE markers + reading line by line is the
# portable way to do this in bash 3.2.
# Extract the body of every $( ... ), <( ... ), and `...` substitution
# in the segment. Emits each body on a separate line. Tracks nesting
# depth + quote state so `echo "$(curl url)"` correctly extracts
# `curl url`, and nested forms like `echo $(curl $(other))` extract the
# OUTER body (which itself starts with curl + a nested $() — the inner
# one is exposed when the outer body is inspected as a synthetic
# segment, so the recursion is implicit).
#
# Codex R3 fix CR2-A: `echo $(curl https://evil.example/p)` previously
# returned ALLOW because cli="echo" (a local builtin) and the curl
# inside the substitution was never inspected. With this extractor +
# the main loop running each substitution body through _inspect_segment,
# substitution-smuggled CLIs are now gated like top-level CLIs.
_extract_substitutions() {
  local s="$1"
  local n=${#s} i=0
  local in_sq=0 in_dq=0
  local depth=0 start=0 esc=0
  local in_bt=0 bt_start=0
  # `in_dq_saved` remembers the OUTER in_dq state when we descend into
  # a $(...) substitution from inside double quotes. Without saving +
  # resetting, the depth>0 walk re-enters the in_dq branch and never
  # sees the matching ')'. Codex R3 follow-up — pinned by the bats
  # `$(curl evil) INSIDE double quotes is BLOCKED`.
  local in_dq_saved=0
  local c c2
  while [[ $i -lt $n ]]; do
    c="${s:$i:1}"
    c2="${s:$i:2}"
    if [[ "$esc" -eq 1 ]]; then
      esc=0; i=$((i + 1)); continue
    fi
    # Inside a $( … ) / <( … ) — depth-tracking. Inner quote state
    # is tracked SEPARATELY (the substitution body is its own bash
    # context — operators inside the body are not the outer-shell
    # operators we care about for segmentation).
    if [[ $depth -gt 0 ]]; then
      if [[ $in_sq -eq 1 ]]; then
        [[ "$c" == "'" ]] && in_sq=0
      elif [[ $in_dq -eq 1 ]]; then
        case "$c" in
          '"') in_dq=0 ;;
          '\\') esc=1 ;;
        esac
      else
        case "$c" in
          "'") in_sq=1 ;;
          '"') in_dq=1 ;;
        esac
        case "$c2" in
          '$('|'<(') depth=$((depth + 1)); i=$((i + 2)); continue ;;
        esac
        if [[ "$c" == ')' ]]; then
          depth=$((depth - 1))
          if [[ $depth -eq 0 ]]; then
            printf '%s\n' "${s:$start:$((i - start))}"
            # Restore the outer in_dq state we saved on descent.
            in_dq=$in_dq_saved
            in_dq_saved=0
          fi
        fi
      fi
      i=$((i + 1)); continue
    fi
    # Inside a `…` backtick substitution.
    if [[ $in_bt -eq 1 ]]; then
      if [[ "$c" == '\\' ]]; then esc=1; i=$((i + 1)); continue; fi
      if [[ "$c" == '`' ]]; then
        printf '%s\n' "${s:$bt_start:$((i - bt_start))}"
        in_bt=0
      fi
      i=$((i + 1)); continue
    fi
    # Top level (depth 0, not in backtick).
    if [[ $in_sq -eq 1 ]]; then
      # Single quotes are literal in bash — NO substitution inside.
      [[ "$c" == "'" ]] && in_sq=0
    elif [[ $in_dq -eq 1 ]]; then
      # Codex R3 follow-up: bash DOES expand $(…), <(…), and `…`
      # inside double quotes. The previous branch only tracked the
      # closing `"` and the `\\` escape — `$(curl evil.example)` inside
      # `"…"` was invisible to the extractor → outer `echo` allowed
      # → curl ran without allowlist enforcement.
      case "$c" in
        '"') in_dq=0; i=$((i + 1)); continue ;;
        '\\') esc=1; i=$((i + 1)); continue ;;
        '`')
          in_bt=1
          bt_start=$((i + 1))
          i=$((i + 1)); continue
          ;;
      esac
      case "$c2" in
        '$('|'<(')
          # Save outer in_dq so it can be restored when this
          # substitution closes — otherwise the depth-walk would
          # re-enter the in_dq branch and miss the matching `)`.
          in_dq_saved=$in_dq
          in_dq=0
          depth=1
          start=$((i + 2))
          i=$((i + 2)); continue
          ;;
      esac
    else
      case "$c" in
        "'") in_sq=1 ;;
        '"') in_dq=1 ;;
        '`')
          in_bt=1
          bt_start=$((i + 1))
          ;;
      esac
      case "$c2" in
        '$('|'<(')
          depth=1
          start=$((i + 2))
          i=$((i + 2)); continue
          ;;
      esac
    fi
    i=$((i + 1))
  done
}

_split_segments() {
  # Quote-aware segment split. Walks the command character by character
  # tracking single-quote / double-quote / backtick state, and emits a
  # segment break only when a shell separator (`;`, `&&`, `||`, `|`,
  # `&`) appears OUTSIDE any quoted region.
  #
  # Codex R2 fix C2: the previous sed-based splitter ran BEFORE any
  # tokenization, so it split quoted URLs with query strings mid-URL
  # (`curl 'https://api.github.com/x?q=a&page=1'` became two segments,
  # the second `page=1'` and the first missing the closing `'`). With
  # quote awareness, the `&` inside the URL stays part of the curl
  # segment.
  #
  # Earlier Copilot R3 fix (the `&` bypass — `true&curl evil.example`):
  # still covered, because `&` outside any quote IS a real separator.
  #
  # Bash 3-compatible (substring + `case` + integer arithmetic only).
  local cmd="$1"
  local n=${#cmd} i=0
  local in_sq=0 in_dq=0 in_bt=0 esc=0
  local seg=""
  local c c2
  while [[ $i -lt $n ]]; do
    c="${cmd:$i:1}"
    c2="${cmd:$i:2}"
    if [[ "$esc" -eq 1 ]]; then
      # Previous char was a backslash inside a "" — this char is
      # escaped, pass through unconditionally.
      seg+="$c"
      esc=0
      i=$((i + 1))
      continue
    fi
    if [[ "$in_sq" -eq 0 && "$in_dq" -eq 0 && "$in_bt" -eq 0 ]]; then
      # Outside any quoted region — operators are real here.
      case "$c2" in
        "&&"|"||")
          printf '%s\n' "$seg"; seg=""; i=$((i + 2)); continue ;;
      esac
      case "$c" in
        ";"|"|"|"&")
          printf '%s\n' "$seg"; seg=""; i=$((i + 1)); continue ;;
        "'") in_sq=1 ;;
        '"') in_dq=1 ;;
        '`') in_bt=1 ;;
      esac
    elif [[ "$in_dq" -eq 1 ]]; then
      case "$c" in
        '"') in_dq=0 ;;
        '\\') esc=1 ;;
      esac
    elif [[ "$in_sq" -eq 1 ]]; then
      # Single-quoted strings have NO escapes (per POSIX).
      [[ "$c" == "'" ]] && in_sq=0
    elif [[ "$in_bt" -eq 1 ]]; then
      [[ "$c" == '`' ]] && in_bt=0
    fi
    seg+="$c"
    i=$((i + 1))
  done
  # Tail segment (no trailing operator).
  if [[ -n "$seg" ]]; then
    printf '%s\n' "$seg"
  fi
}

# Return the first non-flag positional argument from a tokenized arg list.
# Used by ssh / nc.
_first_positional() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -*) ;;  # skip flags
      *)  printf '%s\n' "$arg"; return 0 ;;
    esac
  done
  return 1
}

# Extract DNS-host from a URL string `scheme://[user[:pass]@]host[:port][/...]`.
# Returns empty on no match. Uses bash regex.
#
# IPv6 literals MUST be enclosed in brackets in a URL (RFC 3986):
#   http://[::1]/path → host = [::1]
#   http://[fd00::1]:8080/api → host = [fd00::1]
# We extract the bracketed form FIRST, then fall through to the IPv4 /
# DNS-name regex. R2 (W1) finding — previously the `[` character was
# returned as the "host" for IPv6 URLs which then failed CLI validation
# with a cryptic message. The brackets are kept as part of the extracted
# host so the allowlist entry can be written verbatim (`[::1]`,
# `[fd00::1]`) — `_egress_validate_host` permits brackets for this case.
_host_from_url() {
  local url="$1"
  # IPv6 literal first: scheme://[...]
  if [[ "$url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@[:space:]]+@)?(\[[0-9a-fA-F:]+\]) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  # IPv4 / DNS hostname.
  if [[ "$url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@[:space:]]+@)?([^/:[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# Extract host from `user@host:path` (git/scp/rsync ssh form).
_host_from_userhostpath() {
  local s="$1"
  if [[ "$s" =~ ^([^@[:space:]]+)@([^:[:space:]]+): ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# Extract bare host from `host:path` (rsync / scp without user).
#
# Distinguishing host:path from a local Windows-style drive path
# (`C:\foo`) is the awkward part. Real-world scp/rsync remote paths
# almost always use forward-slash paths after the colon (`host:/tmp/`
# absolute, `host:foo` relative). We accept BOTH forms — relative
# (`host:foo`) AND absolute (`host:/path`) — and require the host name
# to contain at least one `.` OR be at least 4 characters long. That
# heuristic rules out single-letter drive paths (`C:\foo`, `D:/`) while
# admitting realistic short hostnames like `walter-vm.tail.example` or
# `node` / `nas1`. (Sub-4-character bare hostnames like `nas` need the
# operator to pass the full `user@nas:` form so `_host_from_userhostpath`
# matches instead, OR to use the FQDN form which contains a `.`.)
#
# R2 (Copilot) fix: previous regex required non-`/` after `:`, so
# `scp file host:/tmp/` legitimately formatted absolute paths failed
# CLOSED with no extractable host. Real scp/rsync usage is exactly
# `host:/absolute/path`.
_host_from_hostpath() {
  local s="$1"
  # Reject obvious Windows drive paths: single letter + `:\` or `:/`.
  if [[ "$s" =~ ^[A-Za-z]:[\\/] ]]; then
    return 1
  fi
  # Match: HOST : PATH, where HOST contains at least one dot OR is >=4
  # chars (rules out 1-char drives but admits short DNS names).
  if [[ "$s" =~ ^([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+): ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$s" =~ ^([A-Za-z0-9][A-Za-z0-9.-]{3,}): ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Extract host from `[user@]host` (bare ssh target).
_host_from_userhost() {
  local s="$1"
  if [[ "$s" =~ ^([^@[:space:]]+)@([A-Za-z0-9][A-Za-z0-9.-]*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$s" =~ ^([A-Za-z0-9][A-Za-z0-9.-]*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Load the loader function.
# shellcheck disable=SC1090,SC1091
_loader_path="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/walter/lib/egress-loader.sh"
if [[ ! -f "$_loader_path" ]]; then
  _emit_block "network-gate: egress-loader.sh missing at $_loader_path — failing closed."
fi
# shellcheck disable=SC1090
source "$_loader_path"

# Inspect a single shell segment. Detects the CLI + extracts the host(s).
# Returns:
#   0 + STDOUT "ALLOW"           → segment is allowed (no network CLI OR allowlisted)
#   0 + STDOUT "BLOCK: <reason>" → segment is blocked
#
# We collect ALL hosts seen and require ALL of them be allowlisted; the
# first non-allowed one blocks.
_inspect_segment() {
  local seg="$1"
  # Trim leading whitespace
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [[ -z "$seg" ]] && { echo "ALLOW"; return 0; }

  # Tokenize. `read -ra` splits on $IFS (default whitespace) and respects
  # backslash escapes but does NOT honour shell quoting — so
  # `curl "https://api.github.com"` yields the token
  # `"https://api.github.com"` (with quotes). We strip ONE surrounding
  # layer of `'…'` / `"…"` from each token below so URL extraction sees
  # the bare URL. Real-world quoted invocations (especially in CI
  # scripts) were previously fail-CLOSED with no extractable host —
  # Copilot R5 finding.
  local -a tokens raw_tokens
  read -ra raw_tokens <<< "$seg"
  local _t
  tokens=()
  for _t in "${raw_tokens[@]}"; do
    # Strip one layer of matching outer quotes.
    if [[ ${#_t} -ge 2 && "${_t:0:1}" == '"' && "${_t: -1}" == '"' ]]; then
      _t="${_t:1:${#_t}-2}"
    elif [[ ${#_t} -ge 2 && "${_t:0:1}" == "'" && "${_t: -1}" == "'" ]]; then
      _t="${_t:1:${#_t}-2}"
    fi
    tokens+=("$_t")
  done
  # Skip leading shell assignments (`VAR=value`, `FOO=$(cmd)`,
  # `LC_ALL=C cmd …`). These are valid prefix syntax in bash; if the
  # segment is ONLY assignments (no following command) the assignments
  # run in the current shell — there's no CLI to inspect. The
  # _extract_substitutions step at the dispatch layer will catch any
  # `$(curl ...)` inside an assignment value. Codex R3 follow-up: this
  # avoids fail-CLOSED on legitimate `X=$(curl allowed.example/x); ...`
  # which previously had cli=`X=$(curl` → the "unable to identify"
  # branch.
  while [[ ${#tokens[@]} -gt 0 && "${tokens[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    tokens=("${tokens[@]:1}")
  done
  # Segment was pure assignments → no CLI here → ALLOW (any
  # substitution-smuggled CLI was inspected separately).
  if [[ ${#tokens[@]} -eq 0 ]]; then
    echo "ALLOW"
    return 0
  fi
  local cli="${tokens[0]:-}"

  # Strip leading command wrappers + their flags / value-pairs / VAR=val
  # assignments so `sudo -E curl X`, `sudo -u nobody curl X`, `env FOO=bar
  # curl X`, `/usr/bin/env curl X` etc. still resolve to `curl`.
  #
  # Wrappers handled:  sudo, env, nice, nohup, time, stdbuf, setsid,
  #                    chrt, taskset, ionice
  # Value-taking flags for these: sudo -u/-g/-h/-r/-t/-T/-D/-A, env -u/-C.
  # We're conservative: strip 2-token (-X val) form when we recognize
  # the flag; otherwise strip just the flag.
  #
  # R2 finding (B1): without this, `sudo -E curl https://evil.example`
  # silently passed because `-E` wasn't a known CLI → fell to `*) allow`.
  local _strip_more=1
  while [[ "$_strip_more" -eq 1 ]]; do
    _strip_more=0
    case "${cli##*/}" in
      # Codex R3 fix CR2-B: `command` and `exec` are shell builtins
      # that invoke the named binary bypassing functions/aliases —
      # `command curl https://evil.example` was previously treated as
      # an unknown CLI (`cli="command"`) and fell to `*) ALLOW`.
      # `builtin` would let an attacker substitute a function-shadowed
      # name; strip it the same way. (We intentionally do NOT strip
      # `eval` — bash-denylist.sh catches eval-of-variable as RCE.)
      sudo|env|nice|nohup|time|stdbuf|setsid|chrt|taskset|ionice|command|exec|builtin)
        # Drop the wrapper itself.
        tokens=("${tokens[@]:1}")
        # Eat any flags, optional flag values, and VAR=val assignments.
        while [[ ${#tokens[@]} -gt 0 ]]; do
          case "${tokens[0]}" in
            # Value-taking flags (sudo + env). Note: `-N` (sudo's
            # non-interact) and `-S` (sudo's read-password-from-stdin)
            # are VALUELESS — including them previously consumed the
            # NEXT token, which was usually the real CLI, leaving the
            # URL as the new "cli" → unknown → ALLOW (bypass). Copilot
            # R6 finding F22.
            -u|-g|-h|-r|-t|-T|-D|-A|-C)
              tokens=("${tokens[@]:2}") ;;
            # Any other short or long flag: just drop the flag.
            -*)
              tokens=("${tokens[@]:1}") ;;
            # VAR=value (env-style assignment).
            *=*)
              tokens=("${tokens[@]:1}") ;;
            *)
              break ;;
          esac
        done
        cli="${tokens[0]:-}"
        _strip_more=1
        ;;
    esac
  done

  # Strip absolute paths: /usr/bin/curl → curl.
  cli="${cli##*/}"

  # After unwrapping, if the resulting CLI looks suspicious (empty, a
  # leftover flag, or still a VAR=val) we cannot make a safe decision.
  # Fail-CLOSED rather than fall through to the catch-all `*) allow`
  # branch (R2 finding).
  if [[ -z "$cli" || "${cli:0:1}" == "-" || "$cli" == *=* ]]; then
    echo "BLOCK: network-gate: unable to identify the network CLI after stripping wrappers (sudo/env/...). Failing closed. Original segment: ${seg}"
    return 0
  fi

  case "$cli" in
    curl|wget)
      # Extract every URL-like token.
      local found=0 t host
      for t in "${tokens[@]:1}"; do
        if host="$(_host_from_url "$t")" && [[ -n "$host" ]]; then
          found=1
          if ! walter_egress_host_allowed "$host"; then
            echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via '$cli'). Add via: walter-os egress add '$host'"
            return 0
          fi
        fi
      done
      if [[ "$found" -eq 0 ]]; then
        echo "BLOCK: network-gate: '$cli' invoked without an extractable URL host (e.g. '$cli --help'). Run that command outside the agent OR pass a full URL."
        return 0
      fi
      echo "ALLOW"
      return 0
      ;;
    gh)
      # gh's default host is github.com unless GH_HOST is set. We use
      # whichever is configured.
      local gh_host="${GH_HOST:-github.com}"
      if ! walter_egress_host_allowed "$gh_host"; then
        echo "BLOCK: network-gate: '$gh_host' (gh default host) not in egress allowlist. Add via: walter-os egress add '$gh_host'"
        return 0
      fi
      echo "ALLOW"
      return 0
      ;;
    git)
      # Inspect subcommands that touch the network.
      #
      # R2 fixes:
      #   - REMOVED `cherry` (B4) — `git cherry` is local-only (compares
      #     local commits against upstream by reading local refs).
      #   - ADDED `lfs|svn|annex|p4|bundle|send-email` (B5) — these git
      #     extensions DO touch the network and were previously falling
      #     through to the catch-all `*) allow` branch, fully bypassing
      #     the gate.
      #   - `remote` is kept LOCAL-by-default; `git remote -v` and
      #     `git remote add` don't hit the network. The network-touching
      #     `remote update` / `remote show` / `remote prune` subcommands
      #     are rare in agent workflows. If an operator hits one of those
      #     and needs the gate to cover it, they can run with the
      #     two-factor bypass. (Out-of-scope refinement for v0.5.x.)
      #
      # Codex R3 fix CR2-C: walk past git global options
      # (`-C dir`, `-c key=val`, `--git-dir=...`, `--work-tree=...`,
      # `--namespace=...`, `-p` / `--paginate`, `--no-pager`, `--bare`,
      # `--exec-path[=path]`, `--help`, `-v` / `--version`, etc.) before
      # reading the subcommand. Previously `git -c protocol.version=2
      # clone https://evil.example/repo` treated `-c` as the subcommand,
      # fell to the local-only ALLOW branch, and never checked the URL.
      local _gi=1
      while [[ $_gi -lt ${#tokens[@]} ]]; do
        local _gt="${tokens[$_gi]}"
        case "$_gt" in
          # Value-taking global options (next token is the value).
          -C|-c)
            _gi=$((_gi + 2)); continue ;;
          # Value-on-same-token (--flag=value) AND valueless global flags.
          --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--list-cmds=*|--super-prefix=*|--config-env=*|--attr-source=*)
            _gi=$((_gi + 1)); continue ;;
          # Value-taking long options where the value is the NEXT token.
          --git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--list-cmds|--config-env|--attr-source)
            _gi=$((_gi + 2)); continue ;;
          # Valueless global flags.
          -p|--paginate|-P|--no-pager|--no-replace-objects|--no-optional-locks|--bare|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-replace|-v|--version|-h|--help|--html-path|--man-path|--info-path)
            _gi=$((_gi + 1)); continue ;;
          *)
            break ;;
        esac
      done
      local sub="${tokens[$_gi]:-}"
      # Note: `remote` and `submodule` are deliberately NOT in this list
      # — their COMMON forms are local (`git remote -v`,
      # `git submodule status`, `git submodule init` reading .gitmodules).
      # The rare network-using subforms (`git remote update`,
      # `git submodule update --remote`) are operator-explicit and can
      # use the two-factor bypass. Copilot R2 finding: keeping them
      # in the list blocked the common local invocation as "implicit
      # remote".
      case "$sub" in
        clone|fetch|pull|push|ls-remote|fetch-pack|send-pack|http-fetch|http-push|imap-send|upload-pack|upload-archive|receive-pack|bundle|send-email|lfs|svn|annex|p4|cvsimport|cvsexportcommit)
          local t host found=0
          # Scan tokens AFTER the subcommand position (_gi). Was
          # hard-coded to ${tokens[@]:2} pre-CR2-C, which silently
          # ignored URLs when git global options were present.
          for t in "${tokens[@]:$((_gi + 1))}"; do
            if host="$(_host_from_url "$t")" && [[ -n "$host" ]]; then
              found=1
            elif host="$(_host_from_userhostpath "$t")" && [[ -n "$host" ]]; then
              found=1
            else
              continue
            fi
            if ! walter_egress_host_allowed "$host"; then
              echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via 'git $sub'). Add via: walter-os egress add '$host'"
              return 0
            fi
          done
          if [[ "$found" -eq 0 ]]; then
            # `git fetch` with no explicit remote uses the configured
            # upstream — implicit host. Fail-CLOSED per spec. Same for
            # `git lfs push` etc. without an explicit remote.
            echo "BLOCK: network-gate: 'git $sub' uses an implicit remote (no URL on the command line). Pass the remote URL explicitly OR allowlist the configured remote's host with WALTER_EGRESS_ALLOW_OVERRIDE=1 + --allow-egress-outbound."
            return 0
          fi
          echo "ALLOW"
          return 0
          ;;
        archive)
          # `git archive` is local by default but `--remote=URL` (or
          # the space-separated `--remote URL`) makes it network. If
          # --remote is present, require URL extraction; otherwise pass
          # through. R6 finding F20: previous code only handled the
          # `=`-form, fail-CLOSED on the space form even though the URL
          # was right there on the command line.
          local _i=$((_gi + 1)) found_remote=0 found=0 host remote_url=""
          while [[ $_i -lt ${#tokens[@]} ]]; do
            local _tok="${tokens[$_i]}"
            case "$_tok" in
              --remote=*)
                found_remote=1
                remote_url="${_tok#--remote=}"
                _i=$((_i + 1))
                ;;
              --remote)
                # Space-separated form: next token is the URL.
                found_remote=1
                remote_url="${tokens[$((_i + 1))]:-}"
                _i=$((_i + 2))
                ;;
              *)
                _i=$((_i + 1)) ;;
            esac
            if [[ -n "$remote_url" ]]; then
              if host="$(_host_from_url "$remote_url")" && [[ -n "$host" ]]; then
                found=1
                walter_egress_host_allowed "$host" || {
                  echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via 'git archive --remote')."; return 0;
                }
              fi
              remote_url=""
            fi
          done
          if [[ "$found_remote" -eq 1 && "$found" -eq 0 ]]; then
            echo "BLOCK: network-gate: 'git archive --remote' present but URL host could not be extracted. Failing closed."
            return 0
          fi
          echo "ALLOW"
          return 0
          ;;
        *)
          # Local-only git operation (status, log, diff, add, commit,
          # cherry, branch, tag, stash, reset, rebase, …).
          echo "ALLOW"
          return 0
          ;;
      esac
      ;;
    ssh)
      # Target is the first non-flag positional. ssh has flag args that
      # take values (`-i keyfile`, `-p port`, `-o opt=val`, …) — skip
      # both flag + value to avoid mistaking the value for the host.
      # R6 finding F21: `-J jumphost` was previously eaten as a
      # value-taking flag without validating the jumphost. That let
      # `ssh -J evil.example allowed.example` reach `evil.example`
      # because only `allowed.example` was checked. Now -J's value is
      # extracted + checked against the allowlist BEFORE we look at the
      # target. The jumphost arg can be comma-separated for chained
      # jumps (`-J host1,host2`) — we check every entry.
      local i=1 target="" jumphosts=""
      while [[ $i -lt ${#tokens[@]} ]]; do
        local tok="${tokens[$i]}"
        case "$tok" in
          -J)
            jumphosts="${tokens[$((i + 1))]:-}"
            i=$((i + 2)); continue ;;
          -i|-p|-o|-l|-F|-L|-R|-D|-B|-b|-c|-E|-e|-I|-m|-O|-Q|-S|-W|-w)
            i=$((i + 2)); continue ;;
          -*)
            i=$((i + 1)); continue ;;
          *)
            target="$tok"; break ;;
        esac
      done
      # Validate every jumphost in the chain.
      if [[ -n "$jumphosts" ]]; then
        local _jh
        local _IFSold="$IFS"; IFS=','
        for _jh in $jumphosts; do
          IFS="$_IFSold"
          local jhost
          jhost="$(_host_from_userhost "$_jh")" || jhost=""
          if [[ -z "$jhost" ]]; then
            echo "BLOCK: network-gate: 'ssh -J' jumphost not parseable: $_jh"
            return 0
          fi
          if ! walter_egress_host_allowed "$jhost"; then
            echo "BLOCK: network-gate: '$jhost' (ssh -J jumphost) not in egress allowlist. Add via: walter-os egress add '$jhost'"
            return 0
          fi
        done
        IFS="$_IFSold"
      fi
      if [[ -z "$target" ]]; then
        echo "BLOCK: network-gate: 'ssh' invoked without a target host."
        return 0
      fi
      local host
      host="$(_host_from_userhost "$target")" || host=""
      if [[ -z "$host" ]]; then
        echo "BLOCK: network-gate: 'ssh' target not parseable: $target"
        return 0
      fi
      if ! walter_egress_host_allowed "$host"; then
        echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via 'ssh'). Add via: walter-os egress add '$host'"
        return 0
      fi
      echo "ALLOW"
      return 0
      ;;
    scp|rsync)
      # Look for the first token that contains `user@host:` OR `host:`
      # (with `:` followed by a non-`/`, to distinguish from
      # Windows-style or local paths).
      local t host found=0
      for t in "${tokens[@]:1}"; do
        if host="$(_host_from_userhostpath "$t")" && [[ -n "$host" ]]; then
          found=1
        elif host="$(_host_from_hostpath "$t")" && [[ -n "$host" ]]; then
          found=1
        elif host="$(_host_from_url "$t")" && [[ -n "$host" ]]; then
          # rsync://host/module form
          found=1
        else
          continue
        fi
        if ! walter_egress_host_allowed "$host"; then
          echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via '$cli'). Add via: walter-os egress add '$host'"
          return 0
        fi
      done
      if [[ "$found" -eq 0 ]]; then
        echo "BLOCK: network-gate: '$cli' invoked without an extractable host (no user@host:path / rsync:// URL on the command line)."
        return 0
      fi
      echo "ALLOW"
      return 0
      ;;
    nc|ncat|netcat)
      # First non-flag positional is the host.
      local target
      target="$(_first_positional "${tokens[@]:1}")" || target=""
      if [[ -z "$target" ]]; then
        echo "BLOCK: network-gate: '$cli' invoked without a target host."
        return 0
      fi
      if ! walter_egress_host_allowed "$target"; then
        echo "BLOCK: network-gate: '$target' not in egress allowlist (matched via '$cli'). Add via: walter-os egress add '$target'"
        return 0
      fi
      echo "ALLOW"
      return 0
      ;;
    pip|pip3|npm|pnpm|yarn|uv|uvx|cargo|brew|gem|go)
      # These read host config from environment / config files. Per spec
      # AC-2, fail-CLOSED on implicit host.
      #
      # An OPERATOR who explicitly passes `--index-url` / `--registry` /
      # equivalent can extract a parseable host — we honour that. The
      # absence of any URL token in the command line is the trigger to
      # block. Codex R2 finding C1: previously we only ran
      # `_host_from_url` against each TOKEN, but `--registry=URL` /
      # `--index-url=URL` puts the URL inside the token (after `=`),
      # so the regex (anchored on `^scheme://`) didn't match. Now we
      # peel the `--<flag>=` prefix before extraction.
      local t host found=0 url_candidate
      for t in "${tokens[@]:1}"; do
        url_candidate="$t"
        case "$t" in
          --*=*) url_candidate="${t#*=}" ;;
        esac
        if host="$(_host_from_url "$url_candidate")" && [[ -n "$host" ]]; then
          found=1
          if ! walter_egress_host_allowed "$host"; then
            echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via '$cli'). Add via: walter-os egress add '$host'"
            return 0
          fi
        fi
      done
      if [[ "$found" -eq 0 ]]; then
        echo "BLOCK: network-gate: '$cli' uses an implicit host (config/env). Explicitly pass --index-url / --registry / equivalent host argument, OR allowlist the default host and re-run with WALTER_EGRESS_ALLOW_OVERRIDE=1 + --allow-egress-outbound."
        return 0
      fi
      echo "ALLOW"
      return 0
      ;;
    *)
      # Unknown / not a network CLI — pass.
      echo "ALLOW"
      return 0
      ;;
  esac
}

# Two-factor bypass: if both signals present, allow with WARN and exit.
if _two_factor_bypass_active; then
  _emit_allow_with_warn "network-gate: two-factor bypass active (WALTER_EGRESS_ALLOW_OVERRIDE=1 + --allow-egress-outbound). Command allowed with operator acknowledgment."
fi

# Inspect each segment. First BLOCK wins.
# Codex R3 CR2-A: also extract command/process substitutions ($(...),
# <(...), `...`) from each segment and inspect THEIR bodies as
# synthetic segments. This catches `echo $(curl https://evil.example)`
# which would otherwise classify on `echo` (a local builtin) and miss
# the curl entirely.
_inspect_and_dispatch() {
  local seg="$1"
  [[ -z "${seg// }" ]] && return 0
  local result
  result="$(_inspect_segment "$seg")"
  case "$result" in
    ALLOW) ;;
    BLOCK:\ *)
      _emit_block "${result#BLOCK: }" ;;
    *)
      _emit_block "network-gate: unexpected inspector output: $result" ;;
  esac
}

while IFS= read -r _segment; do
  [[ -z "${_segment// }" ]] && continue
  # Inspect the segment as-is first.
  _inspect_and_dispatch "$_segment"
  # Then recurse into any command/process substitutions it contains.
  while IFS= read -r _subst_body; do
    [[ -z "${_subst_body// }" ]] && continue
    _inspect_and_dispatch "$_subst_body"
  done < <(_extract_substitutions "$_segment")
done < <(_split_segments "$CMD")

_emit_allow
