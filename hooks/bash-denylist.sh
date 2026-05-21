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
if [[ -n "${BASH_VERSION:-}" && "${BASH_VERSION%%.*}" -lt 4 ]]; then
  # One-shot guard: if we already attempted a re-exec and ended up back in
  # bash < 4, stop. Without this, a candidate path that itself resolves to
  # bash 3.2 (e.g., symlink chain) would loop forever. Codex review of #81.
  if [[ "${WALTER_BASH_DENYLIST_REEXEC:-0}" == "1" ]]; then
    printf '%s\n' '{"decision":"block","reason":"bash-denylist: re-exec landed on bash < 4 again. Refusing to loop. Install GNU bash >= 4 and ensure it is first on PATH or at /opt/homebrew/bin/bash."}'
    exit 0
  fi
  # Use BASH_SOURCE[0] (the script's actual path) rather than $0, which can
  # be just a bare filename when invoked via PATH lookup and would fail
  # ENOENT under the re-exec. Codex review of #81.
  _self="${BASH_SOURCE[0]}"
  for _candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_candidate" && -f "$_self" ]]; then
      WALTER_BASH_DENYLIST_REEXEC=1 exec "$_candidate" "$_self" "$@"
    fi
  done
  # No newer bash available — emit fail-CLOSED block so the hook does
  # not silently fail-open. Use printf to stay consistent with the rest
  # of the hook's JSON-output convention.
  printf '%s\n' '{"decision":"block","reason":"bash-denylist: requires bash >= 4.0 (macOS /bin/bash 3.2 does not support declare -A). Install brew bash or upgrade /bin/bash."}'
  exit 0
fi
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

# Extract command (using jq if available, fail-closed otherwise)
if ! command -v jq >/dev/null 2>&1; then
  # Fail CLOSED — without jq we cannot parse the hook event.
  # Allowing all ops when jq is missing would let an attacker bypass the hook
  # by shadowing jq on PATH. See approval-gate.sh P0-03 for the same pattern.
  printf '{"decision":"block","reason":"bash-denylist: jq missing — failing closed for safety. Install jq to proceed."}\n'
  exit 0
fi

# Extract command. Fail CLOSED if jq cannot parse the input or the command
# field is absent / empty — we cannot make a security decision about a
# command we cannot read. Codex R2 MEDIUM M4: previously, malformed JSON or
# jq parse failure was silently coerced to CMD="" via `// ""`, causing the
# hook to fall through to "allow".
if ! CMD="$(printf '%s' "$INPUT" | jq -er '.tool_input.command // empty' 2>/dev/null)"; then
  printf '{"decision":"block","reason":"bash-denylist: cannot parse hook input (malformed JSON or missing tool_input.command) — failing closed for safety."}\n'
  exit 0
fi
if [[ -z "$CMD" ]]; then
  printf '{"decision":"block","reason":"bash-denylist: empty command in hook input — failing closed for safety."}\n'
  exit 0
fi

# Two-factor bypass: requires WALTER_DENYLIST_BYPASS=1 (operator opt-in via env)
# AND the literal flag `--allow-denylist-pattern` (acknowledgment in the command).
# Either alone does NOT bypass. See header comment for rationale (Codex R2 M1).
if [[ "${WALTER_DENYLIST_BYPASS:-0}" == "1" ]] \
  && echo "$CMD" | grep -qF -- '--allow-denylist-pattern'; then
  printf '{"decision":"allow","systemMessage":"bash-denylist: two-factor bypass used (WALTER_DENYLIST_BYPASS=1 + --allow-denylist-pattern). Command allowed with operator acknowledgment."}\n'
  exit 0
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
# bash -c / sh -c with command substitution: `bash -c "$(curl ...)"`, etc.
# This also catches `bash -c "$(cat /tmp/payload)"`. Mirror of python-c-variable.
#
# Whitespace-after-`-c` is OPTIONAL. Copilot review of #81 flagged that
# requiring `[[:space:]]+` after `-c` left `bash -c'...'` / `sh -c"..."` (no
# space — valid POSIX shell syntax) as a bypass. We now allow zero or more
# whitespace between `-c` and the opening quote.
DENYLIST_PATTERNS[shell-c-variable]='(^|[[:space:]])(bash|zsh|ksh|dash|sh)[[:space:]]+-c[[:space:]]*["'\'']?\$[{(]'
# Sibling pattern: backtick command substitution `bash -c "`curl …`"`. Codex
# R2 of PR #63 flagged this gap (issue #3 P2-1). Backticks are still common
# in older shell snippets / man pages / one-liners.
#
# Match relaxation per Copilot review of #81: the backtick may appear after
# the opening quote with arbitrary intermediate characters (whitespace,
# escaped backticks `\``, leading text), since `bash -c "...`...`..."` is the
# typical real-world form. We anchor on the `(bash|sh|zsh|dash|ksh) -c <quote> ... \?\``
# shape: shell + `-c` + optional quote + any chars (incl. backslash-escape)
# then a backtick.
DENYLIST_PATTERNS[shell-c-backtick]='(^|[[:space:]])(bash|zsh|ksh|dash|sh)[[:space:]]+-c[[:space:]]*["'\'']?[^`]*`'
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

for pattern_name in "${!DENYLIST_PATTERNS[@]}"; do
  pattern="${DENYLIST_PATTERNS[$pattern_name]}"
  if echo "$CMD" | grep -qE "$pattern"; then
    # Truncate command to 120 chars for the reason string
    truncated="${CMD:0:120}"
    # Use jq to safely construct the JSON reason (handles special chars)
    reason="bash-denylist: command matches blocked pattern '${pattern_name}': ${truncated}"
    printf '{"decision":"block","reason":%s}\n' "$(jq -n --arg r "$reason" '$r')"
    exit 0
  fi
done

# No pattern matched — allow
printf '{"decision":"allow"}\n'
exit 0
